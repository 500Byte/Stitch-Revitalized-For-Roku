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

    ' Control buttons
    m.backGroup = m.top.findNode("backGroup")
    m.chatGroup = m.top.findNode("chatGroup")
    m.playPauseGroup = m.top.findNode("playPauseGroup")
    m.qualityGroup = m.top.findNode("qualityGroup")
    m.controlButton = m.top.findNode("controlButton")
    m.messagesButton = m.top.findNode("messagesButton")
    m.qualitySelectButton = m.top.findNode("qualitySelectButton")

    ' Focus backgrounds
    m.backFocus = m.top.findNode("backFocus")
    m.chatFocus = m.top.findNode("chatFocus")
    m.playPauseFocus = m.top.findNode("playPauseFocus")
    m.qualityFocus = m.top.findNode("qualityFocus")

    ' Other elements
    m.liveIndicator = m.top.findNode("liveIndicator")
    m.topOverlayGroup = m.top.findNode("topOverlayGroup")
    m.bottomOverlayGroup = m.top.findNode("bottomOverlayGroup")
    m.actionControlsGroup = m.top.findNode("actionControlsGroup")
    m.scrimTop = m.top.findNode("scrimTop")
    m.scrimBottom = m.top.findNode("scrimBottom")

    ' Video info
    m.videoTitle = m.top.findNode("videoTitle")
    m.channelUsername = m.top.findNode("channelUsername")
    m.avatar = m.top.findNode("avatar")

    ' Loading overlay
    m.loadingOverlay = m.top.findNode("loadingOverlay")
    m.loadingSpinner = m.top.findNode("loadingSpinner")

    ' Quality dialog modal
    m.qualityModal = m.top.findNode("qualityDialogModal")
    if m.qualityModal <> invalid
        m.qualityModal.observeField("qualitySelected", "onQualityModalSelected")
        m.qualityModal.observeField("wasClosed", "onQualityModalClosed")
    end if

    ' State variables
    m.currentFocusedButton = 0 ' 0=play/pause, 1=chat, 2=quality
    m.isOverlayVisible = false
    m.currentPositionSeconds = 0

    ' Timers
    m.fadeAwayTimer = createObject("roSGNode", "Timer")
    m.fadeAwayTimer.observeField("fire", "onFadeAway")
    m.fadeAwayTimer.repeat = false
    m.fadeAwayTimer.duration = 5
    m.fadeAwayTimer.control = "stop"

    ' Live-edge latency diagnostic timer.
    ' Logs streamingSegment.latency every 5s while the stream is active
    ' (started on state=playing, stopped on paused/error/finished/stopped;
    ' continues to fire during buffering so buffer dips are visible in logs).
    ' See AGENTS.md / DEV.md for how to read these logs over the debug console.
    m.latencyLogTimer = createObject("roSGNode", "Timer")
    m.latencyLogTimer.observeField("fire", "onLatencyLogFire")
    m.latencyLogTimer.repeat = true
    m.latencyLogTimer.duration = 5
    m.latencyLogTimer.control = "stop"

    ' One-shot timer for the post-startup live-edge re-anchor.
    ' Fires ~3s after state=playing settles, then issues a single seek=999999.
    ' Roku's streaming spec endorses seek=999999 as the canonical "go to live"
    ' sentinel: the player clips it to the current availability window.
    ' m.startupSeekFired guards against re-firing on every state transition -
    ' a single seek causes its own buffering/playing cycle, which would
    ' otherwise re-arm this timer in onVideoStateChange and create a tight
    ' 3s seek loop. Reset to false only when content is reassigned (i.e. a
    ' new stream is loaded).
    m.startupSeekFired = false
    m.liveEdgeStartupTimer = createObject("roSGNode", "Timer")
    m.liveEdgeStartupTimer.observeField("fire", "onLiveEdgeStartupFire")
    m.liveEdgeStartupTimer.repeat = false
    m.liveEdgeStartupTimer.duration = 3
    m.liveEdgeStartupTimer.control = "stop"

    ' Suppress the loading overlay during the brief (~200-400ms) re-buffer
    ' that follows the app-initiated live-edge seek. Set true right before
    ' the seek, cleared on the next state=playing. Without this, the user
    ' sees a quick spinner flash right after the stream first starts which
    ' looks like a stutter, even though the seek is working as intended.
    m.suppressLoadingOverlayUntilPlaying = false

    m.chatModeToastGroup = m.top.findNode("chatModeToastGroup")
    m.chatModeToast = m.top.findNode("chatModeToast")
    m.uptimeLabel = m.top.findNode("uptimeLabel")
    m.liveBadgeBg = m.top.findNode("liveBadgeBg")
    m.liveBadgeText = m.top.findNode("liveBadgeText")
    m.liveCapsuleBg = m.top.findNode("liveCapsuleBg")

    ' Observers
    m.top.observeField("position", "onPositionChange")
    m.top.observeField("state", "onVideoStateChange")
    m.top.observeField("content", "onContentChange")
    m.top.observeField("chatIsVisible", "onChatVisibilityChange")
    m.top.observeField("chatWidth", "onChatVisibilityChange")
    m.top.observeField("streamLayoutMode", "onStreamLayoutModeChange")
    m.top.observeField("duration", "onDurationChange")
    m.top.observeField("bufferingStatus", "onBufferingStatusChange")
    m.top.observeField("selectedQuality", "onSelectedQualityChange")

    ' Initialize UI
    updateProgressBar()
    setupLiveUI()

    ' Show loading overlay initially
    showLoadingOverlay()

    ' ? "[StitchVideo] Initialized for live stream"
end sub

sub createMessageOverlay()
    hudCreateMessageOverlay()
end sub

sub setupLiveUI()
    ' Set up UI specifically for live streams
    m.progressBarProgress.width = m.progressBarBase.width ' Full bar for live

    ' Live indicator is only visible when overlay is shown
    m.liveIndicator.visible = m.isOverlayVisible
end sub


sub onPositionChange()
    m.currentPositionSeconds = m.top.position
    if m.isOverlayVisible = true
        updateUptime()
    end if
end sub

' Re-arm the one-shot startup seek when a fresh stream is loaded.
' Setting m.top.content fires this; we use it to reset the latched flag so
' the next stream session gets its own startup seek. Also clear the recent
' seek timestamp - otherwise the watchdog cooldown could be triggered by a
' stale value from the previous stream session.
sub onContentChange()
    if m.top.content <> invalid
        m.startupSeekFired = false
        m.top.recentSeekTimestamp = 0
    end if
end sub

sub onVideoStateChange()
    ? getLogTimestamp(); " [StitchVideo][state] state="; m.top.state; " pos="; m.top.position
    if m.top.state = "playing"
        m.controlButton.uri = "pkg:/images/icons/pause-hero.png"
        hideLoadingOverlay()
        ' Reaching "playing" ends any post-seek re-buffer; re-enable the
        ' loading overlay for future, non-seek-related buffering events.
        m.suppressLoadingOverlayUntilPlaying = false
        hideMessage()
        startLatencyLog()
        ' Fire one immediate sample so we see latency even if the repeating
        ' timer is delayed/blocked for some reason.
        onLatencyLogFire()
        ' Arm the one-shot live-edge re-anchor (latched via m.startupSeekFired
        ' so it fires exactly once per stream session). VideoPlayer sets
        ' suppressStartupSeek=true on recovery paths (watchdog reconnect,
        ' error-driven retryPlayback) so we don't fight the conditions that
        ' caused the stall by immediately re-anchoring at the live edge.
        if m.top.suppressStartupSeek
            ? getLogTimestamp(); " [StitchVideo][seek] action=skip reason=recovery"
            m.startupSeekFired = true
        else
            startLiveEdgeStartupTimer()
        end if
    else if m.top.state = "paused"
        m.controlButton.uri = "pkg:/images/icons/play-hero.png"
        hideLoadingOverlay()
        stopLatencyLog()
        stopLiveEdgeStartupTimer()
    else if m.top.state = "buffering"
        ' The post-seek re-buffer is ~200-400ms and looks like a stutter
        ' to the user. issueLiveEdgeSeek sets the suppress flag immediately
        ' before issuing seek=999999, and the flag is cleared on the next
        ' state=playing. If the re-buffer ever runs longer than expected,
        ' VideoPlayer's stall watchdog (20s post-seek cooldown then 16s
        ' stall threshold) is still the safety net — no risk of silent
        ' hangs.
        if m.suppressLoadingOverlayUntilPlaying <> true
            showLoadingOverlay()
        end if
        stopLiveEdgeStartupTimer()
    else if m.top.state = "error"
        hideLoadingOverlay()
        m.suppressLoadingOverlayUntilPlaying = false
        stopLatencyLog()
        stopLiveEdgeStartupTimer()
        if m.top.errorStr <> invalid and (m.top.errorStr.InStr("970") > -1 or m.top.errorStr.InStr("buffer:loop:demux") > -1)
            showErrorMessage("Incompatible Video Format", "This stream cannot be played on your device")
        else
            showErrorMessage("Stream Error", "Having trouble loading the live stream. Retrying...")
        end if
    else if m.top.state = "finished" or m.top.state = "stopped"
        m.suppressLoadingOverlayUntilPlaying = false
        stopLatencyLog()
        stopLiveEdgeStartupTimer()
    end if
end sub

' ===== Live-edge latency diagnostics =====
' streamingSegment.latency = ms between live edge and the segment currently
' being played. This is the only Roku-exposed measurement of how far behind
' live we are. Useful for evaluating low-latency tuning.

sub startLatencyLog()
    if m.latencyLogTimer <> invalid
        m.latencyLogTimer.control = "start"
    end if
end sub

sub stopLatencyLog()
    if m.latencyLogTimer <> invalid
        m.latencyLogTimer.control = "stop"
    end if
end sub

sub onLatencyLogFire()
    ' Always print one line per fire so we can debug. No early returns:
    ' if streamingSegment is invalid we want to SEE that, not silently skip.
    seg = m.top.streamingSegment
    segValid = "no"
    segType = "?"
    latencyMs = "?"
    bitrate = "?"
    segSeq = "?"

    if seg <> invalid
        segValid = "yes"
        if seg.segType <> invalid then segType = seg.segType.toStr()
        if seg.latency <> invalid then latencyMs = seg.latency.toStr()
        if seg.segBitrateBps <> invalid then bitrate = seg.segBitrateBps.toStr()
        if seg.segSequence <> invalid then segSeq = seg.segSequence.toStr()
    end if

    measured = m.top.measuredBitrate

    ? getLogTimestamp(); " [StitchVideo][latency] state="; m.top.state; " pos="; m.top.position; " seg_valid="; segValid; " seg_type="; segType; " live_edge_ms="; latencyMs; " seg_bitrate_bps="; bitrate; " measured_bps="; measured; " seg_seq="; segSeq
end sub

' ===== Live-edge re-anchor (strategies B and C) =====
' Roku's streaming spec endorses seek=999999 as the canonical "go to live"
' sentinel - the platform clips the position to the current availability
' window. Both timers below use this mechanism. We log a one-line snapshot
' of live_edge_ms BEFORE every seek so we can correlate before/after impact
' against the regular 5s latency timer.

sub startLiveEdgeStartupTimer()
    if m.startupSeekFired = true then return
    if m.liveEdgeStartupTimer <> invalid
        m.liveEdgeStartupTimer.control = "stop"
        m.liveEdgeStartupTimer.control = "start"
    end if
end sub

sub stopLiveEdgeStartupTimer()
    if m.liveEdgeStartupTimer <> invalid
        m.liveEdgeStartupTimer.control = "stop"
    end if
end sub

sub onLiveEdgeStartupFire()
    m.startupSeekFired = true
    issueLiveEdgeSeek("startup")
end sub

' Single point of seek=999999 application. Decides whether to fire the seek
' based on the current pre-seek latency: if we're already close to live the
' seek buys us nothing (and can even slightly increase latency), so we skip
' it.
'
' Bails if we're not in steady-state playing —
' that's a transient invocation race, not a real decision point.
sub issueLiveEdgeSeek(reason as string)
    if m.top.state <> "playing"
        ? getLogTimestamp(); " [StitchVideo][seek] action=skip reason="; reason; " state="; m.top.state
        return
    end if

    ' Pre-seek latency snapshot. preLatencyMs stays invalid when the
    ' segment isn't ready yet — we still fire the seek in that case so
    ' we don't regress behavior when latency is unmeasurable.
    seg = m.top.streamingSegment
    preLatency = "?"
    preLatencyMs = invalid
    if seg <> invalid and seg.latency <> invalid
        preLatency = seg.latency.toStr()
        preLatencyMs = seg.latency
    end if

    ' 1% sample of startup delay behind live (~9K events/month at current
    ' volume). Same measurement point as the old live_edge_seek pre value.
    if preLatencyMs <> invalid and Rnd(100) = 1
        trackEvent("live_latency", { live_edge_ms: preLatencyMs })
    end if

    ' Skip the seek if we're already close enough to live. The seek's
    ' empirically observed steady-state floor is ~20s behind live, so
    ' firing when already at <30s buys us nothing — we've seen latency
    ' actually increase by ~1s in that range. 30s gives ~10s headroom
    ' above the floor so the seek is only fired when it can meaningfully
    ' help.
    if preLatencyMs <> invalid and preLatencyMs < 30000
        ? getLogTimestamp(); " [StitchVideo][seek] action=skip reason="; reason; " pre_live_edge_ms="; preLatency; " already_near_live=true"
        return
    end if

    ? getLogTimestamp(); " [StitchVideo][seek] action=fire reason="; reason; " pre_live_edge_ms="; preLatency; " pos="; m.top.position
    ' Tell VideoPlayer's stall watchdog we just seeked so it doesn't treat
    ' the brief re-buffer that follows as a fake stall and force a reconnect.
    m.top.recentSeekTimestamp = CreateObject("roDateTime").AsSeconds()
    ' Hide the loading overlay during the brief post-seek re-buffer so the
    ' user doesn't see a spinner flash. Cleared when state returns to
    ' "playing" (typically ~200-400ms after the seek lands).
    m.suppressLoadingOverlayUntilPlaying = true
    m.top.seek = 999999
end sub

sub onChatVisibilityChange()
    chatW = hudGetChatWidth()

    ' Adjust layout based on chat visibility (Punto Medio LG + Apple TV)
    if m.top.chatIsVisible
        videoW = 1920 - chatW
        if videoW < 1200 then videoW = 1200
        seekW = videoW - 115
        m.progressBarBase.width = seekW
        m.progressBarProgress.width = seekW

        buttonsW = 258
        buttonsX = videoW - 45 - buttonsW
        if buttonsX < 900 then buttonsX = 900
        if m.actionControlsGroup <> invalid
            m.actionControlsGroup.translation = [buttonsX, 890]
        end if
        if m.videoTitle <> invalid
            m.videoTitle.maxWidth = buttonsX - 70 - 76 - 30
        end if
        if m.liveIndicator <> invalid
            m.liveIndicator.translation = [videoW - 270, 48]
        end if

        if m.scrimBottom <> invalid then m.scrimBottom.width = videoW
        if m.scrimTop <> invalid then m.scrimTop.width = videoW
    else
        m.progressBarBase.width = 1780
        m.progressBarProgress.width = 1780
        if m.actionControlsGroup <> invalid
            m.actionControlsGroup.translation = [1592, 890]
        end if
        if m.videoTitle <> invalid
            m.videoTitle.maxWidth = 1400
        end if
        if m.liveIndicator <> invalid
            m.liveIndicator.translation = [1630, 48]
        end if

        if m.scrimBottom <> invalid then m.scrimBottom.width = 1920
        if m.scrimTop <> invalid then m.scrimTop.width = 1920
    end if
    updateProgressBar()
end sub

sub onStreamLayoutModeChange()
    hudOnStreamLayoutModeChange()
end sub

sub showChatToast(text as string)
    hudShowChatToast(text)
end sub

sub hideChatToast()
    hudHideChatToast()
end sub

sub updateUptime()
    if m.uptimeLabel = invalid then return

    createdAtStr = ""
    if m.top.streamCreatedAt <> invalid and m.top.streamCreatedAt <> ""
        createdAtStr = m.top.streamCreatedAt
    else if m.top?.content?.createdAt <> invalid and m.top.content.createdAt <> ""
        createdAtStr = m.top.content.createdAt
    end if

    if createdAtStr <> ""
        startDt = createObject("roDateTime")
        startDt.FromISO8601String(createdAtStr)
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

            ' Dynamic badge width based on text length (e.g. "EN VIVO" vs "LIVE")
            textLen = 4
            if m.liveBadgeText <> invalid and m.liveBadgeText.text <> invalid
                textLen = len(m.liveBadgeText.text)
            end if
            badgeWidth = 56
            if textLen > 4
                badgeWidth = 84 ' Fits "EN VIVO" cleanly with padding
            end if
            if m.liveBadgeBg <> invalid
                m.liveBadgeBg.width = badgeWidth
            end if

            uptimeX = badgeWidth + 14
            m.uptimeLabel.translation = [uptimeX, 6]
            m.uptimeLabel.text = hStr + ":" + mStr + ":" + sStr
            m.uptimeLabel.visible = true

            if m.liveCapsuleBg <> invalid
                m.liveCapsuleBg.width = uptimeX + 85
            end if
            return
        end if
    end if
    m.uptimeLabel.visible = false
end sub

sub onDurationChange()
    updateProgressBar()
end sub

sub onBufferingStatusChange()
    ' Live streams handle buffering differently
    ' ? "[StitchVideo] Buffering status changed"
end sub

sub onSelectedQualityChange()
    setupLiveUI()
end sub

sub onQualityModalSelected()
    hudOnQualityModalSelected()
end sub

sub onQualityModalClosed()
    hudOnQualityModalClosed()
end sub

sub closeQualityDialog()
    hudCloseQualityDialog(true)
end sub

sub updateProgressBar()
    ' For live streams, always show full progress bar in Twitch purple
    m.progressBarProgress.width = m.progressBarBase.width
end sub

sub showOverlay()
    m.isOverlayVisible = true
    m.controlOverlay.visible = true
    m.liveIndicator.visible = true
    updateUptime()
    focusButton(m.currentFocusedButton)

    ' Start fade timer
    m.fadeAwayTimer.control = "stop"
    m.fadeAwayTimer.control = "start"
end sub

sub hideOverlay()
    m.isOverlayVisible = false
    m.controlOverlay.visible = false
    m.liveIndicator.visible = false
    clearAllButtonFocus()
end sub

sub onFadeAway()
    ' Only hide overlay if quality dialog is not visible
    if m.qualityModal = invalid or not m.qualityModal.visible
        hideOverlay()
    end if
end sub

sub focusButton(buttonIndex)
    clearAllButtonFocus()
    m.currentFocusedButton = buttonIndex

    ' Live stream buttons: 0=play/pause, 1=chat, 2=quality
    if buttonIndex = 0 ' Play/Pause
        m.playPauseFocus.visible = true
    else if buttonIndex = 1 ' Chat
        m.chatFocus.visible = true
    else if buttonIndex = 2 ' Quality
        m.qualityFocus.visible = true
    end if
end sub

sub clearAllButtonFocus()
    m.backFocus.visible = false
    m.chatFocus.visible = false
    m.playPauseFocus.visible = false
    m.qualityFocus.visible = false
end sub

sub executeButtonAction()
    ' Live stream button actions (0=play/pause, 1=chat, 2=quality)
    if m.currentFocusedButton = 0 ' Play/Pause
        togglePlayPause()
    else if m.currentFocusedButton = 1 ' Chat
        m.top.toggleChat = true
    else if m.currentFocusedButton = 2 ' Quality
        showQualityDialog()
    end if
end sub

sub togglePlayPause()
    if m.top.state = "paused"
        m.top.control = "resume"
    else
        m.top.control = "pause"
    end if
end sub

sub showQualityDialog()
    hudShowQualityDialog()
end sub

function convertToReadableTimeFormat(time) as string
    return hudFormatTime(time)
end function

sub showErrorMessage(title as string, message as string)
    hudShowMessage(title, message, 0) ' 0 duration means persistent
end sub

sub hideErrorMessage()
    hudHideMessage()
end sub

sub showMessage(title as string, message as string, duration as float)
    hudShowMessage(title, message, duration)
end sub

sub hideMessage()
    hudHideMessage()
end sub

sub onMessageTimeout()
    hudOnMessageTimeout()
end sub

sub showLoadingOverlay()
    hudShowLoadingOverlay()
end sub

sub hideLoadingOverlay()
    hudHideLoadingOverlay()
end sub

function onKeyEvent(key, press) as boolean
    ' ? "[StitchVideo] KeyEvent: "; key; " "; press

    if press
        ' Reset fade timer on any key press (except back when overlay is hidden)
        if key <> "back" or m.isOverlayVisible
            if m.isOverlayVisible
                m.fadeAwayTimer.control = "stop"
                m.fadeAwayTimer.control = "start"
            end if
        end if

        return handleMainKeys(key)
    end if

    return false
end function

function handleMainKeys(key) as boolean
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
        ' Live stream navigation: play/pause(0) -> chat(1) -> quality(2)
        if m.currentFocusedButton > 0
            focusButton(m.currentFocusedButton - 1)
        else
            focusButton(2) ' Wrap to quality
        end if
        return true
    else if key = "right"
        ' Live stream navigation: play/pause(0) -> chat(1) -> quality(2)
        if m.currentFocusedButton < 2
            focusButton(m.currentFocusedButton + 1)
        else
            focusButton(0) ' Wrap to play/pause
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
    end if

    return false
end function

sub onDestroy()
    hudCloseQualityDialog(false)
    hudDestroyShared()
    if m.qualityModal <> invalid then m.qualityModal.callFunc("onDestroy")
    if m.videoTitle <> invalid then m.videoTitle.callFunc("onDestroy")
    if m.latencyLogTimer <> invalid
        m.latencyLogTimer.control = "stop"
        m.latencyLogTimer.unobserveField("fire")
    end if
    if m.liveEdgeStartupTimer <> invalid
        m.liveEdgeStartupTimer.control = "stop"
        m.liveEdgeStartupTimer.unobserveField("fire")
    end if
    m.top.unobserveField("position")
    m.top.unobserveField("state")
    m.top.unobserveField("content")
    m.top.unobserveField("chatIsVisible")
    m.top.unobserveField("chatWidth")
    m.top.unobserveField("streamLayoutMode")
    m.top.unobserveField("duration")
    m.top.unobserveField("bufferingStatus")
    m.top.unobserveField("qualityOptions")
    m.top.unobserveField("selectedQuality")
end sub
