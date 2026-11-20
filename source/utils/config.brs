' "Registry" is where Roku stores config

' Read config tree from json config file and cache per component/task scope
function GetConfigTree()
    if m._configTree = invalid
        m._configTree = ParseJSON(ReadAsciiFile("pkg:/settings/settings.json"))
    end if
    return m._configTree
end function


' Generic registry accessors
function registry_read(key, section = invalid)
    if section = invalid then return invalid
    reg = CreateObject("roRegistrySection", section)
    if reg.exists(key) then return reg.read(key)
    return invalid
end function

sub registry_write(key, value, section = invalid)
    if section = invalid then return
    reg = CreateObject("roRegistrySection", section)
    reg.write(key, value)
    reg.flush()
end sub

sub registry_delete(key, section = invalid)
    if section = invalid then return
    reg = CreateObject("roRegistrySection", section)
    reg.delete(key)
    reg.flush()
end sub


' "StitchRevitalizedForRoku" registry accessors for the default global settings
function get_setting(key, default = invalid)
    value = registry_read(key, m.global.appid)
    if value = invalid then return default
    return value
end function

sub set_setting(key, value)
    registry_write(key, value, m.global.appid)
end sub

sub unset_setting(key)
    registry_delete(key, m.global.appid)
end sub


' User registry accessors for the currently active user
function get_user_setting(key, default = invalid)
    activeUser = get_setting("active_user")
    if activeUser = invalid then return default
    value = registry_read(key, activeUser)
    if value = invalid

        ' Check for default in Config Tree
        configTree = GetConfigTree()
        configKey = findConfigTreeKey(key, configTree)

        if configKey <> invalid and configKey.default <> invalid
            registry_write(key, configKey.default, activeUser) ' Set user setting to default
            return configKey.default
        end if

        return default
    end if
    return value
end function

sub set_user_setting(key, value)
    if get_setting("active_user") = invalid then return
    registry_write(key, value, get_setting("active_user"))
end sub

sub unset_user_setting(key)
    if get_setting("active_user") = invalid then return
    registry_delete(key, get_setting("active_user"))
end sub


' Recursivly search the config tree for entry with settingname equal to key
function findConfigTreeKey(key as string, tree)
    for each item in tree
        if item.settingName <> invalid and item.settingName = key then return item

        if item.children <> invalid and item.children.Count() > 0
            result = findConfigTreeKey(key, item.children)
            if result <> invalid then return result
        end if
    end for

    return invalid
end function

sub NukeRegistry(section = invalid)
    ? "Erasing Registry"
    Registry = CreateObject("roRegistry")
    if section = invalid
        for each section in Registry.GetSectionList()
            RegistrySection = CreateObject("roRegistrySection", section)
            for each key in RegistrySection.GetKeyList()
                print "Deleting " section + ":" key
                RegistrySection.Delete(key)
            end for
            RegistrySection.flush()
            Registry.Delete(section)
        end for
    else
        RegistrySection = CreateObject("roRegistrySection", section)
        for each key in RegistrySection.GetKeyList()
            print "Deleting " section + ":" key
            RegistrySection.Delete(key)
        end for
        RegistrySection.flush()
    end if

end sub

' True when the user turned the built-in splitter on and the remote kill switch
' has not turned it off. Remote "true" never forces it on.
function isBuiltinSplitterEnabled() as boolean
    if get_user_setting("proxy.builtin", "false") <> "true" then return false
    remote = m.global.remoteConfig
    if type(remote) = "roAssociativeArray" and remote.builtinSplitter = false then return false
    return true
end function

' True unless the remote kill switch turned the live-list ad fix off (default on, also before the config arrives).
function isAdFixEnabled() as boolean
    remote = m.global.remoteConfig
    return not (type(remote) = "roAssociativeArray" and remote.adFix = false)
end function

' Starts the built-in server once, when the splitter is enabled or the live-list ad fix is on
' (remote adFix defaults to true until the config arrives). Enhanced streams are split only when
' isBuiltinSplitterEnabled().
sub startBuiltinSplitter()
    if m.global.demuxServer <> invalid then return
    if not isBuiltinSplitterEnabled() and not isAdFixEnabled() then return
    demuxServer = CreateObject("roSGNode", "DemuxServer")
    demuxServer.control = "RUN"
    m.global.addFields({ demuxServer: demuxServer })
end sub
