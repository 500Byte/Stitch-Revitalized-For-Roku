' Twitch IRC message parser used by ChatJob.

function MessageParser(message as dynamic) as dynamic
    if message = invalid or message = "" then return invalid
    try
        parsedMessage = {
            tags: {},
            source: {},
            command: {},
            parameters: ""
        }
        rawTagsComponent = invalid
        rawSourceComponent = invalid
        rawCommandComponent = invalid
        rawParametersComponent = invalid

        idx = 0

        if message.mid(idx, 1) = "@"
            endIdx = message.Instr(" ")
            if endIdx < 0 then return invalid
            rawTagsComponent = message.mid(1, endIdx)
            idx = endIdx + 1
        end if

        if message.mid(idx, 1) = ":"
            idx += 1
            endIdx = message.Instr(idx, " ")
            if endIdx < 0 then return invalid
            rawSourceComponent = message.mid(idx, endIdx - idx)
            idx = endIdx + 1
        end if

        endIdx = message.InStr(idx, ":")
        if endIdx = -1
            endIdx = message.len()
        end if

        rawCommandComponent = message.mid(idx, endIdx - idx).trim()

        if endIdx <> message.len()
            idx = endIdx + 1
            rawParametersComponent = message.mid(idx)
        end if

        parsedMessage.command = parseCommand(rawCommandComponent)

        if parsedMessage.command <> invalid
            if rawTagsComponent <> invalid
                parsedMessage.tags = parseTags(rawTagsComponent)
            end if
            parsedMessage.source = parseSource(rawSourceComponent)
            if rawParametersComponent <> invalid
                parsedMessage.parameters = rawParametersComponent.trim()
                if rawParametersComponent.mid(0, 1) = "!"
                    parsedMessage.command = parseParameters(rawParametersComponent, parsedMessage.command)
                end if
            end if
        else
            return invalid
        end if
        return parsedMessage
    catch e
        ? "Error Parsing Chat Message: "; e
        return invalid
    end try
end function

function parseTags(tags as string) as object
    tagsToIgnore = {
        "client-nonce": invalid,
        "flags": invalid
    }
    dictParsedtags = {}
    parsedTags = tags.trim().split(";")
    for each tag in parsedTags
        parsedTag = tag.split("=")
        if parsedTag.count() = 0 then continue for
        key = parsedTag[0]
        if parsedTag.count() > 1 and parsedTag[1] <> invalid and parsedTag[1] <> ""
            tagValue = parsedTag[1]
        else
            tagValue = invalid
        end if

        if key = "badges" or key = "badge-info"
            if tagValue <> invalid
                dictParsedtags[key.replace("-", "_")] = tagValue.split(",")
            else
                dictParsedtags[key.replace("-", "_")] = invalid
            end if
        else if key = "emotes"
            if tagValue <> invalid
                dictEmotes = {}
                emotes = tagValue.split("/")
                for each emote in emotes
                    emoteParts = emote.split(":")
                    if emoteParts.count() < 2 then continue for
                    textPositions = []
                    positions = emoteParts[1].split(",")
                    for each position in positions
                        positionParts = position.split("-")
                        if positionParts.count() >= 2
                            textPositions.push({
                                startPosition: positionParts[0],
                                endPosition: positionParts[1]
                            })
                        end if
                    end for
                    if textPositions.count() > 0
                        dictEmotes[emoteParts[0]] = textPositions
                    end if
                end for
                dictParsedtags[key.replace("-", "_")] = dictEmotes
            else
                dictParsedtags[key.replace("-", "_")] = invalid
            end if
        else if key = "emote-sets"
            if tagValue <> invalid
                dictParsedtags[key.replace("-", "_")] = tagValue.split(",")
            end if
        else if not tagsToIgnore.DoesExist(key)
            if tagValue <> invalid
                dictParsedtags[key.replace("-", "_")] = tagValue
            end if
        end if
    end for
    return dictParsedtags
end function

function parseParameters(rawParameterscomponent as string, command as object) as object
    commandParts = rawParameterscomponent.mid(1).trim()
    paramsidx = commandParts.InStr(" ")
    if paramsidx = -1
        command.botCommand = commandParts.mid(0)
    else
        command.botCommand = commandParts.mid(0, paramsidx)
        command.botCommandParams = commandParts.mid(paramsidx).trim()
    end if
    return command
end function

function parseSource(rawSourceComponent as dynamic) as dynamic
    if rawSourceComponent <> invalid
        sourceParts = rawSourceComponent.split("!")
        if sourceParts.count() = 2
            nick = sourceParts[0]
            host = sourceParts[1]
        else
            nick = invalid
            host = sourceParts[0]
        end if
        return {
            nick: nick,
            host: host.trim()
        }
    else
        return invalid
    end if
end function

function parseCommand(rawCommandComponent as string) as dynamic
    parsedCommand = invalid
    commandParts = rawCommandComponent.split(" ")
    if commandParts.count() = 0 then return invalid
    cmd = commandParts[0]
    if cmd = "JOIN" or cmd = "PART" or cmd = "NOTICE" or cmd = "HOSTTARGET" or cmd = "PRIVMSG" or cmd = "USERNOTICE" or cmd = "USERSTATE" or cmd = "ROOMSTATE"
        if commandParts.count() < 2 then return invalid
        parsedCommand = {
            command: cmd,
            channel: commandParts[1]
        }
    else if cmd = "PING"
        parsedCommand = {
            command: cmd
        }
    else if cmd = "CAP"
        capRequestEnabled = (commandParts.count() > 2 and commandParts[2] = "ACK")
        parsedCommand = {
            command: cmd,
            isCapRequestEnabled: capRequestEnabled
        }
    else if cmd = "GLOBALUSERSTATE"
        parsedCommand = {
            command: cmd
        }
    else if cmd = "RECONNECT"
        ? "The Twitch IRC server is about to terminate the connection for maintenance."
        parsedCommand = {
            command: cmd
        }
    else if cmd = "CLEARMSG" or cmd = "CLEARCHAT"
        parsedCommand = {
            command: cmd,
            channel: commandParts[1]
        }
    else if cmd = "WHISPER"
        ? "WhisperReceived"; formatJSON(commandParts, 256)
    else if cmd = "421"
        ? "Unsupported IRC command: "; formatJSON(commandParts, 256)
        return invalid
    else if cmd = "001"
        parsedCommand = {
            command: cmd,
            channel: commandParts[1]
        }
    else if cmd = "002" or cmd = "003" or cmd = "004" or cmd = "353" or cmd = "366" or cmd = "372" or cmd = "375" or cmd = "376"
        return invalid
    else
        ? "Unexpected Command: "; formatJSON(commandParts, 256)
        return invalid
    end if
    return parsedCommand
end function

' Classifies a parsed IRC message for ChatJob queue dispatch.
' Returns { action: "drop" | "reconnect" | "dispatch" | "wait", age: integer }.
function classifyChatCommand(parsedMsg as dynamic, forceLive as boolean, delaySec as integer, nowSec as integer) as object
    if parsedMsg = invalid or parsedMsg?.command?.command = invalid
        return { action: "drop", age: 0 }
    end if

    cmd = parsedMsg.command.command
    if cmd = "RECONNECT"
        return { action: "reconnect", age: 0 }
    else if cmd <> "PRIVMSG"
        return { action: "drop", age: 0 }
    end if

    if parsedMsg?.tags?.tmi_sent_ts = invalid
        return { action: "drop", age: 0 }
    end if

    commentTs = Val(parsedMsg.tags.tmi_sent_ts.left(10), 10)
    age = nowSec - commentTs
    if forceLive or age > delaySec
        return { action: "dispatch", age: age }
    end if

    return { action: "wait", age: age }
end function
