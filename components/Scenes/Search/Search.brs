sub init()
    m.top.observeField("focusedChild", "onGetfocus")
    m.searchTitle = m.top.findNode("searchTitle")
    if m.searchTitle <> invalid then m.searchTitle.text = tr("Search")
    m.recents = m.top.findnode("recents")
    if m.recents <> invalid
        recentsFont = CreateObject("roSGNode", "Font")
        recentsFont.uri = "pkg:/fonts/Archivo-Regular.otf"
        recentsFont.size = 18
        recentsFocusedFont = CreateObject("roSGNode", "Font")
        recentsFocusedFont.uri = "pkg:/fonts/Archivo-Bold.otf"
        recentsFocusedFont.size = 18
        m.recents.textFont = recentsFont
        m.recents.focusedTextFont = recentsFocusedFont
        m.recents.textColor = "0xADADB8FF"
        m.recents.focusedTextColor = "0xFFFFFFFF"
        m.recents.observeField("buttonSelected", "onRecentItemSelected")
    end if
    m.kb = m.top.findNode("keyboard")
    m.kb.textEditBox.hintText = tr("Enter Search Query")
    m.kb.textEditBox.voiceEnabled = true
    m.kb.observefield("text", "handleTextInput")
    m.rowlist = m.top.findNode("homeRowList")
    styleRowListHeader(m.rowlist)
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.searchDebounceTimer = createObject("roSGNode", "Timer")
    m.searchDebounceTimer.duration = 0.3
    m.searchDebounceTimer.repeat = false
    m.searchDebounceTimer.observeField("fire", "executeSearch")
    updateRecents()
end sub

sub updateRecents(appendItem = invalid)
    oldRecents = ParseJson(get_user_setting("recents", "[]"))
    if oldRecents = invalid
        oldRecents = []
    end if
    newRecents = []
    if appendItem <> invalid
        newRecents.Push(appendItem)
    end if
    for each item in oldRecents
        i = newRecents.count()
        if i < 3
            if item <> appendItem
                newRecents.Push(item)
            end if
        end if
    end for
    set_user_setting("recents", FormatJson(newRecents, 256))
    m.recents.buttons = ParseJson(get_user_setting("recents", "[]"))
    adjustPositionForRecents()
end sub

sub onRecentItemSelected()
    selectedText = m.recents.buttons[m.recents.buttonSelected].tostr()
    ? "SelectedText: "; selectedText
    m.kb.setfocus(true)
    m.kb.text = selectedText
end sub

sub adjustPositionForRecents()
    yTranslation = 174
    if m.recents.buttons.count() > 0
        yTranslation = 174 + (m.recents.buttons.count() * 52) + 16
    end if
    m.kb.translation = [132, yTranslation]
end sub

sub handleTextInput()
    if m.kb.text <> invalid and m.kb.text <> ""
        m.rowlist.visible = false
        m.rowlist.content = invalid
        if m.searchDebounceTimer <> invalid
            m.searchDebounceTimer.control = "stop"
            m.searchDebounceTimer.control = "start"
        else
            executeSearch()
        end if
    else
        if m.searchDebounceTimer <> invalid then m.searchDebounceTimer.control = "stop"
        m.GetContentTask = destroyTask(m.GetContentTask, "response")
        m.rowlist.visible = false
        m.rowlist.content = invalid
    end if
end sub

sub executeSearch()
    if m.kb = invalid or m.kb.text = invalid or m.kb.text = "" then return
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.GetContentTask = createApiTask("getSearchQuery", "handleRecommendedSections", { query: m.kb.text.toStr() })
end sub

sub handleRecommendedSections()
    rsp = m.GetContentTask.response
    if rsp = invalid then return
    buildContentNodeFromShelves(rsp)
end sub

sub buildContentNodeFromShelves(shelves)
    LiveChannels = []
    Users = []
    Games = []
    Vods = []
    for each item in shelves.channels
        rowItem = {}
        if item.stream <> invalid
            rowItem.contentType = "LIVE"
        else
            rowItem.contentType = "USER"
        end if
        if rowItem.contentType = "LIVE"
            if item.stream.broadcaster = invalid then continue for
            rowItem.contentId = item.stream.Id
            rowItem.createdAt = item.stream.createdAt
            rowItem.previewImageURL = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", item.stream.broadcaster.login, "1280", "720")
            rowItem.contentTitle = item.stream.broadcaster.broadcastSettings?.title
            rowItem.viewersCount = item.stream.viewersCount
            rowItem.streamerDisplayName = item.stream.broadcaster.displayName
            rowItem.streamerLogin = item.stream.broadcaster.login
            rowItem.streamerId = item.stream.broadcaster.id
            rowItem.streamerProfileImageUrl = item.stream.broadcaster.profileImageURL
            if item.stream.game <> invalid
                rowItem.gameDisplayName = item.stream.game.displayName
                if item.stream.game.boxArtUrl <> invalid
                    rowItem.gameBoxArtUrl = formatTwitchImageUrl(item.stream.game.boxArtUrl, "188", "250")
                end if
                rowItem.gameId = item.stream.game.Id
                rowItem.gameName = item.stream.game.name
            end if
            LiveChannels.push(rowItem)
        end if
        if rowItem.contentType = "USER"
            rowItem.contentId = item.Id
            rowItem.previewImageURL = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", item.login, "1280", "720")
            rowItem.contentTitle = item.displayName
            rowItem.followerCount = item.followers?.totalCount
            rowItem.streamerDisplayName = item.displayName
            rowItem.streamerLogin = item.login
            rowItem.streamerId = item.id
            rowItem.streamerProfileImageUrl = item.profileImageURL
            Users.push(rowItem)
        end if
    end for
    for each game in shelves.games
        rowItem = {}
        rowItem.contentId = game.Id
        rowItem.contentType = "GAME"
        rowItem.viewersCount = game.viewersCount
        rowItem.contentTitle = game.displayName
        rowItem.gameDisplayName = game.displayName
        if game.boxArtUrl <> invalid
            rowItem.gameBoxArtUrl = formatTwitchImageUrl(game.boxArtUrl, "188", "250")
        end if
        rowItem.gameId = game.Id
        rowItem.gameName = game.name
        Games.push(rowItem)
    end for
    for each VOD in shelves.videos
        if VOD.owner = invalid then continue for
        rowItem = {}
        rowItem.contentType = "VOD"
        rowItem.contentId = VOD.Id
        if VOD.previewThumbnailURL <> invalid
            rowItem.previewImageURL = formatTwitchImageUrl(VOD.previewThumbnailURL, "640", "360")
        else if VOD.thumbnailURL <> invalid
            rowItem.previewImageURL = formatTwitchImageUrl(VOD.thumbnailURL, "640", "360")
        end if
        rowItem.contentTitle = VOD.title
        rowItem.viewersCount = VOD.viewCount
        rowItem.streamerDisplayName = VOD.owner.displayName
        rowItem.streamerLogin = VOD.owner.login
        rowItem.streamerId = VOD.owner.id
        if VOD.game <> invalid
            rowItem.gameDisplayName = VOD.game.displayName
            if VOD.game.boxArtUrl <> invalid
                rowItem.gameBoxArtUrl = formatTwitchImageUrl(VOD.game.boxArtUrl, "188", "250")
            end if
            rowItem.gameId = VOD.game.Id
            rowItem.gameName = VOD.game.name
        end if
        Vods.push(rowItem)
    end for
    AllContent = createObject("roSGNode", "ContentNode")
    firstRow = createObject("roSGNode", "ContentNode")
    firstRow.title = tr("Live Channels")
    for each stream in LiveChannels
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        setTwitchContentFields(rowItem, stream)
        firstRow.appendChild(rowItem)
    end for
    secondRow = createObject("roSGNode", "ContentNode")
    secondRow.title = tr("Channels")
    for each User in Users
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        setTwitchContentFields(rowItem, User)
        secondRow.appendChild(rowItem)
    end for
    thirdRow = createObject("roSGNode", "ContentNode")
    thirdRow.title = tr("Categories")
    for each Game in Games
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        setTwitchContentFields(rowItem, Game)
        thirdRow.appendChild(rowItem)
    end for
    fourthRow = createObject("roSGNode", "ContentNode")
    fourthRow.title = tr("VODs")
    for each Vod in Vods
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        setTwitchContentFields(rowItem, Vod)
        fourthRow.appendChild(rowItem)
    end for
    ' set content and heights
    rowItemSize = []
    rowHeights = []
    if firstRow.getChildCount() > 0
        streamRow = getRowConfig("LIVE", true)
        rowItemSize.push(streamRow.itemSize)
        rowHeights.push(streamRow.rowHeight)
        AllContent.appendChild(firstRow)
    end if
    if secondRow.getchildCount() > 0
        userRow = getRowConfig("USER", true)
        rowItemSize.push(userRow.itemSize)
        rowHeights.push(userRow.rowHeight)
        AllContent.appendChild(secondRow)
    end if
    if thirdRow.getchildCount() > 0
        gameRow = getRowConfig("GAME", true)
        rowItemSize.push(gameRow.itemSize)
        rowHeights.push(gameRow.rowHeight)
        AllContent.appendChild(thirdRow)
    end if
    if fourthRow.getchildCount() > 0
        streamRow = getRowConfig("LIVE", true)
        rowItemSize.push(streamRow.itemSize)
        rowHeights.push(streamRow.rowHeight)
        AllContent.appendchild(fourthRow)
    end if
    m.rowlist.visible = false
    m.rowlist.content = AllContent
    m.rowlist.rowHeights = rowHeights
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.visible = true
end sub


sub handleItemSelected()
    if m.kb.text <> ""
        updateRecents(m.kb.text)
    end if
    if m.rowlist.content = invalid then return
    if m.rowlist.rowItemSelected = invalid then return
    if m.rowlist.rowItemSelected.count() < 2 then return
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    if selectedRow = invalid then return
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    m.top.contentSelected = selectedItem
end sub


sub onGetFocus()
    if m.rowlist.focusedchild <> invalid
        if m.rowlist.focusedChild.id = "homeRowList"
            m.rowlist.focusedChild.setFocus(true)
        end if
    else if m.top.focusedChild <> invalid
        if m.top.focusedChild.id = "Search"
            m.kb.setFocus(true)
        else if m.top.focusedChild.id = "homeRowList"
            m.rowlist.setfocus(true)
        end if
    else
        m.top.setfocus(true)
    end if
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene; restore on return.
sub updateRowListFocusFeedback()
    if m.rowlist = invalid then return
    hasFocus = false
    if m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
        hasFocus = true
    end if
    m.rowlist.drawFocusFeedback = hasFocus
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        ? "Search Key Press: "; key
        if key = "right"
            if m.top.focusedChild <> invalid and (m.top.focusedChild.id = "keyboard" or m.top.focusedChild.id = "recents")
                m.kb.setfocus(false)
                m.rowlist.setfocus(true)
                return true
            end if
        end if
        if key = "left"
            if m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
                m.rowlist.setfocus(false)
                m.kb.setfocus(true)
                return true
            end if
        end if
        if key = "up" or key = "back"
            if m.top?.focusedChild?.id <> invalid and m.top.focusedChild.id = "keyboard"
                if m.recents.buttons.count() > 0
                    m.recents.setfocus(true)
                    ' m.kb.setfocus(false)
                    return true
                end if
            end if
            m.rowlist.setfocus(false)
            m.kb.setfocus(false)
            m.top.backPressed = true
            return true
        end if
        if key = "down"
            if m.top?.focusedChild?.id <> invalid and m.top.focusedChild.id = "recents"
                m.kb.setfocus(true)
                return true
            end if
        end if
    end if
    return false
end function

sub onDestroy()
    m.top.unobserveField("focusedChild")
    if m.recents <> invalid then m.recents.unobserveField("buttonSelected")
    if m.kb <> invalid then m.kb.unobserveField("text")
    if m.rowlist <> invalid then m.rowlist.unobserveField("itemSelected")
    if m.searchDebounceTimer <> invalid
        m.searchDebounceTimer.control = "stop"
        m.searchDebounceTimer.unobserveField("fire")
    end if
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
end sub
