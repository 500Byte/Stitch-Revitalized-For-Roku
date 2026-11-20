sub init()
    if m.global <> invalid and m.global.constants <> invalid
        m.top.backgroundColor = m.global.constants.colors.semantic.bgCanvas
    end if
    m.top.observeField("focusedChild", "onGetfocus")
    m.rowlist = m.top.findNode("homeRowList")
    styleRowListHeader(m.rowlist)
    m.rowlist.ObserveField("itemSelected", "handleItemSelected")
    m.header = m.top.findNode("Header")
    m.subtitle = m.top.findNode("subtitle")
    m.gameBoxArt = m.top.findNode("gameBoxArt")
end sub

sub updatePage()
    req = m.top.contentRequested
    if req = invalid then return

    title = req.gameDisplayName
    if title = invalid or title = "" then title = req.gameName
    if title = invalid then title = ""
    m.top.pageTitle = title

    boxArtUrl = req.gameBoxArtUrl
    hasBoxArt = (boxArtUrl <> invalid and boxArtUrl <> "")
    if m.gameBoxArt <> invalid
        m.gameBoxArt.visible = hasBoxArt
        if hasBoxArt then m.gameBoxArt.uri = boxArtUrl
    end if
    textX = 64
    if hasBoxArt then textX = 172
    if m.header <> invalid then m.header.translation = [textX, 46]
    if m.subtitle <> invalid
        m.subtitle.translation = [textX, 100]
        if req.viewersDisplay <> invalid and req.viewersDisplay <> ""
            m.subtitle.text = req.viewersDisplay
        else
            m.subtitle.text = tr("Live Channels")
        end if
    end if

    m.GetContentTask = createApiTask("getGameDirectoryQuery", "handleRecommendedSections", {
        params: { gameAlias: req.gameName }
    })
end sub

function buildContentNodeFromShelves(streams)
    itemsPerRow = getStreamTile().perRow
    contentCollection = createObject("RoSGNode", "ContentNode")
    row = createObject("RoSGNode", "ContentNode")
    gameTitle = ""
    if m.top.contentRequested <> invalid
        gameTitle = m.top.contentRequested.gameDisplayName
        if gameTitle = invalid or gameTitle = "" then gameTitle = m.top.contentRequested.gameName
        if gameTitle = invalid then gameTitle = ""
    end if
    for i = 0 to (streams.count() - 1) step 1
        stream = streams[i]
        if stream = invalid or stream.node = invalid or stream.node.broadcaster = invalid then continue for
        row.title = ""
        rowItem = createObject("RoSGNode", "TwitchContentNode")
        rowItem.contentId = stream.node.Id
        rowItem.contentType = "LIVE"
        rowItem.previewImageURL = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", stream.node.broadcaster.login, "1280", "720")
        rowItem.contentTitle = stream.node.broadcaster.broadcastSettings.title
        rowItem.viewersCount = stream.node.viewersCount
        rowItem.streamerDisplayName = stream.node.broadcaster.displayName
        rowItem.streamerLogin = stream.node.broadcaster.login
        rowItem.streamerId = stream.node.broadcaster.id
        rowItem.streamerProfileImageUrl = stream.node.broadcaster.profileImageURL
        rowItem.gameDisplayName = gameTitle
        ' rowItem.Title = stream.node.broadcaster.broadcastsettings.title
        ' rowItem.secondaryTitle = stream.node.broadcaster.displayName
        ' rowItem.HDPosterUrl = Substitute("https://static-cdn.jtvnw.net/previews-ttv/live_user_{0}-{1}x{2}.jpg", stream.node.broadcaster.login, "1280", "720")
        ' rowItem.ShortDescriptionLine1 = stream.node.viewersCount
        ' rowItem.ShortDescriptionLine2 = stream.node.game.displayName
        row.appendChild(rowItem)
        if row.getChildCount() = itemsPerRow
            contentCollection.appendChild(row)
            row = createObject("RoSGNode", "ContentNode")
        end if
    end for
    ' Keep the last, partly filled row: small categories have fewer streams than one row.
    if row.getChildCount() > 0
        contentCollection.appendChild(row)
    end if
    return contentCollection
end function


sub updateRowList(contentCollection)
    rowItemSize = []
    showRowLabel = []
    rowHeights = []
    for each row in contentCollection.getChildren(contentCollection.getChildCount(), 0)
        hasRowLabel = row.title <> ""
        showRowLabel.push(hasRowLabel)
        config = getRowConfig(row.getchild(0).contentType, hasRowLabel)
        if config <> invalid
            rowItemSize.push(config.itemSize)
            rowHeights.push(config.rowHeight)
        end if
    end for
    m.rowList.rowHeights = rowHeights
    m.rowlist.showRowLabel = showRowLabel
    m.rowlist.rowItemSize = rowItemSize
    m.rowlist.content = contentCollection
    m.rowlist.numRows = contentCollection.getChildCount()
end sub


sub handleRecommendedSections()
    rsp = m.GetContentTask.response
    if rsp = invalid then return
    contentCollection = buildContentNodeFromShelves(rsp.edges)
    updateRowList(contentCollection)
end sub

sub handleItemSelected()
    if m.rowlist.content = invalid then return
    if m.rowlist.rowItemSelected = invalid then return
    if m.rowlist.rowItemSelected.count() < 2 then return
    selectedRow = m.rowlist.content.getchild(m.rowlist.rowItemSelected[0])
    if selectedRow = invalid then return
    selectedItem = selectedRow.getChild(m.rowlist.rowItemSelected[1])
    if selectedItem = invalid then return
    m.top.contentSelected = selectedItem
end sub

sub onGetFocus()
    if m.rowlist.focusedChild = invalid
        m.rowlist.setFocus(true)
    else if m.rowlist.focusedChild.id = "homeRowList"
        m.rowlist.focusedChild.setFocus(true)
    end if
    updateRowListFocusFeedback()
end sub

' Hide the RowList focus rectangle when focus leaves the scene; restore on return.
sub updateRowListFocusFeedback()
    if m.rowlist = invalid then return
    m.rowlist.drawFocusFeedback = m.top.focusedChild <> invalid and m.top.focusedChild.id = "homeRowList"
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press
        ? "Home Scene Key Event: "; key
        if key = "back"
            m.top.backPressed = true
            return true
        end if
    end if
    return false
end function

sub onDestroy()
    m.top.unobserveField("focusedChild")
    if m.rowlist <> invalid
        m.rowlist.unobserveField("itemSelected")
    end if
    m.GetContentTask = destroyTask(m.GetContentTask, "response")
end sub
