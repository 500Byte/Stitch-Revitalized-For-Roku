sub init()
    m.modalContainer = m.top.findNode("modalContainer")
    m.cardBorder = m.top.findNode("cardBorder")
    m.cardBg = m.top.findNode("cardBg")
    m.optionsContainer = m.top.findNode("optionsContainer")
    m.cancelButtonGroup = m.top.findNode("cancelButtonGroup")
    m.cancelFocus = m.top.findNode("cancelFocus")

    m.optionsCount = 0
    m.focusedIndex = 0
    m.focusPosters = []
    m.checkPosters = []

    m.top.observeField("visible", "onVisibleChange")
end sub

sub onVisibleChange()
    if m.top.visible = true
        ' Initial focus matches active quality if possible
        if m.top.currentQuality <> invalid and m.top.currentQuality <> "" and m.top.qualityOptions <> invalid
            for i = 0 to m.top.qualityOptions.count() - 1
                if m.top.qualityOptions[i] = m.top.currentQuality
                    m.focusedIndex = i
                    exit for
                end if
            end for
        else
            m.focusedIndex = 0
        end if
        updateFocus()
    end if
end sub

sub onQualityOptionsChange()
    if m.top.qualityOptions = invalid then return

    ' Clear existing rows
    m.optionsContainer.removeChildrenIndex(m.optionsContainer.getChildCount(), 0)
    m.focusPosters = []
    m.checkPosters = []

    options = m.top.qualityOptions
    m.optionsCount = options.count()
    if m.optionsCount = 0 then return

    rowStep = 58
    rowHeight = 50
    rowWidth = 608

    for i = 0 to m.optionsCount - 1
        optGroup = createObject("roSGNode", "Group")
        optGroup.translation = [0, i * rowStep]

        ' Background capsule
        bgPoster = createObject("roSGNode", "Poster")
        bgPoster.uri = "pkg:/images/capsule.9.png"
        bgPoster.width = rowWidth
        bgPoster.height = rowHeight
        bgPoster.blendColor = "0x26262C88"
        optGroup.appendChild(bgPoster)

        ' Focused capsule
        focusPoster = createObject("roSGNode", "Poster")
        focusPoster.uri = "pkg:/images/capsule.9.png"
        focusPoster.width = rowWidth
        focusPoster.height = rowHeight
        focusPoster.blendColor = "0x9146FFFF"
        focusPoster.visible = false
        optGroup.appendChild(focusPoster)
        m.focusPosters.push(focusPoster)

        ' Option label
        label = createObject("roSGNode", "SimpleLabel")
        label.text = options[i]
        label.fontUri = "pkg:/fonts/Archivo-Bold.otf"
        label.fontSize = 18
        label.color = "0xFFFFFFFF"
        label.translation = [24, 15]
        optGroup.appendChild(label)

        ' Checkmark icon
        checkPoster = createObject("roSGNode", "Poster")
        checkPoster.uri = "pkg:/images/icons/check.png"
        checkPoster.width = 22
        checkPoster.height = 22
        checkPoster.translation = [560, 14]
        checkPoster.blendColor = "0x9146FFFF"
        checkPoster.visible = (options[i] = m.top.currentQuality)
        optGroup.appendChild(checkPoster)
        m.checkPosters.push(checkPoster)

        m.optionsContainer.appendChild(optGroup)
    end for

    ' Dynamic card sizing and vertical centering
    optionsTotalH = m.optionsCount * rowStep
    cancelY = 98 + optionsTotalH + 8
    m.cancelButtonGroup.translation = [36, cancelY]

    cardHeight = cancelY + 52 + 20
    modalY = Int((1080 - cardHeight) / 2)
    if modalY < 60 then modalY = 60

    m.modalContainer.translation = [620, modalY]
    m.cardBorder.height = cardHeight
    m.cardBg.height = cardHeight - 4

    updateFocus()
end sub

sub onCurrentQualityChange()
    if m.top.qualityOptions = invalid or m.checkPosters = invalid then return
    current = m.top.currentQuality
    for i = 0 to m.checkPosters.count() - 1
        if i < m.top.qualityOptions.count()
            isActive = (m.top.qualityOptions[i] = current)
            m.checkPosters[i].visible = isActive
        end if
    end for
end sub

sub updateFocus()
    totalItems = m.optionsCount + 1
    if totalItems <= 1 then return

    for i = 0 to m.optionsCount - 1
        isFocused = (m.focusedIndex = i)
        if i < m.focusPosters.count()
            m.focusPosters[i].visible = isFocused
        end if
        ' When row is focused, checkmark turns white for contrast
        if i < m.checkPosters.count()
            if isFocused
                m.checkPosters[i].blendColor = "0xFFFFFFFF"
            else
                m.checkPosters[i].blendColor = "0x9146FFFF"
            end if
        end if
    end for

    m.cancelFocus.visible = (m.focusedIndex = m.optionsCount)
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    totalItems = m.optionsCount + 1

    if key = "up"
        m.focusedIndex = (m.focusedIndex - 1 + totalItems) mod totalItems
        updateFocus()
        return true
    else if key = "down"
        m.focusedIndex = (m.focusedIndex + 1) mod totalItems
        updateFocus()
        return true
    else if key = "OK"
        if m.focusedIndex < m.optionsCount
            m.top.selectedQualityIndex = m.focusedIndex
            m.top.qualitySelected = true
            m.top.visible = false
        else
            m.top.wasClosed = true
            m.top.visible = false
        end if
        return true
    else if key = "back"
        m.top.wasClosed = true
        m.top.visible = false
        return true
    end if

    return false
end function
