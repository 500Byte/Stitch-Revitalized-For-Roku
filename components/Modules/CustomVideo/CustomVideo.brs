sub init()
    ' Initialize UI elements
    m.top.enableUI = false
    m.top.enableTrickPlay = false

    ' Control overlay elements
    m.controlOverlay = m.top.findNode("controlOverlay")
    m.controlOverlay.visible = false

    ' Progress bar elements
    m.progressBarBase = m.top.findNode("progressBarBase")
    m.progressBarProgress = m.top.findNode("progressBarProgress")
    m.progressBarBuffer = m.top.findNode("progressBarBuffer")
    m.mutedSegmentsGroup = m.top.findNode("mutedSegmentsGroup")
    m.progressDot = m.top.findNode("progressDot")
    m.timeProgress = m.top.findNode("timeProgress")
    m.timeDuration = m.top.findNode("timeDuration")

    ' Toast elements
    m.chatModeToastGroup = m.top.findNode("chatModeToastGroup")
    m.chatModeToast = m.top.findNode("chatModeToast")
    m.muteSkipToastGroup = m.top.findNode("muteSkipToastGroup")
    m.muteSkipToast = m.top.findNode("muteSkipToast")
    m.skipMuteButton = m.top.findNode("skipMuteButton")
    m.currentMutedTarget = -1
    m.mutedSegments = invalid

    ' Control buttons
    m.playPauseGroup = m.top.findNode("playPauseGroup")
    m.rewindGroup = m.top.findNode("rewindGroup")
    m.fastForwardGroup = m.top.findNode("fastForwardGroup")
    m.timeTravelGroup = m.top.findNode("timeTravelGroup")
    m.chatGroup = m.top.findNode("chatGroup")
    m.backGroup = m.top.findNode("backGroup")
    m.controlButton = m.top.findNode("controlButton")

    ' Focus backgrounds
    m.playPauseFocus = m.top.findNode("playPauseFocus")
    m.rewindFocus = m.top.findNode("rewindFocus")
    m.fastForwardFocus = m.top.findNode("fastForwardFocus")
    m.timeTravelFocus = m.top.findNode("timeTravelFocus")
    m.chatFocus = m.top.findNode("chatFocus")
    m.backFocus = m.top.findNode("backFocus")

    ' Time travel dialog
    m.timeTravelDialog = m.top.findNode("timeTravelDialog")
    m.hour0 = m.top.findNode("hour0")
    m.hour1 = m.top.findNode("hour1")
    m.minute0 = m.top.findNode("minute0")
    m.minute1 = m.top.findNode("minute1")
    m.second0 = m.top.findNode("second0")
    m.second1 = m.top.findNode("second1")
    m.hour0Text = m.top.findNode("hour0Text")
    m.hour1Text = m.top.findNode("hour1Text")
    m.minute0Text = m.top.findNode("minute0Text")
    m.minute1Text = m.top.findNode("minute1Text")
    m.second0Text = m.top.findNode("second0Text")
    m.second1Text = m.top.findNode("second1Text")
    m.cancelButton = m.top.findNode("cancelButton")
    m.acceptButton = m.top.findNode("acceptButton")
    m.cancelButtonFocus = m.top.findNode("cancelButtonFocus")
    m.acceptButtonFocus = m.top.findNode("acceptButtonFocus")

    ' Other elements
    m.thumbnailPreview = m.top.findNode("thumbnailPreview")
    m.thumbnails = m.top.findNode("thumbnails")
    m.thumbnailImage = m.top.findNode("thumbnailImage")
    m.thumbnailTime = m.top.findNode("thumbnailTime")
    m.liveIndicator = m.top.findNode("liveIndicator")
    m.uptimeLabel = m.top.findNode("uptimeLabel")
    m.loadingOverlay = m.top.findNode("loadingOverlay")
    m.loadingText = m.top.findNode("loadingText")
    m.loadingSpinner = m.top.findNode("loadingSpinner")

    ' Video info
    m.videoTitle = m.top.findNode("videoTitle")
    m.channelUsername = m.top.findNode("channelUsername")
    m.avatar = m.top.findNode("avatar")

    ' State variables
    m.currentFocusedButton = 3 ' 0=back, 1=timetravel, 2=rewind, 3=play/pause, 4=fastforward, 5=chat
    m.isOverlayVisible = false
    m.isTimeTravelDialogOpen = false
    m.timeTravelFocusedField = 0 ' 0-5 for time fields, 6-7 for buttons
    m.currentPositionSeconds = 0
    m.currentPositionUpdated = false
    m.isSeekMode = false
    m.buttonHeld = invalid
    m.scrollInterval = 10
    m.isLiveStream = false

    ' Time field references
    m.timeFields = [m.hour0, m.hour1, m.minute0, m.minute1, m.second0, m.second1]
    m.timeTexts = [m.hour0Text, m.hour1Text, m.minute0Text, m.minute1Text, m.second0Text, m.second1Text]
    m.timeButtons = [m.cancelButton, m.acceptButton]
    m.timeButtonFocus = [m.cancelButtonFocus, m.acceptButtonFocus]

    ' Timers
    m.fadeAwayTimer = createObject("roSGNode", "Timer")
    m.fadeAwayTimer.observeField("fire", "onFadeAway")
    m.fadeAwayTimer.repeat = false
    m.fadeAwayTimer.duration = 5
    m.fadeAwayTimer.control = "stop"

    m.buttonHoldTimer = createObject("roSGNode", "Timer")
    m.buttonHoldTimer.observeField("fire", "onButtonHold")
    m.buttonHoldTimer.repeat = true
    m.buttonHoldTimer.duration = 0.1
    m.buttonHoldTimer.control = "stop"

    ' Observers
    m.top.observeField("position", "onPositionChange")
    m.top.observeField("state", "onVideoStateChange")
    m.top.observeField("chatIsVisible", "onChatVisibilityChange")
    m.top.observeField("streamLayoutMode", "onStreamLayoutModeChange")
    m.top.observeField("duration", "onDurationChange")
    m.top.observeField("bufferingStatus", "onBufferingStatusChange")
    m.top.observeField("video_type", "onVideoTypeChange")

    ' Initialize UI
    updateProgressBar()

    ' Show loading overlay initially
    showLoadingOverlay()

    ? getLogTimestamp(); " [CustomVideo] Initialized"
end sub

sub createMessageOverlay()
    if m.messageOverlay = invalid
        m.messageOverlay = CreateObject("roSGNode", "Group")
        m.messageOverlay.visible = false

        messageBg = CreateObject("roSGNode", "Rectangle")
        messageBg.width = 600
        messageBg.height = 150
        messageBg.color = "0x000000CC"
        messageBg.translation = [660, 465]

        messageTitle = CreateObject("roSGNode", "Label")
        messageTitle.id = "messageTitle"
        messageTitle.font = "font:MediumBoldSystemFont"
        messageTitle.text = ""
        messageTitle.horizAlign = "center"
        messageTitle.vertAlign = "center"
        messageTitle.width = 600
        messageTitle.height = 50
        messageTitle.translation = [660, 480]

        messageText = CreateObject("roSGNode", "Label")
        messageText.id = "messageText"
        messageText.font = "font:SmallSystemFont"
        messageText.text = ""
        messageText.horizAlign = "center"
        messageText.vertAlign = "center"
        messageText.width = 600
        messageText.height = 50
        messageText.translation = [660, 530]

        m.messageOverlay.appendChild(messageBg)
        m.messageOverlay.appendChild(messageTitle)
        m.messageOverlay.appendChild(messageText)
        m.top.appendChild(m.messageOverlay)
    end if
end sub

sub onVideoTypeChange()
    m.isLiveStream = (m.top.video_type = "LIVE")
    updateUIForVideoType()

    ' Update loading text based on video type
    if m.loadingText <> invalid
        if m.isLiveStream
            m.loadingText.text = "Loading stream..."
        else
            m.loadingText.text = "Loading video..."
        end if
    end if
end sub

sub updateUIForVideoType()
    if m.isLiveStream
        ' Hide seek-related controls for live streams
        m.rewindGroup.visible = false
        m.fastForwardGroup.visible = false
        m.timeTravelGroup.visible = false
        m.progressDot.visible = false

        ' Adjust button focus indices for live streams
        ' 0=back, 1=play/pause, 2=chat
        if m.currentFocusedButton = 1 or m.currentFocusedButton = 2 or m.currentFocusedButton = 4
            m.currentFocusedButton = 1 ' Focus play/pause for live
        end if
        focusButton(m.currentFocusedButton) ' <-- keep focus visuals in sync
    else
        ' Show all controls for VOD/clips
        m.rewindGroup.visible = true
        m.fastForwardGroup.visible = true
        m.timeTravelGroup.visible = true
        m.progressDot.visible = true
    end if
end sub

sub onPositionChange()
    m.currentPositionSeconds = m.top.position
    if not m.isSeekMode
        updateProgressBar()
    end if
    if m.isLiveStream and m.isOverlayVisible then updateUptime()

    ' Auto-skip muted audio segments if enabled, or show Skip Mute button (like Netflix "Skip Intro")
    if m.mutedSegments <> invalid and not m.isSeekMode
        currPos = m.currentPositionSeconds
        autoSkip = (get_user_setting("AutoSkipMuted", "false") = "true")
        inMutedSegment = false

        for each seg in m.mutedSegments
            if seg.offset <> invalid and seg.duration <> invalid
                if currPos >= seg.offset and currPos < (seg.offset + seg.duration - 1)
                    inMutedSegment = true
                    target = seg.offset + seg.duration
                    if autoSkip
                        m.top.seek = target
                        showMuteToast("Saltando audio silenciado...")
                        hideSkipMuteButton()
                    else
                        m.currentMutedTarget = target
                        showSkipMuteButton()
                    end if
                    exit for
                end if
            end if
        end for

        if not inMutedSegment
            hideSkipMuteButton()
        end if
    end if

    ' Auto-save bookmark every 20 seconds (not for live streams)
    if not m.isLiveStream
        ' Position reads 0 at start and when the player resets on exit; saving it
        ' would wipe the real bookmark.
        checker = Int(m.top.position) mod 20
        if checker = 0 and Int(m.top.position) > 0 and (m._lastBookmarkSecond = invalid or m._lastBookmarkSecond <> Int(m.top.position))
            m._lastBookmarkSecond = Int(m.top.position)
            saveVideoBookmark()
        end if
    end if
end sub

sub onVideoStateChange()
    if m.top.state = "playing"
        m.controlButton.uri = "pkg:/images/pause.png"
        hideLoadingOverlay()
        hideMessage()
    else if m.top.state = "paused"
        m.controlButton.uri = "pkg:/images/play.png"
        hideLoadingOverlay()
    else if m.top.state = "buffering"
        showLoadingOverlay()
        if m.loadingText <> invalid
            if m.isLiveStream
                m.loadingText.text = "Buffering stream..."
            else
                m.loadingText.text = "Buffering video..."
            end if
        end if
    else if m.top.state = "error"
        hideLoadingOverlay()
        ? getLogTimestamp(); " [CustomVideo] Video error occurred"
        if m.top.errorStr <> invalid and (m.top.errorStr.InStr("970") > -1 or m.top.errorStr.InStr("buffer:loop:demux") > -1)
            showErrorMessage("Incompatible Video Format", "This video cannot be played on your device")
        else
            showErrorMessage("Stream Error", "Having trouble loading the stream. Retrying...")
        end if
    end if

    ' Show live indicator for live streams
    if m.isLiveStream
        m.liveIndicator.visible = true
    else
        m.liveIndicator.visible = false
    end if
end sub

sub onChatVisibilityChange()
    ' Adjust layout based on chat visibility
    if m.top.chatIsVisible
        targetWidth = 1480
        if m.top.width <> invalid and m.top.width > 0
            targetWidth = m.top.width - 120
        end if
        m.progressBarBase.width = targetWidth
        m.controlOverlay.translation = [0, 920]
    else
        m.progressBarBase.width = 1800
        m.controlOverlay.translation = [0, 920]
    end if

    ' Update all progress bar elements to match new width
    updateProgressBar()
    renderMutedSegments()

    ' Update skip mute button position if currently visible
    if m.skipMuteButton <> invalid and m.skipMuteButton.visible
        showSkipMuteButton()
    end if

    ' Update buffer bar if buffering status is available
    if m.top.bufferingStatus <> invalid
        bufferPercent = m.top.bufferingStatus.percentage
        if bufferPercent <> invalid and m.top.duration > 0
            bufferWidth = m.progressBarBase.width * (bufferPercent / 100)
            m.progressBarBuffer.width = bufferWidth
        end if
    end if
end sub

sub onDurationChange()
    updateProgressBar()
    updateUIForVideoType()
    if m.top.video_type = "VOD" and m.top.video_id <> invalid and m.top.video_id <> "" and m.mutedSegments = invalid
        m.mutedTask = createApiTask("getVodMutedSegmentsQuery", "onMutedSegmentsResponse", { id: m.top.video_id })
    else if m.mutedSegments <> invalid
        renderMutedSegments()
    end if
end sub

sub onMutedSegmentsResponse()
    if m.mutedTask <> invalid and m.mutedTask.response <> invalid
        res = m.mutedTask.response
        if res.muteInfo <> invalid and res.muteInfo.mutedSegmentConnection <> invalid
            nodes = res.muteInfo.mutedSegmentConnection.nodes
            if nodes <> invalid
                m.mutedSegments = nodes
                renderMutedSegments()
            end if
        end if
    end if
    m.mutedTask = destroyTask(m.mutedTask, "response")
end sub

sub renderMutedSegments()
    if m.mutedSegmentsGroup = invalid or m.mutedSegments = invalid or m.top.duration <= 0 then return
    m.mutedSegmentsGroup.removeChildrenIndex(m.mutedSegmentsGroup.getChildCount(), 0)

    baseWidth = m.progressBarBase.width
    totalDuration = m.top.duration

    for each seg in m.mutedSegments
        if seg.offset <> invalid and seg.duration <> invalid
            startX = (seg.offset / totalDuration) * baseWidth
            segW = (seg.duration / totalDuration) * baseWidth
            if segW < 3 then segW = 3 ' Minimum 3px visible segment

            rect = createObject("roSGNode", "Rectangle")
            rect.width = segW
            rect.height = 4
            rect.color = "0xE91E63FF" ' Twitch muted pink/red color
            rect.translation = [startX, 0]
            m.mutedSegmentsGroup.appendChild(rect)
        end if
    end for
end sub

sub onStreamLayoutModeChange()
    mode = m.top.streamLayoutMode
    text = ""
    if mode = 1
        text = "Chat: Lateral"
    else if mode = 2
        text = "Chat: Superpuesto"
    else if mode = 0
        text = "Chat: Oculto"
    end if

    if text <> ""
        showChatToast(text)
    end if
end sub

sub showChatToast(text as string)
    if m.chatModeToast <> invalid and m.chatModeToastGroup <> invalid
        m.chatModeToast.text = text
        m.chatModeToastGroup.visible = true
        if m.chatToastTimer = invalid
            m.chatToastTimer = CreateObject("roSGNode", "Timer")
            m.chatToastTimer.duration = 2
            m.chatToastTimer.repeat = false
            m.chatToastTimer.observeField("fire", "hideChatToast")
        end if
        m.chatToastTimer.control = "stop"
        m.chatToastTimer.control = "start"
    end if
end sub

sub hideChatToast()
    if m.chatModeToastGroup <> invalid then m.chatModeToastGroup.visible = false
end sub

sub showMuteToast(text as string)
    if m.muteSkipToast <> invalid and m.muteSkipToastGroup <> invalid
        m.muteSkipToast.text = text
        m.muteSkipToastGroup.visible = true
        if m.muteToastTimer = invalid
            m.muteToastTimer = CreateObject("roSGNode", "Timer")
            m.muteToastTimer.duration = 3
            m.muteToastTimer.repeat = false
            m.muteToastTimer.observeField("fire", "hideMuteToast")
        end if
        m.muteToastTimer.control = "stop"
        m.muteToastTimer.control = "start"
    end if
end sub

sub hideMuteToast()
    if m.muteSkipToastGroup <> invalid then m.muteSkipToastGroup.visible = false
end sub

sub showSkipMuteButton()
    if m.skipMuteButton = invalid then return
    btnWidth = 360
    margin = 50
    if m.top.width <> invalid and m.top.width > 0 and m.top.chatIsVisible
        btnX = m.top.width - btnWidth - margin
    else
        btnX = 1920 - btnWidth - margin
    end if
    m.skipMuteButton.translation = [btnX, 840]
    m.skipMuteButton.visible = true
end sub

sub hideSkipMuteButton()
    if m.skipMuteButton <> invalid
        m.skipMuteButton.visible = false
    end if
end sub

sub updateUptime()
    if m.uptimeLabel = invalid then return
    if m.top?.content?.createdAt <> invalid and m.top.content.createdAt <> ""
        startDt = createObject("roDateTime")
        startDt.FromISO8601String(m.top.content.createdAt.toStr())
        nowSec = createObject("roDateTime").AsSeconds()
        uptimeSec = nowSec - startDt.AsSeconds()
        if uptimeSec > 0
            hours = Int(uptimeSec / 3600)
            minutes = Int((uptimeSec mod 3600) / 60)
            seconds = uptimeSec mod 60

            hStr = hours.toStr()
            if hours < 10 then hStr = "0" + hStr
            mStr = minutes.toStr()
            if minutes < 10 then mStr = "0" + mStr
            sStr = seconds.toStr()
            if seconds < 10 then sStr = "0" + sStr

            m.uptimeLabel.text = "Uptime: " + hStr + ":" + mStr + ":" + sStr
            m.uptimeLabel.visible = true
            return
        end if
    end if
    m.uptimeLabel.visible = false
end sub

sub onBufferingStatusChange()
    if m.top.bufferingStatus <> invalid
        bufferPercent = m.top.bufferingStatus.percentage
        if bufferPercent <> invalid and m.top.duration > 0
            bufferWidth = m.progressBarBase.width * (bufferPercent / 100)
            m.progressBarBuffer.width = bufferWidth
        end if
    end if
end sub

sub updateProgressBar()
    if m.isLiveStream
        ' For live streams, show minimal progress info
        m.timeProgress.text = "LIVE"
        m.timeDuration.text = "LIVE"
        m.progressBarProgress.width = m.progressBarBase.width ' Full bar for live
        m.progressDot.visible = false
    else if m.top.duration > 0 and m.currentPositionSeconds >= 0
        ' Update progress bar for VOD/clips
        progressRatio = m.currentPositionSeconds / m.top.duration
        m.progressBarProgress.width = m.progressBarBase.width * progressRatio

        ' Clamp the progress dot position within bounds
        dotX = m.progressBarBase.width * progressRatio - 8
        if dotX < 0 then dotX = 0
        if dotX > m.progressBarBase.width then dotX = m.progressBarBase.width

        m.progressDot.translation = [dotX, 59]
        m.progressDot.visible = true

        ' Update time displays
        m.timeProgress.text = convertToReadableTimeFormat(m.currentPositionSeconds)
        m.timeDuration.text = convertToReadableTimeFormat(m.top.duration)
    end if
end sub

sub showOverlay()
    m.isOverlayVisible = true
    m.controlOverlay.visible = true
    updateUIForVideoType() ' Ensure UI is correct for video type
    if m.isLiveStream then updateUptime()
    focusButton(m.currentFocusedButton)

    ' Start fade timer
    m.fadeAwayTimer.control = "stop"
    m.fadeAwayTimer.control = "start"
end sub

sub hideOverlay()
    m.isOverlayVisible = false
    m.controlOverlay.visible = false
    m.thumbnailPreview.visible = false
    clearAllButtonFocus()
end sub

sub onFadeAway()
    if not m.isTimeTravelDialogOpen
        hideOverlay()
    end if
end sub

sub focusButton(buttonIndex)
    clearAllButtonFocus()

    if m.isLiveStream
        ' Adjust button indices for live streams (only back, play/pause, chat available)
        if buttonIndex = 0 ' Back
            m.currentFocusedButton = 0
            m.backFocus.visible = true
        else if buttonIndex = 1 or buttonIndex = 2 or buttonIndex = 3 or buttonIndex = 4 ' Any middle button -> play/pause
            m.currentFocusedButton = 1
            m.playPauseFocus.visible = true
        else if buttonIndex = 5 ' Chat
            m.currentFocusedButton = 2
            m.chatFocus.visible = true
        end if
    else
        ' Normal button handling for VOD/clips
        m.currentFocusedButton = buttonIndex
        if buttonIndex = 0 ' Back
            m.backFocus.visible = true
        else if buttonIndex = 1 ' Time Travel
            m.timeTravelFocus.visible = true
        else if buttonIndex = 2 ' Rewind
            m.rewindFocus.visible = true
        else if buttonIndex = 3 ' Play/Pause
            m.playPauseFocus.visible = true
        else if buttonIndex = 4 ' Fast Forward
            m.fastForwardFocus.visible = true
        else if buttonIndex = 5 ' Chat
            m.chatFocus.visible = true
        end if
    end if
end sub

sub clearAllButtonFocus()
    m.playPauseFocus.visible = false
    m.rewindFocus.visible = false
    m.fastForwardFocus.visible = false
    m.timeTravelFocus.visible = false
    m.chatFocus.visible = false
    m.backFocus.visible = false
end sub

sub executeButtonAction()
    if m.isLiveStream
        ' Live stream button actions
        if m.currentFocusedButton = 0 ' Back
            ? getLogTimestamp(); " [CustomVideo] Back button pressed - attempting to exit"
            m.top.back = true
            if m.top.getParent() <> invalid
                m.top.getParent().back = true
            end if
            hideOverlay()
            m.top.control = "stop"
        else if m.currentFocusedButton = 1 ' Play/Pause
            togglePlayPause()
        else if m.currentFocusedButton = 2 ' Chat
            m.top.toggleChat = true
        end if
    else
        ' VOD/Clips button actions
        if m.currentFocusedButton = 0 ' Back
            ? getLogTimestamp(); " [CustomVideo] Back button pressed - attempting to exit"
            m.top.back = true
            if m.top.getParent() <> invalid
                m.top.getParent().back = true
            end if
            hideOverlay()
            m.top.control = "stop"
        else if m.currentFocusedButton = 1 ' Time Travel
            openTimeTravelDialog()
        else if m.currentFocusedButton = 2 ' Rewind
            seekRelative(-10)
        else if m.currentFocusedButton = 3 ' Play/Pause
            togglePlayPause()
        else if m.currentFocusedButton = 4 ' Fast Forward
            seekRelative(10)
        else if m.currentFocusedButton = 5 ' Chat
            m.top.toggleChat = true
        end if
    end if
end sub

sub togglePlayPause()
    if m.isSeekMode and not m.isLiveStream
        ' Apply seek for VOD/clips
        m.top.seek = m.currentPositionSeconds
        m.isSeekMode = false
        m.currentPositionUpdated = false
        ' Hide thumbnail preview after seeking
        m.thumbnailPreview.visible = false
    else
        ' Toggle play/pause
        if m.top.state = "paused"
            m.top.control = "resume"
        else
            m.top.control = "pause"
        end if
    end if
end sub

sub seekRelative(seconds)
    if m.isLiveStream
        ? getLogTimestamp(); " [CustomVideo] Seeking disabled for live streams"
        return
    end if

    if not m.isSeekMode
        m.currentPositionSeconds = m.top.position
        m.isSeekMode = true
        m.top.control = "pause"
    end if

    m.currentPositionSeconds += seconds
    if m.currentPositionSeconds < 0
        m.currentPositionSeconds = 0
    else if m.currentPositionSeconds > m.top.duration
        m.currentPositionSeconds = m.top.duration
    end if

    updateProgressBar()
    showThumbnailPreview()
end sub

sub showThumbnailPreview()
    if m.isLiveStream
        return ' No thumbnails for live streams
    end if

    if m.top.thumbnailInfo <> invalid and m.top.thumbnailInfo.width <> invalid
        m.thumbnailPreview.visible = true
        m.thumbnailTime.text = convertToReadableTimeFormat(m.currentPositionSeconds)

        ' Guard against divide-by-zero and invalid thumbnail_parts
        if m.top.thumbnailInfo.thumbnail_parts <> invalid and m.top.thumbnailInfo.thumbnail_parts.Count() > 0
            ' Calculate thumbnail position
            thumbnailsPerPart = Int(m.top.thumbnailInfo.count / m.top.thumbnailInfo.thumbnail_parts.Count())

            ' Additional guard to ensure thumbnailsPerPart is valid
            if thumbnailsPerPart > 0
                thumbnailPosOverall = Int(m.currentPositionSeconds / m.top.thumbnailInfo.interval)
                thumbnailPosCurrent = thumbnailPosOverall mod thumbnailsPerPart
                thumbnailRow = Int(thumbnailPosCurrent / m.top.thumbnailInfo.cols)
                thumbnailCol = Int(thumbnailPosCurrent mod m.top.thumbnailInfo.cols)

                m.thumbnailImage.translation = [-thumbnailCol * m.top.thumbnailInfo.width, -thumbnailRow * m.top.thumbnailInfo.height]

                ' Check bounds before accessing thumbnail_parts array
                partIndex = Int(thumbnailPosOverall / thumbnailsPerPart)
                if m.top.thumbnailInfo.info_url <> invalid and partIndex < m.top.thumbnailInfo.thumbnail_parts.Count() and m.top.thumbnailInfo.thumbnail_parts[partIndex] <> invalid
                    m.thumbnailImage.uri = m.top.thumbnailInfo.info_url + m.top.thumbnailInfo.thumbnail_parts[partIndex]
                end if
            end if
        end if

        ' Position thumbnail preview near progress bar
        progressRatio = m.currentPositionSeconds / m.top.duration
        thumbnailX = 60 + (m.progressBarBase.width * progressRatio) - 100
        if thumbnailX < 60 then thumbnailX = 60
        if thumbnailX > 1660 then thumbnailX = 1660
        m.thumbnailPreview.translation = [thumbnailX, 760]
    end if
end sub

sub openTimeTravelDialog()
    if m.isLiveStream
        ? getLogTimestamp(); " [CustomVideo] Time travel disabled for live streams"
        return
    end if

    m.isTimeTravelDialogOpen = true
    m.timeTravelDialog.visible = true
    m.timeTravelFocusedField = 0
    focusTimeTravelField(0)

    ' Reset all time values
    for i = 0 to 5
        m.timeTexts[i].text = "0"
    end for
end sub

sub closeTimeTravelDialog()
    m.isTimeTravelDialogOpen = false
    m.timeTravelDialog.visible = false
    clearTimeTravelFocus()
end sub

sub focusTimeTravelField(fieldIndex)
    clearTimeTravelFocus()
    m.timeTravelFocusedField = fieldIndex

    if fieldIndex >= 0 and fieldIndex <= 5
        ' Focus time field
        m.timeFields[fieldIndex].visible = true
    else if fieldIndex = 6
        ' Focus cancel button
        m.timeButtonFocus[0].visible = true
    else if fieldIndex = 7
        ' Focus accept button
        m.timeButtonFocus[1].visible = true
    end if
end sub

sub clearTimeTravelFocus()
    for i = 0 to 5
        m.timeFields[i].visible = false
    end for
    m.timeButtonFocus[0].visible = false
    m.timeButtonFocus[1].visible = false
end sub

sub executeTimeTravelAction()
    if m.timeTravelFocusedField >= 0 and m.timeTravelFocusedField <= 5
        ' Move to buttons
        focusTimeTravelField(6)
    else if m.timeTravelFocusedField = 6
        ' Cancel
        closeTimeTravelDialog()
    else if m.timeTravelFocusedField = 7
        ' Accept - jump to time
        jumpToTime = getTimeTravelTime()

        ' Ensure we're not in seek mode when applying time travel
        m.isSeekMode = false
        m.currentPositionUpdated = false

        ' Apply the seek immediately
        m.top.seek = jumpToTime

        ' Update our internal position tracking
        m.currentPositionSeconds = jumpToTime

        ' Update the progress bar to reflect the new position
        updateProgressBar()

        ' Hide thumbnail preview if it was visible
        m.thumbnailPreview.visible = false

        closeTimeTravelDialog()
    end if
end sub

function getTimeTravelTime() as integer
    hour0 = Int(Val(m.timeTexts[0].text)) * 36000
    hour1 = Int(Val(m.timeTexts[1].text)) * 3600
    minute0 = Int(Val(m.timeTexts[2].text)) * 600
    minute1 = Int(Val(m.timeTexts[3].text)) * 60
    second0 = Int(Val(m.timeTexts[4].text)) * 10
    second1 = Int(Val(m.timeTexts[5].text))
    return hour0 + hour1 + minute0 + minute1 + second0 + second1
end function

sub changeTimeTravelValue(direction)
    if m.timeTravelFocusedField >= 0 and m.timeTravelFocusedField <= 5
        currentValue = Int(Val(m.timeTexts[m.timeTravelFocusedField].text))

        ' Store old value for rollback if needed
        oldValue = currentValue
        if direction > 0
            currentValue += 1
        else
            currentValue -= 1
        end if

        ' Apply limits based on field type
        if m.timeTravelFocusedField = 2 or m.timeTravelFocusedField = 4 ' Minutes/seconds tens
            if currentValue > 5 then currentValue = 0
            if currentValue < 0 then currentValue = 5
        else
            if currentValue > 9 then currentValue = 0
            if currentValue < 0 then currentValue = 9
        end if

        m.timeTexts[m.timeTravelFocusedField].text = currentValue.toStr()
        ' Validate total time doesn't exceed video duration
        totalTime = getTimeTravelTime()
        if totalTime > m.top.duration and m.top.duration > 0
            ' Rollback to old value if exceeded
            m.timeTexts[m.timeTravelFocusedField].text = oldValue.toStr()
        end if
    end if
end sub

sub onButtonHold()
    if m.isLiveStream
        return ' No seeking for live streams
    end if

    if m.buttonHeld = "left"
        seekRelative(-m.scrollInterval)
        m.scrollInterval += 5
    else if m.buttonHeld = "right"
        seekRelative(m.scrollInterval)
        m.scrollInterval += 5
    end if
end sub

function convertToReadableTimeFormat(time) as string
    time = Int(time)
    if time < 3600
        minutes = Int(time / 60)
        seconds = Int(time mod 60)
        if seconds < 10
            secondStr = "0" + seconds.toStr()
        else
            secondStr = seconds.toStr()
        end if
        return minutes.toStr() + ":" + secondStr
    else
        hours = Int(time / 3600)
        minutes = Int((time mod 3600) / 60)
        seconds = Int(time mod 60)

        if minutes < 10
            minuteStr = "0" + minutes.toStr()
        else
            minuteStr = minutes.toStr()
        end if

        if seconds < 10
            secondStr = "0" + seconds.toStr()
        else
            secondStr = seconds.toStr()
        end if

        return hours.toStr() + ":" + minuteStr + ":" + secondStr
    end if
end function

sub saveVideoBookmark()
    ' Bookmark saving logic (keeping your existing implementation)
    if m.top.video_type = "LIVE" or m.top.video_type = "VOD"
        bookmarkPosition = Int(m.top.position)
        if m.top.video_type = "LIVE" and m.top?.content?.createdAt <> invalid
            secondsSincePublished = createObject("roDateTime")
            secondsSincePublished.FromISO8601String(m.top.content.createdAt.toStr())
            currentTime = createObject("roDateTime").AsSeconds()
            bookmarkPosition = currentTime - secondsSincePublished.AsSeconds()
        end if

        if m.top.video_type = "VOD" then saveLocalBookmark(m.top.video_id, bookmarkPosition)

        if get_user_setting("id", invalid) <> invalid
            if m.bookmarkTask <> invalid
                m.bookmarkTask = invalid
            end if
            m.bookmarkTask = createObject("roSGNode", "TwitchApiTask")
            m.bookmarkTask.functionname = "updateUserViewedVideo"
            m.bookmarkTask.request = {
                "userId": get_user_setting("id"),
                "position": bookmarkPosition,
                "videoId": m.top.video_id,
                "videoType": m.top.video_type
            }
            m.bookmarkTask.control = "run"
        end if
    end if
end sub

' Resume reads this local map; the Twitch sync only refreshes it, so a replay no
' longer depends on the cloud round trip or on being logged in.
sub saveLocalBookmark(videoId as string, position as integer)
    if videoId = "" then return
    raw = get_user_setting("VideoBookmarks", "")
    bookmarks = invalid
    if raw <> "" then bookmarks = ParseJSON(raw)
    if type(bookmarks) <> "roAssociativeArray" then bookmarks = {}
    ' ponytail: start over when a new VOD would pass 200 entries, keep an LRU if that loses real history
    if bookmarks.Count() >= 200 and not bookmarks.DoesExist(videoId) then bookmarks = {}
    bookmarks[videoId] = position.toStr()
    set_user_setting("VideoBookmarks", FormatJson(bookmarks))
end sub

sub showErrorMessage(title as string, message as string)
    showMessage(title, message, 0)
end sub

sub hideErrorMessage()
    hideMessage()
end sub

sub showMessage(title as string, message as string, duration as float)
    createMessageOverlay()
    if m.messageOverlay <> invalid
        titleNode = m.messageOverlay.findNode("messageTitle")
        if titleNode <> invalid
            titleNode.text = title
            titleNode.visible = (title <> "")
        end if
        messageNode = m.messageOverlay.findNode("messageText")
        if messageNode <> invalid
            messageNode.text = message
            if title = ""
                messageNode.translation = [660, 515]
            else
                messageNode.translation = [660, 530]
            end if
        end if
    end if

    m.messageOverlay.visible = true

    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer = invalid
    end if

    if duration > 0
        m.messageTimer = CreateObject("roSGNode", "Timer")
        m.messageTimer.duration = duration
        m.messageTimer.repeat = false
        m.messageTimer.observeField("fire", "onMessageTimeout")
        m.messageTimer.control = "start"
    end if
end sub

sub hideMessage()
    if m.messageOverlay <> invalid
        m.messageOverlay.visible = false
    end if
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer = invalid
    end if
end sub

sub onMessageTimeout()
    hideMessage()
    m.messageTimer = invalid
end sub

sub showLoadingOverlay()
    if m.loadingOverlay <> invalid
        m.loadingOverlay.visible = true
    end if
    if m.loadingSpinner <> invalid
        m.loadingSpinner.control = "start"
    end if
end sub

sub hideLoadingOverlay()
    if m.loadingOverlay <> invalid
        m.loadingOverlay.visible = false
    end if
    if m.loadingSpinner <> invalid
        m.loadingSpinner.control = "stop"
    end if
end sub

function onKeyEvent(key, press) as boolean
    ? getLogTimestamp(); " [CustomVideo] KeyEvent: "; key; " "; press

    if press
        ' Reset fade timer on any key press
        if m.isOverlayVisible
            m.fadeAwayTimer.control = "stop"
            m.fadeAwayTimer.control = "start"
        end if

        if m.isTimeTravelDialogOpen
            return handleTimeTravelKeys(key)
        else
            return handleMainKeys(key)
        end if
    else
        ' Handle key release
        if key = "rewind" or key = "fastforward"
            m.buttonHeld = invalid
            m.buttonHoldTimer.control = "stop"
            m.scrollInterval = 10
            if m.isSeekMode
                m.thumbnailPreview.visible = false
            end if
        end if
    end if

    return false
end function

function handleMainKeys(key) as boolean
    ' Netflix-style Skip Intro/Muted Audio: if the skip button is visible, OK immediately skips past mute
    if key = "OK" and m.skipMuteButton <> invalid and m.skipMuteButton.visible = true and not m.isOverlayVisible
        if m.currentMutedTarget <> invalid and m.currentMutedTarget > 0
            m.top.seek = m.currentMutedTarget
            hideSkipMuteButton()
            showMuteToast("Silencio saltado")
            return true
        end if
    end if

    if key = "up" or key = "OK" or key = "play"
        if not m.isOverlayVisible
            showOverlay()
            return true
        end if
    end if

    if not m.isOverlayVisible
        return false
    end if

    if key = "left"
        if m.isLiveStream
            ' Live stream navigation: back(0) -> play/pause(1) -> chat(2)
            if m.currentFocusedButton > 0
                focusButton(m.currentFocusedButton - 1)
            else
                focusButton(2) ' Wrap to chat
            end if
        else
            ' Normal navigation
            if m.currentFocusedButton > 0
                focusButton(m.currentFocusedButton - 1)
            else
                focusButton(5) ' Wrap to chat button
            end if
        end if
        return true
    else if key = "right"
        if m.isLiveStream
            ' Live stream navigation: back(0) -> play/pause(1) -> chat(2)
            if m.currentFocusedButton < 2
                focusButton(m.currentFocusedButton + 1)
            else
                focusButton(0) ' Wrap to back
            end if
        else
            ' Normal navigation
            if m.currentFocusedButton < 5
                focusButton(m.currentFocusedButton + 1)
            else
                focusButton(0) ' Wrap to back button
            end if
        end if
        return true
    else if key = "down" or key = "back"
        hideOverlay()
        return true
    else if key = "OK"
        executeButtonAction()
        return true
    else if key = "play"
        togglePlayPause()
        return true
    else if key = "rewind"
        if not m.isLiveStream
            m.buttonHeld = "left"
            m.buttonHoldTimer.control = "start"
            seekRelative(-10)
        end if
        return true
    else if key = "fastforward"
        if not m.isLiveStream
            m.buttonHeld = "right"
            m.buttonHoldTimer.control = "start"
            seekRelative(10)
        end if
        return true
    end if

    return false
end function

function handleTimeTravelKeys(key) as boolean
    if key = "left"
        if m.timeTravelFocusedField > 0
            focusTimeTravelField(m.timeTravelFocusedField - 1)
        end if
        return true
    else if key = "right"
        if m.timeTravelFocusedField < 7
            focusTimeTravelField(m.timeTravelFocusedField + 1)
        end if
        return true
    else if key = "up"
        if m.timeTravelFocusedField >= 0 and m.timeTravelFocusedField <= 5
            changeTimeTravelValue(1)
        else if m.timeTravelFocusedField = 6
            focusTimeTravelField(5)
        else if m.timeTravelFocusedField = 7
            focusTimeTravelField(5)
        end if
        return true
    else if key = "down"
        if m.timeTravelFocusedField >= 0 and m.timeTravelFocusedField <= 5
            changeTimeTravelValue(-1)
        else if m.timeTravelFocusedField <= 5
            focusTimeTravelField(6)
        end if
        return true
    else if key = "OK"
        executeTimeTravelAction()
        return true
    else if key = "back"
        closeTimeTravelDialog()
        return true
    end if

    return false
end function

sub onDestroy()
    if m.fadeAwayTimer <> invalid
        m.fadeAwayTimer.control = "stop"
        m.fadeAwayTimer.unobserveField("fire")
    end if
    if m.buttonHoldTimer <> invalid
        m.buttonHoldTimer.control = "stop"
        m.buttonHoldTimer.unobserveField("fire")
    end if
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
    end if
    if m.chatToastTimer <> invalid
        m.chatToastTimer.control = "stop"
        m.chatToastTimer.unobserveField("fire")
    end if
    if m.muteToastTimer <> invalid
        m.muteToastTimer.control = "stop"
        m.muteToastTimer.unobserveField("fire")
    end if
    m.mutedTask = destroyTask(m.mutedTask, "response")
    m.top.unobserveField("position")
    m.top.unobserveField("state")
    m.top.unobserveField("chatIsVisible")
    m.top.unobserveField("streamLayoutMode")
    m.top.unobserveField("duration")
    m.top.unobserveField("bufferingStatus")
    m.top.unobserveField("video_type")
end sub
