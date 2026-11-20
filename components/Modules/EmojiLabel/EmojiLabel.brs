' Copyright Kasper Gammeltoft and other contributors. Licensed under MIT
' https://github.com/KasperGam/EmojiOnRoku/blob/main/LICENSE
sub init()
    m.components = m.top.findNode("layout")
    m.top.observeField("text", "setText")
    m.animation = m.top.findNode("testAnimation")
    ' m.animation.duration = 0
    m.vector = m.top.findNode("testVector2D")
    ' kvArray = [
    '     [0, 0],
    '     [(0 - (m.components.boundingRect().width * 0.25)), m.components.translation[1]],
    '     [(0 - (m.components.boundingRect().width * 0.5)), m.components.translation[1]],
    '     [(0 - (m.components.boundingRect().width * 0.75)), m.components.translation[1]],
    '     [(0 - (m.components.boundingRect().width)), m.components.translation[1]]
    ' ]
    ' m.vector.keyValue = kvArray
    m.top.observeField("color", "updateComponents")
    m.top.observeField("font", "updateComponents")
    m.top.observeField("horizAlign", "updateComponents")
    m.top.observeField("vertAlign", "updateComponents")
    m.top.observeField("width", "updateComponents")
    m.top.observeField("repeatCount", "doScroll")
    m.top.observeField("emojiSize", "updateComponents")
    m.top.observeField("maxWidth", "updateComponents")
    m.timer = m.top.findNode("timer")
    if m.timer <> invalid
        m.timer.observeField("fire", "onTimerFireChange")
    end if
    m.scrollDelayTimer = createObject("roSGNode", "Timer")
    m.scrollDelayTimer.duration = 0.2
    m.scrollDelayTimer.repeat = false
    m.scrollDelayTimer.observeField("fire", "onScrollDelayFire")
    m.emojiRegex = invalid
    try
        m.emojiRegex = createObject("roRegex", regex(), "m")
    catch e
        m.emojiRegex = invalid
    end try
    setText()
end sub

sub onTimerFireChange() as void
    if m.animation = invalid or m.timer = invalid then return
    m.animation.repeat = false
    m.animation.control = "stop"
    m.components.translation = [0, 0]
    m.timer.control = "stop"
end sub

sub onScrollDelayFire()
    if m.animation = invalid or m.timer = invalid or m.top.repeatCount = 0 then return
    if m.top.maxWidth > 0
        dur = (m.top.width / m.top.maxWidth) * 2
        m.animation.duration = dur
        m.timer.duration = dur
    end if
    m.animation.repeat = true
    m.timer.repeat = true
    m.animation.control = "start"
    m.timer.control = "start"
end sub

sub doScroll()
    if m.animation = invalid or m.timer = invalid then return
    if m.scrollDelayTimer <> invalid then m.scrollDelayTimer.control = "stop"
    if m.top.repeatCount <> invalid and m.top.repeatCount <> 0
        if m.scrollDelayTimer <> invalid
            m.scrollDelayTimer.control = "start"
        else
            onScrollDelayFire()
        end if
    else
        m.animation.repeat = false
        m.animation.control = "stop"
        m.components.translation = [0, 0]
        m.timer.control = "stop"
    end if
end sub

' Will update the components if an interface field has changed.
sub updateComponents()
    ' Only update components if we are actually rendering text
    if m.top.text <> ""
        width = m.top.width
        height = m.top.height
        hAlign = m.top.horizAlign
        vAlign = m.top.vertAlign
        ' Set the layout group properties to reflect the horiz and vert
        ' aligments
        m.components.horizAlignment = hAlign
        m.components.vertAlignment = vAlign

        ' Set component properties
        comps = getAllComponents()
        totalWidth = 0
        for each comp in comps
            comp.visible = true
            if comp.subtype() = "Label"
                comp.width = 0
                comp.height = height
                comp.vertAlign = vAlign
                comp.color = m.top.color
                if m.top.font <> invalid
                    comp.font = m.top.font
                end if
            else
                ' For posters, use emojiSize first if set
                if m.top.emojiSize > 0
                    comp.width = m.top.emojiSize
                    comp.height = m.top.emojiSize
                    ' Then use height if set
                else if height > 0
                    comp.width = height
                    comp.height = height
                else
                    comp.width = 0
                    comp.height = 0
                end if
            end if
            totalWidth = totalWidth + comp.width
        end for
        width = totalWidth

        ' Check if we need to use ellipsis for this label
        ' checkBoundingWidth()
        boundingWidth = m.components.boundingRect().width
        if width = 0 or boundingWidth > width
            width = boundingWidth
        end if
        innerWidth = 0 - width
        m.top.width = width * 1.1
        if m.top.maxWidth = 0
            m.top.maxWidth = m.top.width
        end if
        if m.animation <> invalid
            m.animation.duration = (m.top.width / m.top.maxWidth)
        end if
        if m.timer <> invalid
            m.timer.duration = (m.top.width / m.top.maxWidth)
        end if
        if m.vector <> invalid
            m.vector.keyValue = [[0, 0], [innerWidth, 0]]
        end if

        if m.top.emojiSize > height
            height = m.top.emojiSize
        end if
        ' Set proper translation for horizontal alignment
        xTranslation = 0
        yTranslation = 0
        ' For center, that is in the middle of the node
        if hAlign = "center"
            xTranslation = width / 2
            ' For right, that is the right edge of the node
        else if hAlign = "right"
            xTranslation = width
        end if

        ' Set proper translation for vertical alignment
        ' For center, use the middle of the node
        if vAlign = "center"
            yTranslation = height / 2
            ' For bottom, use bottom edge of node
        else if vAlign = "bottom"
            yTranslation = height
        end if
        m.top.clippingRect = {
            width: m.top.maxWidth,
            height: (m.top.height * 2),
            x: 0,
            y: (0 - (m.top.height / 2))
        }
    end if
end sub

' Updates the entire label components with new text.
sub setText()
    labelText = m.top.text

    resetComponents()
    if labelText <> ""
        if m.emojiRegex <> invalid
            matches = m.emojiRegex.matchAll(labelText)
            for each match in matches
                matchText = match[0]
                loc = labelText.instr(matchText)
                if loc > 0
                    leftText = labelText.left(loc)
                    m.components.appendChild(createLabel(leftText))
                end if

                pointURI = emojiPointName(matchText)
                m.components.appendChild(createPoster(pointURI))

                labelText = labelText.mid(loc + matchText.len())
            end for
        end if

        ' If we have remaining text (or regex unavailable), create a label for it.
        if labelText <> ""
            m.components.appendChild(createLabel(labelText))
        end if
    end if

    ' Update the components.
    updateComponents()
end sub

' Create a new label to display non-emoji text in the label.
function createLabel(withText as string)
    label = createObject("roSGNode", "Label")
    label.text = withText
    label.color = m.top.color
    label.vertAlign = m.top.vertAlign
    label.height = m.top.height
    if m.top.font <> invalid
        label.font = m.top.font
    end if

    return label
end function

' Create a new poster to show an emoji with.
function createPoster(uri as string)
    poster = CreateObject("roSGNode", "Poster")
    poster.uri = uri

    ' Use emoji size first if set
    if m.top.emojiSize > 0
        poster.width = m.top.emojiSize
        poster.height = m.top.emojiSize
        ' Then use height if set
    else if m.top.height > 0
        poster.width = m.top.height
        poster.height = m.top.height
    end if

    return poster
end function

' Returns all components for the current emoji label.
function getAllComponents()
    components = []
    for i = 0 to m.components.getChildCount() - 1
        components.push(m.components.getChild(i))
    end for

    return components
end function

' Removes all child components to reset the layout group.
sub resetComponents()
    while m.components.getChildCount() > 0
        m.components.removeChildIndex(0)
    end while
end sub


sub onDestroy()
    if m.scrollDelayTimer <> invalid
        m.scrollDelayTimer.control = "stop"
        m.scrollDelayTimer.unobserveField("fire")
    end if
    if m.timer <> invalid
        m.timer.control = "stop"
        m.timer.unobserveField("fire")
    end if
    if m.animation <> invalid
        m.animation.control = "stop"
    end if
    m.top.unobserveField("text")
    m.top.unobserveField("color")
    m.top.unobserveField("font")
    m.top.unobserveField("horizAlign")
    m.top.unobserveField("vertAlign")
    m.top.unobserveField("width")
    m.top.unobserveField("repeatCount")
    m.top.unobserveField("emojiSize")
    m.top.unobserveField("maxWidth")
end sub

' function onSizeChange()
'     m.top.clippingRect = {
'         width: m.top.maxWidth
'         height: m.top.height
'         x: 0
'         y: -10
'     }
' end function
