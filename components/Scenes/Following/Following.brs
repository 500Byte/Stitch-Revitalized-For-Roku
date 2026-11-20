sub init()
    m.top.observeField("focusedChild", "onGetfocus")
    ? "init"; TimeStamp()
    ' m.top.observeField("itemFocused", "onGetFocus")
    m.rowlist = m.top.findNode("homeRowList")
    styleRowListHeader(m.rowlist)
    m.heroBackdrop = m.top.findNode("heroBackdrop")
    m.heroLivePill = m.top.findNode("heroLivePill")
    m.heroLiveBg = m.top.findNode("heroLiveBg")
    m.heroLiveLabel = m.top.findNode("heroLiveLabel")
    m.heroStreamer = m.top.findNode("heroStreamer")
    m.heroMetaLine = m.top.findNode("heroMetaLine")
    m.heroTitle = m.top.findNode("heroTitle")
    m.pendingBackdropUrl = ""
    m.heroDebounceTimer = createTimer(0.15, "applyHeroBackdrop", false)
    if m.heroDebounceTimer <> invalid then m.heroDebounceTimer.control = "stop"
    ' m.allChannels = m.top.findNode("allChannels")
    ' m.allChannels.observeField("itemSelected", "handleItemSelected")
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.rowlist.ObserveField("rowItemFocused", "onRowItemFocused")
    m.offlineList = m.top.findNode("offlineList")
    m.loading = true
    m.lastLoad = 0
    m.GetContentTask = createApiTask("getFollowingPageQuery", "decideRoute")
    m.refreshTimer = createTimer(120, "onRefreshTimer", true)
end sub

function isLoggedIn() as boolean
    user = get_setting("active_user")
    return not m.top.anonymous and user <> invalid and user <> "$default$"
end function

' Following is the visible screen only while heroScene has no channel, game or player page on top of it.
function isTopScene() as boolean
    parent = m.top.getParent()
    if parent = invalid then return false
    for each child in parent.getChildren(-1, 0)
        kind = child.subtype()
        if kind = "ChannelPage" or kind = "GamePage" or kind = "VideoPlayer" then return false
    end for
    return true
end function

sub onRefreshTimer()
    refreshFollowing(0)
end sub

' Silent reload; skipped for anonymous users, hidden screen, in-flight load or a load newer than minAge seconds.
sub refreshFollowing(minAge as integer)
    if m.loading or not isLoggedIn() or not isTopScene() then return
    if CreateObject("roDateTime").AsSeconds() - m.lastLoad < minAge then return
    m.loading = true
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    m.GetContentTask = createApiTask("getFollowingPageQuery", "decideRoute")
end sub

sub decideRoute()
    ? "DecideRoute"; TimeStamp()
    m.loading = false
    if m.GetContentTask.response <> invalid
        m.lastLoad = CreateObject("roDateTime").AsSeconds()
        ' Count the next timer refresh from this load, so a return refresh and a tick don't run back to back.
        m.refreshTimer.control = "stop"
        m.refreshTimer.control = "start"
    end if
    if isLoggedIn()
        ? "Route -> handleRecommendedSections"
        handleRecommendedSections()
    else
        ? "Route -> handleDefaultSections"
        handleDefaultSections()
    end if
end sub

sub handleDefaultSections()
    rsp = m.GetcontentTask.response
    if rsp = invalid or rsp.shelves = invalid or rsp.shelves.count() = 0 then return
    contentCollection = createObject("RoSGNode", "ContentNode")
    for each shelf in rsp.shelves
        ' Skip any GAME-tile shelf (e.g., "Categories we think you'll like").
        ' GAME tiles render with the wrong row height in the shared RowList,
        ' which only handles LIVE stream tiles correctly. See TODO.md.
        isGameShelf = shelf.streams <> invalid and shelf.streams.count() > 0 and shelf.streams[0].contentType = "GAME"
        if not isGameShelf
            row = createObject("RoSGNode", "ContentNode")
            row.title = shelf.title
            for each stream in shelf.streams
                rowItem = createObject("RoSGNode", "TwitchContentNode")
                setTwitchContentFields(rowItem, stream)
                row.appendChild(rowItem)
            end for
            if row.getchildcount() > 0
                contentCollection.appendChild(row)
            end if
        end if
    end for
    updateRowList(contentCollection)
end sub



sub handleRecommendedSections()
    ? "handleRecommendedSections: "; TimeStamp()
    contentCollection = createObject("RoSGNode", "ContentNode")
    rsp = m.GetcontentTask.response
    if rsp = invalid then return
    try
        if rsp.liveFollows <> invalid and rsp.liveFollows.count() > 0
            row = createObject("RoSGNode", "ContentNode")
            row.title = tr("followedLiveUsers")
            for each liveItem in rsp.liveFollows
                twitchContentNode = createObject("roSGNode", "TwitchContentNode")
                setTwitchContentFields(twitchContentNode, liveItem)
                row.appendChild(twitchContentNode)
            end for
            if row.getChildCount() > 0
                contentCollection.appendChild(row)
            end if
        end if
    catch e
        ? "[Following] handleRecommendedSections: live follows parse error: "; e
    end try
    try
        if rsp.shelves <> invalid and rsp.shelves.count() > 0
            shelvesAdded = 0
            for each shelf in rsp.shelves
                if shelf.streams = invalid or shelf.streams.count() = 0 then continue for
                if shelf.streams[0].contentType = "GAME" then continue for
                row = createObject("RoSGNode", "ContentNode")
                shelfTitle = ""
                if shelf.title <> invalid then shelfTitle = shelf.title.trim()
                if shelfTitle = "" then shelfTitle = tr("Live Channels")
                row.title = shelfTitle
                for each stream in shelf.streams
                    twitchContentNode = createObject("roSGNode", "TwitchContentNode")
                    setTwitchContentFields(twitchContentNode, stream)
                    row.appendChild(twitchContentNode)
                end for
                if row.getChildCount() > 0
                    contentCollection.appendChild(row)
                    shelvesAdded += 1
                    if shelvesAdded >= 4 then exit for
                end if
            end for
        end if
    catch e
        ? "[Following] handleRecommendedSections: recommended shelves parse error: "; e
    end try
    try
        ? "LiveStreamSection Complete: "; TimeStamp()
        if rsp.offlineFollows <> invalid and rsp.offlineFollows.count() > 0
            row = createObject("RoSGNode", "ContentNode")
            row.title = tr("followedOfflineUsers")
            ? "OfflineSection Start: "; TimeStamp()
            streams = []
            streams.append(rsp.offlineFollows)
            sortMethod = get_user_setting("FollowPageSorting", "streamerLogin")
            ? "Sort Method: "; sortMethod
            if sortMethod = "streamerLogin"
                streams.sortBy("streamerLogin", "i")
            else if sortMethod = "followerCount"
                streams.sortBy("followerCount", "r")
            else if sortMethod = "ASC_followerCount"
                streams.sortBy("followerCount")
            end if
            for each offlineUser in streams
                twitchContentNode = createObject("roSGNode", "TwitchContentNode")
                setTwitchContentFields(twitchContentNode, offlineUser)
                row.appendChild(twitchContentNode)
            end for
            if row.getChildCount() > 0
                contentCollection.appendChild(row)
            end if
            ? "OfflineStreamSection Complete: "; TimeStamp()
        end if
    catch e
        ? "[Following] handleRecommendedSections: offline follows parse error: "; e
    end try
    if contentCollection.getChildCount() > 0
        updateRowList(contentCollection)
    end if
end sub

sub updateRowList(contentCollection)
    ? "updateRowList: "; TimeStamp()
    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        hasRowLabel = row.title <> ""
        firstChild = row.getChild(0)
        if firstChild <> invalid
            config = getRowConfig(firstChild.contentType, hasRowLabel, false)
            if config <> invalid
                showRowLabel.push(hasRowLabel)
                rowItemSize.push(config.itemSize)
                rowHeights.push(config.rowHeight)
            end if
        end if
    end for
    focusPos = findFocusedChannel(contentCollection)
    m.rowlist.rowHeights = rowHeights
    m.rowlist.showRowLabel = showRowLabel
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.content = contentCollection
    m.rowlist.numRows = m.rowlist.content.getChildCount()
    if focusPos <> invalid then m.rowlist.jumpToRowItem = focusPos
    updateHeroFromFocused(true)
    ? "updateRowList Done: "; TimeStamp()
end sub

' On a reload, where the focused channel lands in newContent (same login), else the old row/index clamped.
' Returns invalid on the first load.
function findFocusedChannel(newContent as object) as dynamic
    old = m.rowlist.content
    focused = m.rowlist.rowItemFocused
    if old = invalid or focused = invalid or focused.count() < 2 or newContent.getChildCount() = 0 then return invalid
    oldRow = old.getChild(focused[0])
    oldItem = invalid
    if oldRow <> invalid then oldItem = oldRow.getChild(focused[1])
    if oldItem <> invalid
        rows = []
        for each row in newContent.getChildren(-1, 0)
            logins = []
            for each item in row.getChildren(-1, 0)
                logins.push(item.streamerLogin)
            end for
            rows.push(logins)
        end for
        found = findLoginPosition(rows, oldItem.streamerLogin)
        if found <> invalid then return found
    end if
    rowSizes = []
    for each row in newContent.getChildren(-1, 0)
        rowSizes.push(row.getChildCount())
    end for
    return clampRowItemFocus(focused, rowSizes)
end function

sub handleItemSelected()
    item = invalid
    if m.rowlist.focusedChild <> invalid
        item = m.rowlist
    else if m.offlinelist <> invalid and m.offlinelist.focusedChild <> invalid
        item = m.offlinelist
    end if
    if item <> invalid
        if item.content = invalid then return
        if item.rowItemSelected = invalid then return
        if item.rowItemSelected.count() < 2 then return
        selectedRow = item.content.getchild(item.rowItemSelected[0])
        if selectedRow = invalid then return
        selectedItem = selectedRow.getChild(item.rowItemSelected[1])
        if selectedItem = invalid then return
    else
        return
    end if

    ' Delegate to specific handler based on content type
    if selectedItem.contentType = "LIVE"
        ' Use the existing live handler for direct playback
        handleLiveItemSelected()
    else
        ' Regular navigation for other content types
        m.top.contentSelected = selectedItem
    end if
end sub

sub handleLiveItemSelected()
    if m.rowlist.content = invalid then return
    if m.rowlist.rowItemSelected = invalid then return
    if m.rowlist.rowItemSelected.count() < 2 then return
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    if selectedRow = invalid then return
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    if selectedItem = invalid then return
    m.top.playContent = true
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    ' A dialog is open: it owns focus until it closes (heroScene restores focus then).
    scene = m.top.getScene()
    if scene <> invalid and scene.dialog <> invalid then return
    ' focusedChild also fires when focus leaves (menu, sidebar) or the list content changes: only act on gaining it.
    if not m.top.isInFocusChain()
        updateRowListFocusFeedback()
        return
    end if
    if m.rowlist.focusedChild = invalid
        m.rowlist.setFocus(true)
    else if m.rowlist.focusedChild.id = "homeRowList"
        m.rowlist.focusedChild.setFocus(true)
    end if
    updateRowListFocusFeedback()
    refreshFollowing(30)
end sub

' Hide the RowList focus rectangle when focus leaves the scene (e.g. user
' presses Up to MenuBar). Restore it when focus returns. RowList still
' remembers the previously focused tile internally.
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
        ? "Home Scene Key Event: "; key
        if key = "up" or key = "back"
            m.top.backPressed = true
            return true
        end if
    end if
    return false
end function

sub onRowItemFocused()
    updateHeroFromFocused(false)
end sub

' Syncs the Apple-TV hero spotlight text and backdrop to the currently focused tile.
sub updateHeroFromFocused(immediate = false as boolean)
    if m.rowlist = invalid or m.rowlist.content = invalid then return
    focused = m.rowlist.rowItemFocused
    rowIdx = 0
    colIdx = 0
    if focused <> invalid and focused.count() >= 2
        if focused[0] >= 0 then rowIdx = focused[0]
        if focused[1] >= 0 then colIdx = focused[1]
    end if
    row = m.rowlist.content.getChild(rowIdx)
    if row = invalid then return
    item = row.getChild(colIdx)
    if item = invalid then return

    backdropUrl = ""
    if item.contentType = "LIVE"
        pillW = 88
        if m.heroLiveLabel <> invalid and m.heroLiveBg <> invalid
            badgeText = tr("LIVE")
            if badgeText = invalid or badgeText = "" then badgeText = "LIVE"
            m.heroLiveLabel.width = 0
            m.heroLiveLabel.text = badgeText
            try
                measured = m.heroLiveLabel.boundingRect().width
                if measured <> invalid and measured > 0 then pillW = Int(measured) + 20
            catch e
            end try
            if pillW < 68 then pillW = 68
            m.heroLiveBg.width = pillW
            m.heroLiveLabel.width = pillW
        end if
        if m.heroLivePill <> invalid then m.heroLivePill.visible = true
        if m.heroStreamer <> invalid
            m.heroStreamer.translation = [pillW + 14, 0]
            m.heroStreamer.text = item.streamerDisplayName
        end if
        if m.heroMetaLine <> invalid
            meta = ""
            if item.gameDisplayName <> invalid and item.gameDisplayName.trim() <> ""
                meta = item.gameDisplayName.trim()
            end if
            if item.viewersDisplay <> invalid and item.viewersDisplay.trim() <> ""
                if meta <> "" then meta += "  ·  "
                meta += item.viewersDisplay.trim()
            end if
            m.heroMetaLine.text = meta
        end if
        if m.heroTitle <> invalid then m.heroTitle.text = item.contentTitle
        if item.previewImageURL <> invalid then backdropUrl = item.previewImageURL
    else
        if m.heroLivePill <> invalid then m.heroLivePill.visible = false
        if m.heroStreamer <> invalid
            m.heroStreamer.translation = [0, 0]
            streamerName = item.streamerDisplayName
            if streamerName = invalid or streamerName = "" then streamerName = item.contentTitle
            if streamerName = invalid then streamerName = ""
            m.heroStreamer.text = streamerName
        end if
        if m.heroMetaLine <> invalid
            meta = tr("Offline Channels")
            if item.followerDisplay <> invalid and item.followerDisplay.trim() <> ""
                meta += "  ·  " + item.followerDisplay.trim()
            end if
            m.heroMetaLine.text = meta
        end if
        if m.heroTitle <> invalid then m.heroTitle.text = ""
        if item.streamerProfileImageUrl <> invalid then backdropUrl = item.streamerProfileImageUrl
    end if

    m.pendingBackdropUrl = backdropUrl
    if immediate
        applyHeroBackdrop()
    else if m.heroDebounceTimer <> invalid
        m.heroDebounceTimer.control = "stop"
        m.heroDebounceTimer.control = "start"
    else
        applyHeroBackdrop()
    end if
end sub

sub applyHeroBackdrop()
    if m.heroBackdrop = invalid then return
    if m.pendingBackdropUrl <> invalid
        m.heroBackdrop.uri = m.pendingBackdropUrl
    end if
end sub

sub onDestroy()
    m.top.unobserveField("focusedChild")
    if m.rowlist <> invalid
        m.rowlist.unobserveField("itemSelected")
        m.rowlist.unobserveField("rowItemFocused")
    end if
    m.heroDebounceTimer = destroyTask(m.heroDebounceTimer, "fire")
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
    if m.refreshTimer <> invalid
        m.refreshTimer.control = "stop"
        m.refreshTimer.unobserveField("fire")
    end if
end sub
