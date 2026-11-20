sub init()
    m.itemlabel = m.top.findNode("itemLabel")
    m.plainTitle = m.top.findNode("plainTitle")
    m.itemStreamer = m.top.findNode("itemStreamer")
    m.itemmask = m.top.findNode("itemMask")
    m.timestampRect = m.top.findNode("timestampRect")
    m.timestampLabel = m.top.findNode("timestampLabel")
    m.itemposter = m.top.findNode("itemPoster")
    m.circlePoster = m.top.findNode("circlePoster")
    m.streamAvatar = m.top.findNode("streamAvatar")
    m.liveicon = m.top.findNode("liveIcon")
    m.liveBg = m.top.findNode("liveBg")
    m.liveBadgeText = m.top.findNode("liveBadgeText")
    m.itemSubtitle = m.top.findNode("itemSubtitle")
    m.itemViewers = m.top.findNode("itemViewers")
    m.viewsRect = m.top.findNode("viewsRect")
    m.runtimeRect = m.top.findNode("runtimeRect")
    m.runtimeLabel = m.top.findNode("runtimeLabel")
end sub

' Reset all toggleable nodes to their default visible state before each
' content type configures its own layout. RowList recycles item components,
' so state from a previous content type would otherwise bleed through.
sub resetVisibility()
    if m.itemposter = invalid then return
    m.itemposter.visible = true
    if m.circlePoster <> invalid then m.circlePoster.visible = false
    if m.streamAvatar <> invalid then m.streamAvatar.visible = false
    if m.plainTitle <> invalid then m.plainTitle.visible = false
    if m.itemStreamer <> invalid then m.itemStreamer.visible = false
    if m.liveicon <> invalid then m.liveicon.visible = true
    if m.itemViewers <> invalid then m.itemViewers.visible = true
    if m.viewsRect <> invalid then m.viewsRect.visible = true
    if m.runtimeRect <> invalid then m.runtimeRect.visible = false
    if m.runtimeLabel <> invalid then m.runtimeLabel.visible = false
    if m.timestampLabel <> invalid then m.timestampLabel.visible = true
    if m.timestampRect <> invalid then m.timestampRect.visible = true
    if m.itemlabel <> invalid
        m.itemlabel.visible = true
        m.itemlabel.horizAlign = "left"
        m.itemlabel.repeatCount = 0
    end if
    if m.itemSubtitle <> invalid then m.itemSubtitle.horizAlign = "left"
end sub

sub showcontent()
    resetVisibility()
    GlobalSettings()
    if m.top.itemContent.contentType = "GAME"
        GameSettings()
    else if m.top.itemContent.contentType = "LIVE"
        LiveSettings()
    else if m.top.itemContent.contentType = "VOD"
        VodSettings()
    else if m.top.itemContent.contentType = "CLIP"
        ClipSettings()
    else if m.top.itemContent.contentType = "USER"
        UserSettings()
    end if
end sub

sub GlobalSettings()
    if m.global = invalid or m.global.constants = invalid then return
    if m.itemSubtitle = invalid then return
    m.itemSubtitle.color = m.global.constants.colors.semantic.textSecondary
end sub

sub GameSettings()
    if m.itemposter = invalid then return
    if m.runtimeRect = invalid or m.runtimeLabel = invalid then return
    if m.itemSubtitle = invalid then return
    if m.liveicon = invalid or m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.runtimeRect.visible = false
    m.runtimeLabel.visible = false
    m.itemposter.width = 188
    m.itemposter.height = 250
    m.itemposter.loadwidth = 188
    m.itemposter.loadheight = 250
    if m.itemlabel <> invalid then m.itemlabel.visible = false
    if m.plainTitle <> invalid
        m.plainTitle.width = 188
        m.plainTitle.horizAlign = "left"
        m.plainTitle.translation = [0, 260]
        m.plainTitle.text = m.top.itemContent.contentTitle
        m.plainTitle.visible = true
    end if
    m.itemSubtitle.width = 188
    m.itemSubtitle.translation = [0, 288]
    m.liveicon.visible = false
    m.itemViewers.visible = false
    m.viewsRect.visible = false
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
    m.itemSubtitle.text = m.top.itemContent.viewersDisplay
    m.itemposter.uri = m.top.itemContent.gameBoxArtUrl
end sub

' Size the poster and place 3-line metadata + avatar from getStreamTile().
' Also undoes GAME/USER sizing when RowList recycles this item for a stream tile.
sub applyStreamLayout()
    tile = getStreamTile()
    m.itemposter.width = tile.width
    m.itemposter.height = tile.height
    m.itemposter.loadwidth = tile.width
    m.itemposter.loadheight = tile.height

    avatarUrl = m.top.itemContent.streamerProfileImageUrl
    textX = 0
    textW = tile.width
    if m.streamAvatar <> invalid and avatarUrl <> invalid and avatarUrl <> ""
        m.streamAvatar.translation = [0, tile.height + 13]
        m.streamAvatar.uri = avatarUrl
        m.streamAvatar.visible = true
        textX = 60
        textW = tile.width - 60
    else if m.streamAvatar <> invalid
        m.streamAvatar.visible = false
    end if

    m.itemlabel.maxwidth = textW
    m.itemlabel.translation = [textX, tile.height + 11]

    streamer = ""
    if m.top.itemContent.streamerDisplayName <> invalid then streamer = m.top.itemContent.streamerDisplayName.trim()
    if m.itemStreamer <> invalid and streamer <> ""
        m.itemStreamer.text = streamer
        m.itemStreamer.width = textW
        m.itemStreamer.translation = [textX, tile.height + 39]
        m.itemStreamer.visible = true
        m.itemSubtitle.translation = [textX, tile.height + 63]
    else
        if m.itemStreamer <> invalid then m.itemStreamer.visible = false
        m.itemSubtitle.translation = [textX, tile.height + 39]
    end if
    m.itemSubtitle.width = textW

    m.viewsRect.translation = [10, tile.height - 38]
    m.itemViewers.translation = [20, tile.height - 38]
end sub

' Helper to size viewer/date/live capsule cleanly around rendered text.
sub sizePill(rectNode as object, labelNode as object, textVal as dynamic)
    if rectNode = invalid or labelNode = invalid then return
    if textVal = invalid or textVal.toStr().trim() = ""
        rectNode.visible = false
        labelNode.visible = false
        return
    end if
    labelNode.width = 0
    labelNode.text = textVal.toStr()
    labelNode.visible = true
    rectNode.visible = true
    rectNode.height = 28
    try
        w = Int(labelNode.boundingRect().width) + 20
        if w < 56 then w = 56
        labelNode.width = w - 20
        rectNode.width = w
    catch e
    end try
end sub

sub LiveSettings()
    if m.itemposter = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    applyStreamLayout()
    if m.liveBadgeText <> invalid and m.liveBg <> invalid
        badgeText = tr("LIVE")
        if badgeText = invalid or badgeText = "" then badgeText = "LIVE"
        m.liveBadgeText.width = 0
        m.liveBadgeText.text = badgeText
        pillW = 88
        try
            measured = m.liveBadgeText.boundingRect().width
            if measured <> invalid and measured > 0 then pillW = Int(measured) + 20
        catch e
        end try
        if pillW < 68 then pillW = 68
        m.liveBg.width = pillW
        m.liveBadgeText.width = pillW
    end if
    sizePill(m.viewsRect, m.itemViewers, m.top.itemContent.viewersDisplay)
    m.itemposter.uri = m.top.itemContent.previewImageURL
    gameName = ""
    if m.top.itemContent.gameDisplayName <> invalid then gameName = m.top.itemContent.gameDisplayName.trim()
    m.itemSubtitle.text = gameName
    m.itemlabel.text = m.top.itemContent.contentTitle
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
end sub

sub VodSettings()
    if m.itemposter = invalid then return
    if m.liveicon = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    applyStreamLayout()
    m.liveicon.visible = false
    sizePill(m.viewsRect, m.itemViewers, m.top.itemContent.viewersDisplay)
    sizePill(m.timestampRect, m.timestampLabel, m.top.itemContent.relativePublishDate)
    m.itemposter.uri = m.top.itemContent.previewImageURL
    gameName = ""
    if m.top.itemContent.gameDisplayName <> invalid then gameName = m.top.itemContent.gameDisplayName.trim()
    m.itemSubtitle.text = gameName
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub ClipSettings()
    if m.itemposter = invalid then return
    if m.liveicon = invalid then return
    if m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    applyStreamLayout()
    m.liveicon.visible = false
    sizePill(m.viewsRect, m.itemViewers, m.top.itemContent.viewersDisplay)
    sizePill(m.timestampRect, m.timestampLabel, m.top.itemContent.relativePublishDate)
    m.itemposter.uri = m.top.itemContent.previewImageURL
    gameName = ""
    if m.top.itemContent.gameDisplayName <> invalid then gameName = m.top.itemContent.gameDisplayName.trim()
    m.itemSubtitle.text = gameName
    m.itemlabel.text = m.top.itemContent.contentTitle
end sub

sub UserSettings()
    if m.itemposter = invalid then return
    if m.runtimeRect = invalid or m.runtimeLabel = invalid then return
    if m.circlePoster = invalid then return
    if m.liveicon = invalid or m.itemViewers = invalid or m.viewsRect = invalid then return
    if m.itemSubtitle = invalid then return
    if m.timestampLabel = invalid or m.timestampRect = invalid then return
    m.runtimeRect.visible = false
    m.runtimeLabel.visible = false
    m.itemposter.visible = false
    m.circlePoster.uri = m.top.itemContent.streamerProfileImageUrl
    m.circlePoster.visible = true
    if m.itemlabel <> invalid then m.itemlabel.visible = false
    if m.plainTitle <> invalid
        m.plainTitle.width = 150
        m.plainTitle.horizAlign = "center"
        m.plainTitle.translation = [0, 160]
        m.plainTitle.text = m.top.itemContent.contentTitle
        m.plainTitle.visible = true
    end if
    m.itemSubtitle.width = 150
    m.itemSubtitle.horizAlign = "center"
    m.itemSubtitle.translation = [0, 188]
    m.liveicon.visible = false
    m.itemViewers.visible = false
    m.viewsRect.visible = false
    m.itemSubtitle.text = m.top.itemContent.followerDisplay
    m.timestampLabel.visible = false
    m.timestampRect.visible = false
end sub

sub onGetFocus()
    if m.itemLabel <> invalid then m.itemLabel.repeatCount = 0
end sub

sub showrowfocus()
    if m.itemmask = invalid or m.top.rowFocusPercent = invalid then return
    m.itemmask.opacity = 0.75 - (m.top.rowFocusPercent * 0.75)
end sub
