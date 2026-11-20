sub main()
    if m.top.contentRequested.contentType = "CLIP"
        ' For clips, try to find a working URL using a more direct approach
        clipSlug = m.top.contentRequested.clipSlug
        if clipSlug = invalid or clipSlug = ""
            clipSlug = m.top.contentRequested.contentId
        end if

        content = CreateObject("roSGNode", "TwitchContentNode")
        contentFields = m.top.contentRequested
        if GetInterface(contentFields, "ifSGNodeChildren") <> invalid
            contentFields = contentFields.getFields()
        end if
        contentFields.delete("change")
        contentFields.delete("focusedChild")
        content.setFields(contentFields)

        ' Fetch official signed clip URL via GraphQL first; fall back to probing legacy URLs only if needed
        clipUrl = getClipUrlViaGraphQL(clipSlug)
        if clipUrl <> invalid and clipUrl <> ""
            content.url = clipUrl
            content.StreamUrls = [clipUrl]
            content.streamQualities = [true]
            content.streamContentIds = ["Original"]
        else
            workingUrl = findWorkingClipUrl(clipSlug, m.top.contentRequested.previewImageUrl)
            if workingUrl <> invalid and workingUrl <> ""
                content.url = workingUrl
                content.StreamUrls = [workingUrl]
                if content.streamQualities = invalid
                    content.streamQualities = []
                end if
                content.streamQualities.push(true)
                content.streamContentIds = ["Original"]
            else
                fallbackUrls = generateClipFallbackUrls(clipSlug, m.top.contentRequested.previewImageUrl)
                content.url = fallbackUrls[0]
                content.StreamUrls = fallbackUrls
                content.streamQualities = []
                content.streamContentIds = []
                for i = 0 to fallbackUrls.Count() - 1
                    content.streamQualities.push(true)
                    content.streamContentIds.push("Fallback_" + i.toStr())
                end for
            end if
        end if

        ' Set clip-specific properties for better playback
        content.ignoreStreamErrors = true
        content.switchingStrategy = "no-adaptation"
    else
        rsp = invalid
        if m.top.contentRequested.contentType = "VOD"
            vodQuery = ReadAsciiFile("pkg:/source/graphql/VodPlayerWrapper_Query.gql")
            rsp = TwitchGraphQLRequest({
                query: vodQuery,
                variables: {
                    "videoId": m.top.contentRequested.contentId,
                    "platform": "web_tv",
                    "playerType": "pulsar",
                    "skipPlayToken": false
                }
            })

        end if
        if m.top.contentRequested.contentType = "LIVE"
            streamQuery = ReadAsciiFile("pkg:/source/graphql/StreamPlayer_Query.gql")
            rsp = TwitchGraphQLRequest({
                query: streamQuery,
                variables: {
                    "login": m.top.contentRequested.streamerLogin,
                    "platform": "web_tv",
                    "playerType": "roku",
                    "skipPlayToken": false
                }
            })
            if rsp?.data?.user?.stream?.createdAt <> invalid
                m.streamCreatedAt = rsp.data.user.stream.createdAt
            end if
        end if

        usherUrl = ""
        if m.top.contentRequested.contentType = "VOD"
            if rsp = invalid or rsp.data = invalid or rsp.data.video = invalid or rsp.data.video.playbackAccessToken = invalid
                trackEvent("content_fetch_error", { content_type: "VOD", error_type: "token_fetch_failed", content_id: m.top.contentRequested.contentId, streamer_login: m.top.contentRequested.streamerLogin })
                m.top.response = invalid
                return
            end if
            usherUrl = "https://usher.ttvnw.net/vod/" + rsp.data.video.id + ".m3u8?playlist_include_framerate=true&allow_source=true&player_type=pulsar&player_backend=mediaplayer&reassignments_supported=true&nauth=" + rsp.data.video.playbackAccessToken.value.EncodeUri() + "&nauthsig=" + rsp.data.video.playbackAccessToken.signature
        else if m.top.contentRequested.contentType = "LIVE"
            if rsp = invalid or rsp.data = invalid or rsp.data.user = invalid or rsp.data.user.stream = invalid or rsp.data.user.stream.playbackAccessToken = invalid or rsp.data.user.stream.playbackAccessToken.value = invalid
                trackEvent("content_fetch_error", { content_type: "LIVE", error_type: "token_fetch_failed", content_id: m.top.contentRequested.contentId, streamer_login: m.top.contentRequested.streamerLogin })
                m.top.response = invalid
                return
            end if
            usherUrl = "https://usher.ttvnw.net/api/channel/hls/" + rsp.data.user.login + ".m3u8"
            usherUrl += "?allow_source=true"
            usherUrl += "&fast_bread=true"
            usherUrl += "&playlist_include_framerate=true"
            usherUrl += "&player_backend=mediaplayer"
            usherUrl += "&reassignments_supported=true"
            usherUrl += "&supported_codecs=avc1%2Cmp4a"
            usherUrl += "&transcode_mode=cbr_v1"
            usherUrl += "&p=" + CreateObject("roDeviceInfo").GetRandomUUID().replace("-", "")
            usherUrl += "&token=" + rsp.data.user.stream.playbackAccessToken.value.EncodeUriComponent()
            usherUrl += "&sig=" + rsp.data.user.stream.playbackAccessToken.signature.EncodeUriComponent()
        end if

        ' ? "[GetTwitchContent] Final Usher URL: "; usherUrl

        req = HttpRequest({
            url: usherUrl,
            headers: {
                "Accept": "*/*",
                "Origin": "https://android.tv.twitch.tv",
                "Referer": "https://android.tv.twitch.tv/",
                "User-Agent": "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36",
                "Client-ID": "kimne78kx3ncx6brgo4mv6wki5h1ko"
            },
            method: "GET"
        })

        usher_response = invalid
        maxRetries = 3
        retryCount = 0
        while retryCount < maxRetries
            usher_response = req.send()
            if usher_response <> invalid
                exit while
            end if
            retryCount++
            sleep(1000)
        end while
        if usher_response = invalid
            trackEvent("content_fetch_error", { content_type: m.top.contentRequested.contentType, error_type: "usher_request_failed", content_id: m.top.contentRequested.contentId, streamer_login: m.top.contentRequested.streamerLogin })
            m.top.response = invalid
            return
        end if

        statusCode = usher_response.getResponseCode()
        usher_rsp = usher_response.getString()
        finalPlaylistContent = ""

        ' Check status code to determine response type
        if statusCode = 200
            ' Success - response is M3U8 playlist
            finalPlaylistContent = usher_rsp
        else
            ' Error response - parse JSON for error details
            try
                jsonResponse = ParseJson(usher_rsp)
                if jsonResponse <> invalid and Type(jsonResponse) = "roArray" and jsonResponse.Count() > 0 and jsonResponse[0].type = "error"
                    ' Handle Twitch error response
                    errorMsg = "Unknown error"
                    if jsonResponse[0].error <> invalid
                        errorMsg = jsonResponse[0].error
                    end if

                    ' Create an error content node to pass back
                    content = CreateObject("roSGNode", "TwitchContentNode")
                    content.setFields({
                        contentType: "ERROR",
                        title: "VOD Unavailable",
                        description: errorMsg,
                        errorCode: jsonResponse[0].error_code
                    })

                    m.top.response = content
                    return
                else
                    m.top.response = invalid
                    return
                end if
            catch e
                captureException(e, "GetTwitchContent/parseUsherErrorResponse")
                m.top.response = invalid
                return
            end try
        end if

        ' TRANSCODESTACK="transmux" only means "no server transcodes" (plain TS too),
        ' so it is not a verdict. Enhanced Broadcasting is detected from fMP4 below.
        isTransmux = false
        stream_objects = parseMasterPlaylist(finalPlaylistContent)
        fps = invalid

        ' If no streams found, this is a critical error
        if stream_objects.Count() = 0
            trackEvent("content_fetch_error", { content_type: m.top.contentRequested.contentType, error_type: "no_streams_in_manifest", content_id: m.top.contentRequested.contentId, streamer_login: m.top.contentRequested.streamerLogin })
            m.top.response = invalid
            return
        end if

        stream_bitrates = []
        stream_urls = []
        stream_qualities = []
        stream_content_ids = []
        stream_sticky = []
        stream_formats = []
        streams = []
        metadata = []

        lowestSide = 2147483647
        for each stream_item in stream_objects
            if stream_item["RESOLUTION"] <> invalid and stream_item["URL"] <> invalid
                dims = stream_item["RESOLUTION"].split("x")
                side = Val(dims[0])
                if Val(dims[1]) < side then side = Val(dims[1])
                if side < lowestSide then lowestSide = side
            end if
        end for

        for each stream_item in stream_objects
            if stream_item["RESOLUTION"] <> invalid and stream_item["URL"] <> invalid
                res = stream_item["RESOLUTION"].split("x")[1]
                streamUrl = stream_item["URL"]

                if stream_item["VIDEO"] = "chunked"
                    if stream_item["FRAME-RATE"] <> invalid
                        fps = stream_item["FRAME-RATE"].split(".")[0]
                    end if
                    value = res + "p"
                    if fps <> invalid
                        value = value + fps + " (Source)"
                    end if
                else
                    value = stream_item["VIDEO"]
                end if

                ' Vertical streams (like 720x1280) are checked by their shorter side.
                shortSide = Val(res)
                width = Val(stream_item["RESOLUTION"].split("x")[0])
                if width < shortSide then shortSide = width
                if m.global?.maxVideoHeight <> invalid
                    if shortSide > m.global.maxVideoHeight
                        ' Never filter out every variant: the lowest one always stays.
                        if shortSide > lowestSide then continue for
                    end if
                end if

                if Val(res) >= 720
                    stream_qualities.push(true)
                    stream_quality = true
                else
                    stream_qualities.push(false)
                    stream_quality = false
                end if

                ' Use the stream URL as-is from the playlist
                stream_bitrates.push(Int(Val(stream_item["BANDWIDTH"])) / 1000)
                stream_sticky.push(false)
                stream_content_ids.push(value)
                stream_urls.push(streamUrl)
                stream_formats.push("hls")

                stream = {
                    url: streamUrl,
                    stickyredirects: false,
                    quality: stream_quality,
                    contentid: value,
                    bitrate: Int(Val(stream_item["BANDWIDTH"])) / 1000
                }
                streams.push(stream)

                metadata.push({
                    QualityID: value,
                    Streams: [stream],
                    StreamUrls: [streamUrl],
                    StreamStickyHttpRedirects: [false],
                    StreamQualities: [stream_quality],
                    StreamContentIds: [value],
                    StreamBitrates: [Int(Val(stream_item["BANDWIDTH"])) / 1000]
                })
            end if
        end for

        ' Sort streams by bitrate (highest first) for quality preference
        if streams.Count() > 0
            for i = 0 to streams.Count() - 2
                for j = i + 1 to streams.Count() - 1
                    if streams[i].bitrate < streams[j].bitrate
                        ' Swap all arrays
                        temp = streams[i]
                        streams[i] = streams[j]
                        streams[j] = temp

                        temp_meta = metadata[i]
                        metadata[i] = metadata[j]
                        metadata[j] = temp_meta

                        temp_val = stream_bitrates[i]
                        stream_bitrates[i] = stream_bitrates[j]
                        stream_bitrates[j] = temp_val

                        temp_val = stream_urls[i]
                        stream_urls[i] = stream_urls[j]
                        stream_urls[j] = temp_val

                        temp_val = stream_qualities[i]
                        stream_qualities[i] = stream_qualities[j]
                        stream_qualities[j] = temp_val

                        temp_val = stream_content_ids[i]
                        stream_content_ids[i] = stream_content_ids[j]
                        stream_content_ids[j] = temp_val

                        temp_val = stream_sticky[i]
                        stream_sticky[i] = stream_sticky[j]
                        stream_sticky[j] = temp_val
                    end if
                end for
            end for
        end if

        metadata.unshift({
            QualityID: "Automatic",
            StreamBitrates: stream_bitrates,
            streams: streams,
            StreamUrls: stream_urls,
            StreamQualities: stream_qualities,
            StreamContentIDs: stream_content_ids,
            StreamStickyHttpRedirects: stream_sticky
        })

        content = CreateObject("roSGNode", "TwitchContentNode")
        contentFields = m.top.contentRequested
        if GetInterface(contentFields, "ifSGNodeChildren") <> invalid
            contentFields = contentFields.getFields()
        end if
        ' Strip internal SceneGraph fields that leak through getFields()
        contentFields.delete("change")
        contentFields.delete("focusedChild")
        content.setFields(contentFields)

        ' Set live stream properties
        if m.top.contentRequested.contentType = "LIVE"
            content.live = true
            if m.streamCreatedAt <> invalid and m.streamCreatedAt <> ""
                content.createdAt = m.streamCreatedAt
            end if
        end if

        userQualityPreference = get_user_setting("playback.video.quality", "highest")

        selectedMetadata = invalid
        if userQualityPreference = "highest" and metadata.Count() > 1
            selectedMetadata = metadata[1]
            ' ? "[GetTwitchContent] Using HIGHEST quality setting: "; metadata[1].QualityID
        else if userQualityPreference = "lowest" and metadata.Count() > 0
            ' Select the lowest quality stream
            lowestQualityIndex = metadata.Count() - 1
            selectedMetadata = metadata[lowestQualityIndex]
            ' ? "[GetTwitchContent] Using LOWEST quality setting: "; metadata[lowestQualityIndex].QualityID
        else
            ' Use automatic selection (index 0) - this allows adaptive bitrate
            selectedMetadata = metadata[0]
            ' ? "[GetTwitchContent] Using AUTOMATIC quality setting: "; metadata[0].QualityID
        end if

        ' Set only valid ContentNode fields to avoid type mismatch
        if selectedMetadata <> invalid
            ' Set QualityID
            if selectedMetadata.QualityID <> invalid
                content.QualityID = selectedMetadata.QualityID
            end if

            ' Set URL and StreamUrls - handle both single and multiple streams
            if selectedMetadata.StreamUrls <> invalid and selectedMetadata.StreamUrls.Count() > 0
                content.url = selectedMetadata.StreamUrls[0]
                content.StreamUrls = selectedMetadata.StreamUrls
            else if selectedMetadata.Streams <> invalid and selectedMetadata.Streams.Count() > 0
                ' Fallback to Streams array if StreamUrls not available
                content.url = selectedMetadata.Streams[0].url
                streamUrls = []
                for each stream in selectedMetadata.Streams
                    streamUrls.push(stream.url)
                end for
                content.StreamUrls = streamUrls
            end if

            ' Set qualities - handle field name variations
            if selectedMetadata.StreamQualities <> invalid
                content.StreamQualities = selectedMetadata.StreamQualities
            end if

            ' Set content IDs - handle field name variations
            if selectedMetadata.StreamContentIds <> invalid
                content.StreamContentIds = selectedMetadata.StreamContentIds
            else if selectedMetadata.StreamContentIDs <> invalid
                content.StreamContentIds = selectedMetadata.StreamContentIDs
            end if

            ' Set bitrates
            if selectedMetadata.StreamBitrates <> invalid
                content.StreamBitrates = selectedMetadata.StreamBitrates
            end if

            ' Set sticky redirects - handle field name variations
            if selectedMetadata.StreamStickyHttpRedirects <> invalid
                content.StreamStickyHttpRedirects = selectedMetadata.StreamStickyHttpRedirects
            end if
        end if

        ' Detect fMP4 (Enhanced Broadcasting) from the variant playlist
        if content.url <> invalid and content.url <> ""
            try
                variantReq = HttpRequest({
                    url: content.url,
                    headers: {
                        "Accept": "*/*",
                        "User-Agent": "Mozilla/5.0"
                    },
                    method: "GET",
                    ' One bounded try: this runs before every live start and reconnect,
                    ' and a failed probe just plays the stream directly.
                    timeout: 3000
                })
                variantRsp = variantReq.send()
                if variantRsp <> invalid
                    isTransmux = isFmp4Playlist(variantRsp.getString())
                end if
            catch e
                captureException(e, "GetTwitchContent/detectTransmux")
            end try
        end if

        if isTransmux
            content.isTransmux = true

            proxyUrl = get_user_setting("proxy.url", "").trim()
            if proxyUrl.right(1) = "/" then proxyUrl = proxyUrl.left(proxyUrl.len() - 1)
            demuxServer = m.global.demuxServer
            if proxyUrl = "" and demuxServer <> invalid and demuxServer.ready = true and isBuiltinSplitterEnabled()
                proxyUrl = "http://127.0.0.1:" + demuxServer.port.toStr()
            end if
            ? "[fmp4-demux] isTransmux=true, proxyUrl=" proxyUrl
            if proxyUrl <> ""
                ' Preserve upstream codec/bandwidth/resolution per variant so the
                ' proxy's synthesized demuxed master advertises the real decoder
                ' requirements (H.264 / HEVC / AV1).
                variantHints = {}
                for each item in stream_objects
                    if item["URL"] <> invalid
                        variantHints[item["URL"]] = {
                            codecs: item["CODECS"],
                            bandwidth: item["BANDWIDTH"],
                            resolution: item["RESOLUTION"]
                        }
                    end if
                end for

                if content.url <> invalid and content.url <> ""
                    ? "[fmp4-demux] rewriting url: " content.url
                    content.url = buildProxyM3u8Url(proxyUrl, content.url, variantHints[content.url])
                end if
                if content.StreamUrls <> invalid
                    newStreamUrls = []
                    for each streamUrl in content.StreamUrls
                        newStreamUrls.push(buildProxyM3u8Url(proxyUrl, streamUrl, variantHints[streamUrl]))
                    end for
                    content.StreamUrls = newStreamUrls
                end if
                content.ForwardQueryStringParams = false
                content.isTransmux = false
                content.isProxied = true
                ' Proxy the quality-menu options too.
                for each entry in metadata
                    proxyQualityEntry(entry, proxyUrl, variantHints)
                end for
            end if
        else if m.top.contentRequested.contentType = "LIVE" and isAdFixEnabled() and m.top.contentRequested.skipLiveRoute <> true
            keepAdBreakCount(content, metadata)
        end if

        m.top.metadata = metadata
    end if

    m.top.response = content
end sub

' Plain live lists go through the built-in server when it runs: it keeps the ad break count Twitch drops,
' which otherwise freezes Roku after ads. Pieces still come straight from Twitch.
sub keepAdBreakCount(content as object, metadata as object)
    server = m.global.demuxServer
    if server = invalid or server.ready <> true then return
    ' One id per playback: the server keeps one break count for all quality variants carrying it.
    session = StrI(Rnd(2147483646), 16).Trim() + StrI(Rnd(2147483646), 16).Trim()
    base = "http://127.0.0.1:" + server.port.toStr() + "/live?u="
    suffix = "&k=" + session
    ? "[fmp4-demux] live list through the built-in server"
    if content.url <> invalid and content.url <> "" then content.url = base + content.url.EncodeUriComponent() + suffix
    if content.StreamUrls <> invalid
        urls = []
        for each streamUrl in content.StreamUrls
            urls.push(base + streamUrl.EncodeUriComponent() + suffix)
        end for
        content.StreamUrls = urls
    end if
    content.ForwardQueryStringParams = false
    for each entry in metadata
        if entry.StreamUrls <> invalid
            urls = []
            for each streamUrl in entry.StreamUrls
                urls.push(base + streamUrl.EncodeUriComponent() + suffix)
            end for
            entry.StreamUrls = urls
        end if
        if entry.Streams <> invalid
            streams = []
            for each stream in entry.Streams
                copy = {}
                copy.Append(stream)
                copy.url = base + stream.url.EncodeUriComponent() + suffix
                streams.push(copy)
            end for
            entry.Streams = streams
        end if
        entry.ForwardQueryStringParams = false
    end for
end sub

' Proxies one quality option; shared Streams entries are copied, not changed in place.
sub proxyQualityEntry(entry as object, proxyUrl as string, variantHints as object)
    if entry.StreamUrls <> invalid
        urls = []
        for each streamUrl in entry.StreamUrls
            urls.push(buildProxyM3u8Url(proxyUrl, streamUrl, variantHints[streamUrl]))
        end for
        entry.StreamUrls = urls
    end if
    if entry.Streams <> invalid
        streams = []
        for each stream in entry.Streams
            copy = {}
            copy.Append(stream)
            copy.url = buildProxyM3u8Url(proxyUrl, stream.url, variantHints[stream.url])
            streams.push(copy)
        end for
        entry.Streams = streams
    end if
    entry.ForwardQueryStringParams = false
end sub

function getClipUrlViaGraphQL(clipSlug as string) as dynamic
    ' Try to get clip URL via GraphQL API with proper authentication
    ' ? "[GetTwitchContent] Attempting GraphQL clip lookup for: "; clipSlug

    try
        ' First try to get clip info with playback access token
        rsp = TwitchGraphQLRequest({
            query: "query ClipAccessToken($slug: ID!) { clip(slug: $slug) { id slug title playbackAccessToken(params: {platform: " + chr(34) + "web" + chr(34) + ", playerType: " + chr(34) + "site" + chr(34) + "}) { signature value } videoQualities { frameRate quality sourceURL } } }",
            variables: {
                "slug": clipSlug
            }
        })

        if rsp <> invalid and rsp.data <> invalid and rsp.data.clip <> invalid
            clip = rsp.data.clip

            ' If we have a playback access token, try to use it
            if clip.playbackAccessToken <> invalid
                token = clip.playbackAccessToken.value
                signature = clip.playbackAccessToken.signature

                ' Try to construct authenticated URL
                if clip.videoQualities <> invalid and clip.videoQualities.Count() > 0
                    bestQuality = clip.videoQualities[0]
                    for each quality in clip.videoQualities
                        if quality.quality <> invalid and bestQuality.quality <> invalid
                            if Val(quality.quality) > Val(bestQuality.quality)
                                bestQuality = quality
                            end if
                        end if
                    end for

                    if bestQuality.sourceURL <> invalid
                        authenticatedUrl = bestQuality.sourceURL
                        if token <> invalid and signature <> invalid
                            ' Add authentication parameters
                            if authenticatedUrl.InStr("?") > -1
                                authenticatedUrl += "&token=" + token.EncodeUriComponent() + "&sig=" + signature.EncodeUriComponent()
                            else
                                authenticatedUrl += "?token=" + token.EncodeUriComponent() + "&sig=" + signature.EncodeUriComponent()
                            end if
                        end if

                        ' ? "[GetTwitchContent] GraphQL found authenticated clip URL: "; authenticatedUrl
                        return authenticatedUrl
                    end if
                end if
            end if

            ' Fallback to regular video qualities if no token
            if clip.videoQualities <> invalid and clip.videoQualities.Count() > 0
                bestQuality = clip.videoQualities[0]
                for each quality in clip.videoQualities
                    if quality.quality <> invalid and bestQuality.quality <> invalid
                        if Val(quality.quality) > Val(bestQuality.quality)
                            bestQuality = quality
                        end if
                    end if
                end for

                if bestQuality.sourceURL <> invalid
                    ' ? "[GetTwitchContent] GraphQL found clip URL: "; bestQuality.sourceURL
                    return bestQuality.sourceURL
                end if
            end if
        end if
    catch e
        ' ? "[GetTwitchContent] GraphQL clip lookup failed: "; e.message
        captureException(e, "GetTwitchContent/getClipUrlViaGraphQL")
    end try

    return invalid
end function

function findWorkingClipUrl(clipSlug as string, previewImageUrl as string) as dynamic
    ' Generate test URLs
    testUrls = generateClipFallbackUrls(clipSlug, previewImageUrl)

    ' Test each URL with a simple HTTP request
    for each testUrl in testUrls
        ' ? "[GetTwitchContent] Testing clip URL: "; testUrl
        if isUrlAccessible(testUrl)
            ' ? "[GetTwitchContent] Found working clip URL: "; testUrl
            return testUrl
        end if
        ' Small delay between requests to avoid rate limiting
        sleep(100)
    end for

    ' ? "[GetTwitchContent] No working clip URL found via testing"
    return invalid
end function

function isUrlAccessible(url as string) as boolean
    ' Make a quick HEAD request to test if the URL is accessible
    req = CreateObject("roUrlTransfer")
    if req = invalid then return false
    req.SetCertificatesFile("common:/certs/ca-bundle.crt")
    req.SetUrl(url)

    ' Enhanced headers for clip access
    req.AddHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    req.AddHeader("Accept", "video/mp4,video/webm,video/*,*/*")
    req.AddHeader("Accept-Encoding", "identity")
    req.AddHeader("Accept-Language", "en-US,en;q=0.9")
    req.AddHeader("Cache-Control", "no-cache")
    req.AddHeader("Connection", "keep-alive")
    req.AddHeader("DNT", "1")
    req.AddHeader("Origin", "https://www.twitch.tv")
    req.AddHeader("Pragma", "no-cache")
    req.AddHeader("Referer", "https://www.twitch.tv/")
    req.AddHeader("Sec-Ch-Ua", chr(34) + "Not_A Brand" + chr(34) + ";v=" + chr(34) + "8" + chr(34) + ", " + chr(34) + "Chromium" + chr(34) + ";v=" + chr(34) + "120" + chr(34) + ", " + chr(34) + "Google Chrome" + chr(34) + ";v=" + chr(34) + "120" + chr(34))
    req.AddHeader("Sec-Ch-Ua-Mobile", "?0")
    req.AddHeader("Sec-Ch-Ua-Platform", chr(34) + "Windows" + chr(34))
    req.AddHeader("Sec-Fetch-Dest", "video")
    req.AddHeader("Sec-Fetch-Mode", "cors")
    req.AddHeader("Sec-Fetch-Site", "cross-site")
    req.AddHeader("Client-ID", "kimne78kx3ncx6brgo4mv6wki5h1ko")

    ' Use GET with range instead of HEAD to avoid some server restrictions
    req.AddHeader("Range", "bytes=0-1023")

    ' Set timeout and try the request
    req.SetMessagePort(CreateObject("roMessagePort"))

    if req.AsyncGetToString()
        msg = wait(3000, req.GetMessagePort()) ' 3 second timeout
        if msg <> invalid and type(msg) = "roUrlEvent"
            responseCode = msg.GetResponseCode()
            ' ? "[GetTwitchContent] URL test response: "; responseCode; " for "; url
            ' Accept 200 (OK), 206 (Partial Content), or 302 (Redirect) as success
            return (responseCode = 200 or responseCode = 206 or responseCode = 302)
        end if
    end if

    return false
end function
