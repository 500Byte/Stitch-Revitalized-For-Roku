' Classifies Twitch OAuth validation outcome.
' Only an explicit HTTP 401 with an active access_token means the token is invalid.
' Anonymous sessions and transient network/server errors preserve local settings.
function classifyOauthValidation(activeUser as string, accessToken as dynamic, sendResult as dynamic, parsedRsp as dynamic) as object
    if activeUser = "$default$" or accessToken = invalid or accessToken = ""
        return { status: "anonymous", tokenValid: true }
    end if
    if sendResult = invalid or parsedRsp = invalid
        return { status: "network_error", tokenValid: true }
    end if
    if parsedRsp.status <> invalid and parsedRsp.status = 401
        return { status: "invalid", tokenValid: false }
    end if
    if parsedRsp.expires_in <> invalid
        return { status: "valid", tokenValid: true }
    end if
    return { status: "network_error", tokenValid: true }
end function
