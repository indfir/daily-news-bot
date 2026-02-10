# Cloud Version of News Fetcher for GitHub Actions
# Uses Environment Variables for Secrets
# + Decode Google News RSS links into original publisher links (batchexecute Fbv4je)

$topics = @{
    "Astronomy"  = "Astronomy"
    "Science"    = "Science"
    "Technology" = "Technology"
    "Data / AI"  = "Artificial Intelligence Data Science"
    "Movies"     = "Movies"
}

# Read Secrets from Environment Variables (GitHub Secrets)
$botToken  = $env:TELEGRAM_TOKEN
$chatId    = $env:TELEGRAM_CHAT_ID
$botToken2 = $env:TELEGRAM_TOKEN_2
$chatId2   = $env:TELEGRAM_CHAT_ID_2

# Build List of Targets
$targets = @()
if ($botToken -and $chatId)   { $targets += @{ Token = $botToken;  ChatId = $chatId  } }
if ($botToken2 -and $chatId2) { $targets += @{ Token = $botToken2; ChatId = $chatId2 } }

if ($targets.Count -eq 0) {
    Write-Error "No valid TELEGRAM_TOKEN or TELEGRAM_CHAT_ID found."
    exit 1
}

$currentDate = Get-Date -Format "MMMM dd, yyyy"

# User Agent for Scrapers
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

function Get-GoogleTranslation {
    param(
        [string]$Text,
        [string]$TargetLanguage = "id"
    )

    $encoded = [uri]::EscapeDataString($Text)
    $url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$TargetLanguage&dt=t&q=$encoded"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        if ($response -and $response.Count -gt 0 -and $response[0].Count -gt 0) {
            $translatedText = ""
            foreach ($segment in $response[0]) {
                if ($segment[0]) { $translatedText += $segment[0] }
            }
            return $translatedText
        }
    } catch { return $Text }

    return $Text
}

function Send-TelegramMessage {
    param ([string]$Message)

    foreach ($target in $script:targets) {
        $tToken  = $target.Token
        $tChatId = $target.ChatId

        $url = "https://api.telegram.org/bot" + $tToken + "/sendMessage"
        $body = @{
            chat_id                  = $tChatId
            text                     = $Message
            parse_mode               = "HTML"
            disable_web_page_preview = "true"
        }

        try {
            Invoke-RestMethod -Uri $url -Method Post -Body $body -ErrorAction Stop | Out-Null
            Write-Host "Sent message to ChatID: $tChatId"
        } catch {
            Write-Host "Failed to send to $tChatId : $($_.Exception.Message)"
        }
    }
}

# ---------------------------
# URL helpers
# ---------------------------

function Resolve-FinalUrl {
    param([Parameter(Mandatory)][string]$Url)

    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 -UserAgent $script:userAgent -ErrorAction Stop
        if ($r.BaseResponse.ResponseUri) { return $r.BaseResponse.ResponseUri.AbsoluteUri }
        if ($r.BaseResponse.RequestMessage.RequestUri) { return $r.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }
        return $Url
    } catch {
        try {
            $r = Invoke-WebRequest -Uri $Url -Method Get -MaximumRedirection 10 -UserAgent $script:userAgent -ErrorAction Stop
            if ($r.BaseResponse.ResponseUri) { return $r.BaseResponse.ResponseUri.AbsoluteUri }
            if ($r.BaseResponse.RequestMessage.RequestUri) { return $r.BaseResponse.RequestMessage.RequestUri.AbsoluteUri }
        } catch {}
        return $Url
    }
}

# ---------------------------
# Google News decode (original publisher URL)
# Mechanism follows the gist approach: batchexecute rpc Fbv4je returns garturlres. [page:1]
# ---------------------------

$GoogleDecodeCache = @{}  # per-run cache

function Get-GnArtIdFromGoogleRssUrl {
    param([Parameter(Mandatory)][string]$Url)

    try {
        $u = [Uri]$Url
        $parts = $u.AbsolutePath.Trim("/").Split("/")
        if ($u.Host -ne "news.google.com") { return $null }
        if ($parts.Length -lt 2) { return $null }
        if ($parts[$parts.Length - 2] -ne "articles") { return $null }
        return $parts[$parts.Length - 1]
    } catch {
        return $null
    }
}

function Get-GoogleNewsDecodingParams {
    param([Parameter(Mandatory)][string]$GnArtId)

    # Using /rss/articles/<id> page can expose data-n-a-sg and data-n-a-ts; this is part of the known reverse-engineered flow. [page:1]
    $url = "https://news.google.com/rss/articles/$GnArtId"

    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $script:userAgent -ErrorAction Stop
    $html = $resp.Content

    $sig = $null
    $ts  = $null

    # Extract attributes from HTML
    $m1 = [regex]::Match($html, 'data-n-a-sg="([^"]+)"')
    if ($m1.Success) { $sig = $m1.Groups[1].Value }

    $m2 = [regex]::Match($html, 'data-n-a-ts="([^"]+)"')
    if ($m2.Success) { $ts = $m2.Groups[1].Value }

    if (-not $sig -or -not $ts) {
        throw "Could not extract signature/timestamp for Google News article id."
    }

    return [PSCustomObject]@{
        gn_art_id  = $GnArtId
        signature  = $sig
        timestamp  = [int64]$ts
    }
}

function Decode-GoogleNewsUrlToPublisher {
    param(
        [Parameter(Mandatory)][string]$SourceUrl,
        [int]$MinDelayMs = 350
    )

    if ($GoogleDecodeCache.ContainsKey($SourceUrl)) {
        return $GoogleDecodeCache[$SourceUrl]
    }

    $gnId = Get-GnArtIdFromGoogleRssUrl -Url $SourceUrl
    if (-not $gnId) {
        $GoogleDecodeCache[$SourceUrl] = $SourceUrl
        return $SourceUrl
    }

    # Small delay to reduce rate-limit risk
    Start-Sleep -Milliseconds $MinDelayMs

    try {
        $p = Get-GoogleNewsDecodingParams -GnArtId $gnId

        # Build the batchexecute payload (rpcid Fbv4je) to get garturlres. [page:1]
        $inner = "[`"garturlreq`",[[`"X`",`"X`",[`"X`",`"X`"],null,null,1,1,`"US:en`",null,1,null,null,null,null,null,0,1],`"X`",`"X`",1,[1,1,1],1,1,null,0,0,null,0],`"$($p.gn_art_id)`",$($p.timestamp),`"$($p.signature)`"]"
        $articlesReq = @("Fbv4je", $inner)
        $fReqObj = @(@($articlesReq))   # [[ articlesReq ]]
        $fReqJson = ($fReqObj | ConvertTo-Json -Compress -Depth 10)

        $body = "f.req=" + [uri]::EscapeDataString($fReqJson)

        $headers = @{
            "Content-Type" = "application/x-www-form-urlencoded;charset=UTF-8"
            "Referer"      = "https://news.google.com/"
        }

        $resp = Invoke-WebRequest -Uri "https://news.google.com/_/DotsSplashUi/data/batchexecute" `
                                  -Method Post -Headers $headers -Body $body -UseBasicParsing `
                                  -UserAgent $script:userAgent -ErrorAction Stop

        $text = $resp.Content

        # Response format is newline-delimited; gist parses by splitting "\n\n" then JSON-decoding the second chunk. [page:1]
        $chunks = $text -split "(\r?\n){2}"
        if ($chunks.Count -lt 2) { throw "Unexpected batchexecute response format." }

        $jsonBlock = $chunks[1]
        $arr = $jsonBlock | ConvertFrom-Json

        # Each element has [2] which is a JSON string containing ["garturlres","<url>", ...] [page:1]
        $first = $arr | Select-Object -First 1
        if (-not $first -or -not $first[2]) { throw "No garturlres payload found." }

        $innerArr = $first[2] | ConvertFrom-Json
        $decodedUrl = $innerArr[1]

        if (-not $decodedUrl -or ($decodedUrl -like "*news.google.com*")) {
            throw "Decoded URL empty or still Google News."
        }

        $GoogleDecodeCache[$SourceUrl] = $decodedUrl
        return $decodedUrl
    }
    catch {
        # Fallback: keep original Google News link if decode fails (rate limit / format changes)
        $GoogleDecodeCache[$SourceUrl] = $SourceUrl
        return $SourceUrl
    }
}

# ---------------------------
# Start messaging
# ---------------------------

$headerMsg = "<b>Daily News Brief - " + $currentDate + "</b>"
Send-TelegramMessage -Message $headerMsg

# Array to hold all news for JSON export
$allNewsData = @()

foreach ($topicName in $topics.Keys) {
    $rawQuery = $topics[$topicName]
    $encodedQuery = [uri]::EscapeDataString($rawQuery)

    $topicContent = "<b>" + $topicName + "</b>`n`n"
    $allItems = @()

    # --- Source 1: Bing News ---
    try {
        $bingUrl = "https://www.bing.com/news/search?q=" + $encodedQuery + "&format=rss"
        $response = Invoke-WebRequest -Uri $bingUrl -UseBasicParsing -UserAgent $userAgent -ErrorAction Stop
        [xml]$rssXml = $response.Content

        if ($rssXml.rss.channel.item) {
            foreach ($item in $rssXml.rss.channel.item) {
                $allItems += [PSCustomObject]@{
                    Title       = [string]$item.title
                    Link        = [string]$item.link
                    Description = [string]$item.description
                    PubDate     = [string]$item.pubDate
                    Source      = "Bing"
                }
            }
        }
    } catch {
        Write-Host "Bing Error for $topicName : $($_.Exception.Message)"
    }

    # --- Source 2: Google News ---
    try {
        $googleUrl = "https://news.google.com/rss/search?q=" + $encodedQuery + "+when:30d&hl=en-ID&gl=ID&ceid=ID:en"
        $response = Invoke-WebRequest -Uri $googleUrl -UseBasicParsing -UserAgent $userAgent -ErrorAction Stop
        [xml]$rssXml = $response.Content

        if ($rssXml.rss.channel.item) {
            foreach ($item in $rssXml.rss.channel.item) {
                $allItems += [PSCustomObject]@{
                    Title       = [string]$item.title
                    Link        = [string]$item.link
                    Description = [string]$item.title
                    PubDate     = [string]$item.pubDate
                    Source      = "Google"
                }
            }
        }
    } catch {
        Write-Host "Google Error for $topicName : $($_.Exception.Message)"
    }

    # --- Filter & Sort ---
    $cutoffDate = (Get-Date).AddDays(-30)
    $finalItems = $allItems | Where-Object {
        try {
            $d = [DateTime]::Parse($_.PubDate)
            $d -ge $cutoffDate
        } catch { $true }
    } | Sort-Object {
        try { [DateTime]::Parse($_.PubDate) } catch { Get-Date }
    } -Descending | Select-Object -First 5

    # --- Process & Send ---
    if ($finalItems) {
        $counter = 1
        foreach ($item in $finalItems) {
            $title   = $item.Title
            $rawDesc = $item.Description
            $source  = $item.Source

            # Resolve link
            $link = $item.Link

            if ($source -eq "Google") {
                # Decode Google News URL -> original publisher URL (best effort) [page:1]
                $link = Decode-GoogleNewsUrlToPublisher -SourceUrl $link -MinDelayMs 450
            } else {
                # For Bing, just follow redirects if any
                $link = Resolve-FinalUrl -Url $link
            }

            # Translate Description
            $translatedDesc = Get-GoogleTranslation -Text $rawDesc

            # Add to JSON Data
            $allNewsData += [PSCustomObject]@{
                Topic          = $topicName
                Title          = $title
                SummaryEncoded = $translatedDesc
                Link           = $link
                Source         = $source
                Date           = (Get-Date).ToString("yyyy-MM-dd HH:mm")
            }

            # Format HTML-safe
            $safeTitle = $title.Replace("<", "&lt;").Replace(">", "&gt;")
            $safeDesc  = $translatedDesc.Replace("<", "&lt;").Replace(">", "&gt;")

            $topicContent += "$counter. <b>$safeTitle</b> <i>($source)</i>`n$safeDesc`n<a href='$link'>Baca Selengkapnya</a>`n`n"
            $counter++
        }
    } else {
        $topicContent += "No fresh news found in last 30 days (Bing/Google).`n"
    }

    Send-TelegramMessage -Message $topicContent
}

# Export to JSON for OpenClaw
$jsonPath = Join-Path $PSScriptRoot "news.json"
$allNewsData | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8
Write-Host "Exported news to $jsonPath"
