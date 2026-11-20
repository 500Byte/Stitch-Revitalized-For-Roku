sub init()
    m.top.functionName = "main"
end sub

sub fetchNextPage(cursor as dynamic, offset as dynamic)
    if m.top.videoId = invalid or m.top.videoId = "" then return

    if m.commentsQuery = invalid or m.commentsQuery = "" then return
    query = m.commentsQuery

    variables = { "videoID": m.top.videoId }
    if cursor <> invalid and cursor <> ""
        variables["cursor"] = cursor
    else if offset <> invalid
        variables["contentOffsetSeconds"] = Int(offset)
    end if

    data = {
        "query": query,
        "variables": variables
    }

    rsp = TwitchGraphQLRequest(data, 5000)
    if rsp = invalid or rsp.data = invalid or rsp.data.video = invalid or rsp.data.video.comments = invalid
        m.hasNextPage = false
        return
    end if

    if rsp.data.video.owner <> invalid
        owner = rsp.data.video.owner
        if m.top.broadcasterId = invalid or m.top.broadcasterId = ""
            if owner.id <> invalid then m.top.broadcasterId = owner.id
            if owner.login <> invalid then m.top.broadcasterLogin = owner.login
        end if
    end if

    commentsData = rsp.data.video.comments
    edges = commentsData.edges
    if edges <> invalid
        for each edge in edges
            node = edge.node
            if node <> invalid
                text = ""
                emotesList = []
                if node.message <> invalid and node.message.fragments <> invalid
                    for each frag in node.message.fragments
                        if frag.text <> invalid
                            text += frag.text
                            if frag.emote <> invalid and frag.emote.emoteID <> invalid
                                emoteWord = frag.text.trim()
                                if emoteWord <> ""
                                    emotesList.push({ word: emoteWord, id: frag.emote.emoteID })
                                end if
                            end if
                        end if
                    end for
                end if

                badges = []
                if node.message <> invalid and node.message.userBadges <> invalid
                    for each ub in node.message.userBadges
                        if ub.setID <> invalid and ub.version <> invalid
                            badges.push(ub.setID + "/" + ub.version)
                        end if
                    end for
                end if

                displayName = ""
                if node.commenter <> invalid and node.commenter.displayName <> invalid
                    displayName = node.commenter.displayName
                end if

                color = ""
                if node.message <> invalid and node.message.userColor <> invalid
                    color = node.message.userColor
                end if

                commentObj = {
                    tags: {
                        display_name: displayName,
                        color: color,
                        badges: badges,
                        emotes: {},
                        emotesList: emotesList
                    },
                    parameters: text
                }

                m.commentsQueue.push({
                    offsetSeconds: node.contentOffsetSeconds,
                    commentObj: commentObj
                })

                if edge.cursor <> invalid
                    m.nextCursor = edge.cursor
                end if
            end if
        end for
    end if

    if commentsData.pageInfo <> invalid and commentsData.pageInfo.hasNextPage <> invalid
        m.hasNextPage = commentsData.pageInfo.hasNextPage
    else
        m.hasNextPage = false
    end if
end sub

sub main()
    m.commentsQuery = ReadAsciiFile("pkg:/source/graphql/VideoComments_Query.gql")
    m.commentsQueue = []
    m.nextCursor = invalid
    m.hasNextPage = true
    m.lastPosition = -1.0

    m.port = createObject("roMessagePort")
    m.top.observeField("stopRequested", m.port)

    ' Initial fetch if videoId is set
    currentPos = m.top.currentPosition
    fetchNextPage(invalid, currentPos)
    m.lastPosition = currentPos

    while true
        msg = wait(150, m.port)
        if m.top.stopRequested = true
            exit while
        end if

        currPos = m.top.currentPosition

        ' Detect seek (> 4 seconds deviation from expected progression)
        if m.lastPosition >= 0.0 and abs(currPos - m.lastPosition) > 4.0
            ' Player seeked: clear queue and refetch at new position
            m.commentsQueue.clear()
            m.nextCursor = invalid
            m.hasNextPage = true
            fetchNextPage(invalid, currPos)
        end if
        m.lastPosition = currPos

        ' Check if buffer running low (< 10 comments or latest comment offset < currPos + 25s)
        needsMore = false
        if m.commentsQueue.count() < 10 and m.hasNextPage
            needsMore = true
        else if m.commentsQueue.count() > 0
            lastItem = m.commentsQueue[m.commentsQueue.count() - 1]
            if lastItem.offsetSeconds < (currPos + 25.0) and m.hasNextPage
                needsMore = true
            end if
        end if

        if needsMore
            fetchNextPage(m.nextCursor, invalid)
        end if

        ' Dispatch comments ready for current timestamp
        while m.commentsQueue.count() > 0
            first = m.commentsQueue[0]
            if first.offsetSeconds <= currPos
                if m.top.readyForNextComment = true
                    m.top.readyForNextComment = false
                    m.top.nextCommentObj = first.commentObj
                    m.commentsQueue.shift()
                else
                    ' UI still busy rendering previous comment
                    exit while
                end if
            else
                ' Future comment, wait until video playback reaches its timestamp
                exit while
            end if
        end while
    end while
end sub
