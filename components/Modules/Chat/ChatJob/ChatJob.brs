sub init()
    m.top.functionName = "main"
    m.delay = 29
end sub

sub loginToChat(tcpListen)
    tcpListen.SendStr("CAP REQ :twitch.tv/tags twitch.tv/commands" + Chr(13) + Chr(10))
    user_auth_token = get_user_setting("access_token")
    m.loggedInUsername = get_user_setting("login")
    if m.loggedInUsername <> invalid and m.loggedInUsername <> "" and user_auth_token <> invalid and user_auth_token <> ""
        tcpListen.SendStr("PASS oauth:" + user_auth_token + Chr(13) + Chr(10))
        tcpListen.SendStr("USER " + m.loggedInUsername + " 8 * :" + m.loggedInUsername + Chr(13) + Chr(10))
        tcpListen.SendStr("NICK " + m.loggedInUsername + Chr(13) + Chr(10))
    else
        tcpListen.SendStr("PASS SCHMOOPIIE" + Chr(13) + Chr(10))
        tcpListen.SendStr("NICK justinfan32006" + Chr(13) + Chr(10))
    end if
end sub

function reconnectToChat(tcpListen, addr) as object
    tcpListen.Close()
    sleep(2000)
    tcpListen = createObject("roStreamSocket")
    tcpListen.SetSendToAddress(addr)
    tcpListen.notifyReadable(true)
    tcpListen.Connect()
    loginToChat(tcpListen)
    tcpListen.SendStr("JOIN #" + m.top.channel + Chr(13) + Chr(10))
    return tcpListen
end function

sub main()
    if m.top.channel <> ""
        receivedNewMessage = false
        tcpListen = createObject("roStreamSocket")
        addr = createObject("roSocketAddress")
        addr.SetAddress("irc.chat.twitch.tv:6667")
        tcpListen.SetSendToAddress(addr)
        tcpListen.notifyReadable(true)
        tcpListen.Connect()
        loginToChat(tcpListen)
        tcpListen.eOK()
        tcpListen.IsReadable()
        tcpListen.IsWritable()
        tcpListen.IsException()
        tcpListen.eSuccess()
        tcpListen.SendStr("JOIN #" + m.top.channel + Chr(13) + Chr(10))
        queue = createObject("roArray", 300, true)
        ' Teardown signal: a port message is read without a rendezvous, unlike a m.top read
        m.port = createObject("roMessagePort")
        m.top.observeField("stopRequested", m.port)
        sendWaitingMessage = true
        readBuf = ""
        ' A stop sent before the observer existed never reaches the port
        stopped = m.top.stopRequested
        while not stopped and m.port.getMessage() = invalid
            gotData = false
            dispatched = false
            avail = tcpListen.GetCountRcvBuf()
            if avail > 0
                gotData = true
                if avail > 4096 then avail = 4096
                chunk = tcpListen.ReceiveStr(avail)
                if chunk <> invalid and chunk <> ""
                    readBuf = readBuf + chunk
                    if len(readBuf) > 65536
                        readBuf = ""
                    end if
                end if
            else if tcpListen.IsReadable()
                tcpListen = reconnectToChat(tcpListen, addr)
                readBuf = ""
            end if

            while true
                nlPos = readBuf.InStr(Chr(10))
                if nlPos < 0 then exit while
                line = readBuf.Left(nlPos + 1)
                readBuf = readBuf.Mid(nlPos + 1)
                if line <> ""
                    if Left(line, 4) = "PING"
                        tcpListen.SendStr("PONG :tmi.twitch.tv" + Chr(13) + Chr(10))
                    else
                        queue.unshift(line)
                        receivedNewMessage = true
                        while queue.count() > 100
                            queue.pop()
                        end while
                    end if
                end if
            end while
            if stopped then exit while
            if m.top.readyForNextComment and queue.count() > 0
                ' Check if delay is complete using irc timestamp
                oldestComment = queue.peek()
                _parsedMessage = MessageParser(oldestComment)
                nowSec = CreateObject("roDateTime").AsSeconds()
                decision = classifyChatCommand(_parsedMessage, m.top.forceLive = true, m.delay, nowSec)
                if decision.action = "reconnect"
                    ? getLogTimestamp(); " [ChatJob] Server requested reconnect, reconnecting..."
                    tcpListen = reconnectToChat(tcpListen, addr)
                    queue.clear()
                    readBuf = ""
                    m.top.readyForNextComment = true
                    continue while
                else if decision.action = "drop"
                    queue.pop()
                    continue while
                else if decision.action = "dispatch"
                    sendWaitingMessage = false
                    queue.pop()
                    m.top.nextCommentObj = _parsedMessage
                    dispatched = true
                end if

                if sendWaitingMessage = true
                    if decision.age >= m.delay
                        sendWaitingMessage = false
                    else if queue.count() > 0 and queue[0] <> invalid and receivedNewMessage
                        latestParsed = MessageParser(queue[0])
                        receivedNewMessage = false
                        if latestParsed?.command?.command = "PRIVMSG"
                            m.top.nextCommentObj = latestParsed
                            dispatched = true
                        end if
                    end if
                end if
            end if
            if not gotData and not dispatched
                sleep(25)
            end if
        end while
        m.top.unobserveField("stopRequested")
        tcpListen.Close()
    end if
end sub
