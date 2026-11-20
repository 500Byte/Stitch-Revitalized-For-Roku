' Shared HUD overlay, loading spinner, toast, and quality modal helpers
' included by both CustomVideo and StitchVideo.

function hudGetChatWidth() as integer
    if m.top.chatWidth <> invalid and m.top.chatWidth > 0
        return m.top.chatWidth
    else if m.global <> invalid and m.global.constants <> invalid and m.global.constants.chatWidth <> invalid and m.global.constants.chatWidth > 0
        return m.global.constants.chatWidth
    end if
    return 420
end function

function hudFormatTime(time as dynamic) as string
    secs = 0
    if time <> invalid then secs = Int(time)
    if secs < 0 then secs = 0
    if secs < 3600
        minutes = Int(secs / 60)
        seconds = Int(secs mod 60)
        if seconds < 10
            secondStr = "0" + seconds.toStr()
        else
            secondStr = seconds.toStr()
        end if
        return minutes.toStr() + ":" + secondStr
    else
        hours = Int(secs / 3600)
        minutes = Int((secs mod 3600) / 60)
        seconds = Int(secs mod 60)
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

sub hudCreateMessageOverlay()
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

sub hudShowMessage(title as string, message as string, duration as float)
    hudCreateMessageOverlay()
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
        m.messageOverlay.visible = true
    end if

    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
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

sub hudHideMessage()
    if m.messageOverlay <> invalid
        m.messageOverlay.visible = false
    end if
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
        m.messageTimer = invalid
    end if
end sub

sub hudOnMessageTimeout()
    hudHideMessage()
end sub

sub hudOnStreamLayoutModeChange()
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
        hudShowChatToast(text)
    end if
end sub

sub hudShowChatToast(text as string)
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

sub hudHideChatToast()
    if m.chatModeToastGroup <> invalid then m.chatModeToastGroup.visible = false
end sub

sub hudShowLoadingOverlay()
    if m.loadingOverlay <> invalid
        m.loadingOverlay.visible = true
    end if
    if m.loadingSpinner <> invalid
        m.loadingSpinner.control = "start"
    end if
end sub

sub hudHideLoadingOverlay()
    if m.loadingOverlay <> invalid
        m.loadingOverlay.visible = false
    end if
    if m.loadingSpinner <> invalid
        m.loadingSpinner.control = "stop"
    end if
end sub

sub hudShowQualityDialog()
    if m.qualityModal = invalid then return
    if m.top.qualityOptions <> invalid and m.top.qualityOptions.count() > 0
        if m.fadeAwayTimer <> invalid then m.fadeAwayTimer.control = "stop"
        m.qualityModal.qualityOptions = m.top.qualityOptions
        m.qualityModal.currentQuality = m.top.selectedQuality
        m.qualityModal.visible = true
        m.qualityModal.setFocus(true)
    end if
end sub

sub hudOnQualityModalSelected()
    if m.qualityModal = invalid then return
    selectedIndex = m.qualityModal.selectedQualityIndex
    if selectedIndex >= 0 and m.top.qualityOptions <> invalid and selectedIndex < m.top.qualityOptions.count()
        m.top.selectedQuality = m.top.qualityOptions[selectedIndex]
        m.top.QualityChangeRequest = selectedIndex
        m.top.QualityChangeRequestFlag = true
    end if
    m.top.setFocus(true)
    if m.fadeAwayTimer <> invalid then m.fadeAwayTimer.control = "start"
end sub

sub hudOnQualityModalClosed()
    m.top.setFocus(true)
    if m.fadeAwayTimer <> invalid then m.fadeAwayTimer.control = "start"
end sub

sub hudCloseQualityDialog(restartTimer = true as boolean)
    if m.qualityModal <> invalid and m.qualityModal.visible
        m.qualityModal.visible = false
        m.top.setFocus(true)
    end if
    if restartTimer and m.fadeAwayTimer <> invalid
        m.fadeAwayTimer.control = "start"
    end if
end sub

sub hudDestroyShared()
    if m.fadeAwayTimer <> invalid
        m.fadeAwayTimer.control = "stop"
        m.fadeAwayTimer.unobserveField("fire")
    end if
    if m.messageTimer <> invalid
        m.messageTimer.control = "stop"
        m.messageTimer.unobserveField("fire")
        m.messageTimer = invalid
    end if
    if m.chatToastTimer <> invalid
        m.chatToastTimer.control = "stop"
        m.chatToastTimer.unobserveField("fire")
    end if
    if m.loadingSpinner <> invalid
        m.loadingSpinner.control = "stop"
    end if
    if m.qualityModal <> invalid
        m.qualityModal.unobserveField("qualitySelected")
        m.qualityModal.unobserveField("wasClosed")
        m.qualityModal.visible = false
    end if
end sub
