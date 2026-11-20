' Pure helpers for parsing Twitch master playlists, building fmp4-demux-proxy URLs,
' and constructing legacy clip fallback URLs.

' Parses an Usher #EXTM3U master playlist into an array of variant metadata AAs.
' Handles CODECS="..." attributes containing commas without truncating them.
function parseMasterPlaylist(playlistContent as string) as object
    streamObjects = []
    if playlistContent = "" then return streamObjects

    lines = playlistContent.Split(chr(10))
    for i = 0 to lines.Count() - 1
        rawLine = lines[i].Trim()
        if rawLine.InStr("#EXT-X-STREAM-INF:") = 0
            streamInfo = rawLine.Split(",")
            streamObj = {}
            for infoIdx = 0 to streamInfo.Count() - 1
                infoParsed = streamInfo[infoIdx].Split("=")
                if infoParsed.Count() >= 2
                    key = infoParsed[0].replace("#EXT-X-STREAM-INF:", "").Trim()
                    value = toString(infoParsed[1]).replace(chr(34), "").Trim()
                    streamObj[key] = value
                end if
            end for

            ' CODECS="..." may contain commas (e.g. "avc1.64001f,mp4a.40.2")
            codecsStart = rawLine.InStr("CODECS=")
            if codecsStart >= 0
                afterEq = rawLine.Mid(codecsStart + 7)
                if Left(afterEq, 1) = chr(34)
                    closeQuote = afterEq.Mid(1).InStr(chr(34))
                    if closeQuote >= 0
                        streamObj["CODECS"] = afterEq.Mid(1, closeQuote)
                    end if
                end if
            end if

            if i + 1 < lines.Count()
                nextLine = lines[i + 1].Trim()
                if nextLine <> "" and Left(nextLine, 1) <> "#"
                    streamObj["URL"] = nextLine
                    streamObjects.push(streamObj)
                end if
            end if
        end if
    end for

    return streamObjects
end function

' Builds the /m3u8 proxy URL carrying optional variant hints (codecs, bw, res).
function buildProxyM3u8Url(proxyBaseUrl as string, streamUrl as string, hints as dynamic) as string
    url = proxyBaseUrl + "/m3u8?u=" + streamUrl.EncodeUriComponent()
    if hints = invalid then return url

    if isValidAndNotEmpty(hints.codecs)
        url = url + "&codecs=" + hints.codecs.EncodeUriComponent()
    end if
    if isValidAndNotEmpty(hints.bandwidth)
        url = url + "&bw=" + hints.bandwidth.EncodeUriComponent()
    end if
    if isValidAndNotEmpty(hints.resolution)
        url = url + "&res=" + hints.resolution.EncodeUriComponent()
    end if

    return url
end function

' Builds candidate clip MP4 URLs when GraphQL clip lookup returns no signed URL.
function generateClipFallbackUrls(clipSlug as string, previewImageUrl = "" as string) as object
    fallbackUrls = []

    uuid = invalid
    if previewImageUrl <> invalid and previewImageUrl <> ""
        if previewImageUrl.InStr("twitch-clips-thumbnails-prod") > -1
            pathParts = previewImageUrl.Split("/")
            if pathParts.Count() >= 6
                uuid = pathParts[5]
            end if
        end if
    end if

    if uuid <> invalid
        fallbackUrls.push("https://production.assets.clips.twitchcdn.net/v2/media/" + clipSlug + "/" + uuid + "/video.mp4")
        fallbackUrls.push("https://clips-media-assets2.twitch.tv/" + clipSlug + "-" + uuid + ".mp4")
        fallbackUrls.push("https://clips-media-assets.twitch.tv/" + clipSlug + "-" + uuid + ".mp4")
        fallbackUrls.push("https://clips-media-assets2.twitch.tv/" + clipSlug + "/" + uuid + ".mp4")
    end if

    fallbackUrls.push("https://clips-media-assets2.twitch.tv/" + clipSlug + ".mp4")
    fallbackUrls.push("https://clips-media-assets.twitch.tv/" + clipSlug + ".mp4")
    fallbackUrls.push("https://production.assets.clips.twitchcdn.net/" + clipSlug + ".mp4")
    fallbackUrls.push("https://clips-media-assets2.twitch.tv/" + clipSlug + "-source.mp4")
    fallbackUrls.push("https://clips-media-assets2.twitch.tv/AT-cm%7C" + clipSlug + ".mp4")

    return fallbackUrls
end function
