' Pure helpers for video quality index lookup during error/buffering recovery.

function findQualityOptionIndex(qualityOptions as dynamic, selectedQuality as dynamic) as integer
    if qualityOptions = invalid or qualityOptions.count() = 0 then return -1

    selectedStr = ""
    if selectedQuality <> invalid then selectedStr = selectedQuality.toStr()
    if selectedStr = "" then return 0

    for i = 0 to qualityOptions.count() - 1
        if qualityOptions[i] = selectedStr
            return i
        end if
    end for

    return -1
end function

function getNextLowerQualityIndex(qualityOptions as dynamic, selectedQuality as dynamic) as integer
    currentIndex = findQualityOptionIndex(qualityOptions, selectedQuality)
    if currentIndex >= 0 and currentIndex < qualityOptions.count() - 1
        return currentIndex + 1
    end if
    return -1
end function

function getAlternativeQualityIndex(qualityOptions as dynamic) as integer
    if qualityOptions = invalid then return -1
    if qualityOptions.count() > 2
        return Int(qualityOptions.count() / 2)
    end if
    return -1
end function

' Computes capped exponential backoff in seconds (1, 2, 4, 8, 16, 16...) for live reconnects.
function computeReconnectDelay(attempts as integer) as integer
    if attempts <= 1 then return 1
    delaySec = 1
    for i = 1 to attempts - 1
        delaySec = delaySec * 2
        if delaySec >= 16 then return 16
    end for
    return delaySec
end function

' Evaluates one 2-second live watchdog tick and decides stall recovery action.
function evaluateWatchdogTick(lastGoodPos as dynamic, currentPos as float, stallSeconds as integer) as object
    if lastGoodPos = invalid or currentPos <> lastGoodPos
        return {
            lastGoodPos: currentPos,
            stallSeconds: 0,
            action: "reset"
        }
    end if

    nextStall = stallSeconds + 2
    action = "none"
    if nextStall >= 24
        action = "force_reconnect"
    else if nextStall >= 16
        action = "reconnect"
    else if nextStall = 4
        action = "check_live"
    end if

    return {
        lastGoodPos: lastGoodPos,
        stallSeconds: nextStall,
        action: action
    }
end function
