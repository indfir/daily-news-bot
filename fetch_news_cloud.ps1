# fetch_news_cloud.ps1
# Daily News Fetcher for GitHub Actions
# - Read Telegram secrets from env vars
# - Fetch RSS from Bing News and Google News
# - Decode Google News RSS links to publisher links (best-effort)
# - Deduplicate links across runs using sent_links_history.json (commit this file in workflow)
# - Translate summary with translate.googleapis.com

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$topics = @{
    "Astronomy"  = "Astronomy"
    "Science"    = "Science"
    "Technology" = "Technology"
    "Data / AI"  = "Artificial Intelligence Data Science"
    "Movies"     = "Movies"
}

$botToken  = $env:TELEGRAM_TOKEN
$chatId    = $env:TELEGRAM_CHAT_ID
$botToken2 = $env:TELEGRAM_TOKEN_2
$chatId2   = $env:TELEGRAM_CHAT_ID_2

$script:targets = @()
if ($botToken -and $chatId)   { $script:targets += @{ Token = $botToken;  ChatId = $chatId  } }
if ($botToken2 -and $chatId2) { $script:targets += @{ Token = $botToken2; ChatId = $chatId2 } }

if ($script:targets.Count -eq 0) {
    Write-Error "No valid TELEGRAM_TOKEN/TELEGRAM_CHAT_ID found."
    exit 1
}

$currentDate = Get-Date -Format "MMMM dd, yyyy"
$script:userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

function Send-TelegramMessage {
    param([Parameter(Mandatory)][string]$Message)

    foreach ($target in $script:targets) {
        $url = "https://api.telegram.org/bot$($target.Token)/sendMessage"
        $body = @{
            chat_id                  = $target.ChatId
            text                     = $Message
            parse_mode               = "HTML"
            disable_web_page_preview = "true"
        }
        try {
            Invoke-RestMethod -Uri $url -Method Post -Body $body -ErrorAction Stop | Out-Null
            Write-Host "Sent message to ChatID: $($target.ChatId)"
        } catch {
            Write-Host "Failed to send to $($target.ChatId) : $($_.Exception.Message)"
        }
    }
}

function Get-GoogleTranslation {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$TargetLanguage = "id"
    )

    $encoded = [uri]::EscapeDataString($Text)
    $url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$TargetLanguage&dt=t&q=$encoded"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        if ($response -and $response.Count -gt 0 -and $response[0].Count -gt 0) {
            $out = ""
            foreach ($seg in $response[0]) { if ($seg[0]) { $out += $seg[0] } }
            return $out
        }
    } catch { }
    return $Text
}

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
        } catch { }
        return $Url
    }
}

function Get-CanonicalUrlKey {
    param([Parameter(Mandatory)][string]$Url)

    try {
        $u = [Uri]$Url
        $scheme = $u.Scheme.ToLowerInvariant()
        $host   = $u.Host.ToLowerInvariant()
        $path   = $u.AbsolutePath.TrimEnd("/")
        $query  = $u.Query
        if ([string]::IsNullOrWhiteSpace($query)) { $query = "" }

        if ($query) {
            $pairs = $query.TrimStart("?").Split("&") | Where-Object { $_ -ne "" }
            $keep = @()
            foreach ($p in $pairs) {
                $k = ($p.Split("=")[0]).ToLowerInvariant()
                if ($k -in @("utm_source","utm_medium","utm_campaign","utm_term","utm_content","fbclid","gclid")) { continue }
                $keep += $p
            }
            $query = if ($keep.Count -gt 0) { "?" + ($keep -join "&") } else { "" }
        }

        return "${scheme}://${host}${path}${query}"
    } catch {
        return $Url.Trim()
    }
}

# ---------------------------
# Persistent history (null-safe)
# ---------------------------
$script:historyPath = Join-Path $PSScriptRoot "sent_links_history.json"
$script:historyRetentionDays = 30

function Get-SentLinksHistory {
    if (-not (Test-Path $script:historyPath)) { return @() }

    try {
        $raw = Get-Content $script:historyPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }

        $obj = $raw | ConvertFrom-Json

        # IMPORTANT: ConvertFrom-Json can yield $null for "[]" in pwsh 7.x -> force array [web:94]
        if ($null -eq $obj) { return @() }

        return @($obj)
    } catch {
        return @()
    }
}

function Prune-SentLinksHistory {
    param($History)

    if ($null -eq $History) { $History = @() }

    $cutoff = (Get-Date).AddDays(-1 * $script:historyRetentionDays)
    return @($History | Where-Object {
        try { [DateTime]::Parse($_.SentDate) -ge $cutoff } catch { $true }
    })
}

function Save-SentLinksHistory {
    param($History)

    if ($null -eq $History) { $History = @() }
    $History | ConvertTo-Json -Depth 6 | Out-File $script:historyPath -Encoding UTF8
}

function Test-LinkAlreadySent {
    param([Parameter(Mandatory)][string]$CanonicalKey, $History)

    if ($null -eq $History) { return $false }
    return ($History.CanonicalKey -contains $CanonicalKey)
}

function Add-LinkToHistory {
    param(
        [Parameter(Mandatory)][string]$CanonicalKey,
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string]$Topic,
        [Parameter(Mandatory)][string]$Source,
        $History
    )

    if ($null -eq $History) { $History = @() }

    $History += [PSCustomObject]@{
        CanonicalKey = $CanonicalKey
        Link         = $Url
        Title        = $Title
        Topic        = $Topic
        Source       = $Source
        SentDate     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    return $History
}

# ---------------------------
# Google News decode (publisher URL) - best effort
# Mechanism: batchexecute rpc Fbv4je -> garturlres [web:22]
# ---------------------------
$script:GoogleDecodeCache = @{}

function Get-GnArtIdFromGoogleRssUrl {
    param([Parameter(Mandatory)][string]$Url)
    try {
        $u = [Uri]$Url
        $parts = $u.AbsolutePath.Trim("/").Split("/")
        if ($u.Host -ne "news.google.com") { return $null }
        if ($parts.Length -lt 2) { return $null }
        if ($parts[$parts.Length - 2] -ne "articles") { return $null }
        return $parts[$parts.Length - 1]
    } catch { return $null }
}

function Get-GoogleNewsDecodingParams {
    param([Parameter(Mandatory)][string]$GnArtId)

    $url = "https://news.google.com/rss/articles/$GnArtId"
    $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $script:userAgent -ErrorAction Stop
    $html = $resp.Content

    $m1 = [regex]::Match($html, 'data-n-a-sg="([^"]+)"')
    $m2 = [regex]::Match($html, 'data-n-a-ts="([^"]+)"')

    if (-not $m1.Success -or -not $m2.Success) {
        throw "Could not extract signature/timestamp for Google News article id."
    }

    [PSCustomObject]@{
        gn_art_id  = $GnArtId
        signature  = $m1.Groups[1].Value
        timestamp  = [int64]$m2.Groups[1].Value
    }
}

function Decode-GoogleNewsUrlToPublisher {
    param(
        [Parameter(Mandatory)][string]$SourceUrl,
        [int]$MinDelayMs = 350
    )

    if ($script:GoogleDecodeCache.ContainsKey($SourceUrl)) {
        return $script:GoogleDecodeCache[$SourceUrl]
    }

    $gnId = Get-GnArtIdFromGoogleRssUrl -Url $SourceUrl
    if (-not $gnId) {
        $script:GoogleDecodeCache[$SourceUrl] = $SourceUrl
        return $SourceUrl
    }

    Start-Sleep -Milliseconds $MinDelayMs

    try {
        $p = Get-GoogleNewsDecodingParams -GnArtId $gnId

        $inner = "[`"garturlreq`",[[`"X`",`"X`",[`"X`",`"X`"],null,null,1,1,`"US:en`",null,1,null,null,null,null,null,0,1],`"X`",`"X`",1,[1,1,1],1,1,null,0,0,null,0],`"$($p.gn_art_id)`",$($p.timestamp),`"$($p.signature)`"]"
        $articlesReq = @("Fbv4je", $inner)
        $fReqObj = @(@($articlesReq))
        $fReqJson = ($fReqObj | ConvertTo-Json -Compress -Depth 10)
        $body = "f.req=" + [uri]::EscapeDataString($fReqJson)

        $headers = @{
            "Content-Type" = "application/x-www-form-urlencoded;charset=UTF-8"
            "Referer"      = "https://news.google.com/"
        }

        $resp = Invoke-WebRequest -Uri "https://news.google.com/_/DotsSplashUi/data/batchexecute" `
            -Method Post -Headers $headers -Body $body -UseBasicParsing -UserAgent $script:userAgent -ErrorAction Stop

        $text = $resp.Content
        $chunks = $text -split "(\r?\n){2}"
        if ($chunks.Count -lt 2) { throw "Unexpected batchexecute response format." }

        $arr = ($chunks[1] | ConvertFrom-Json)
        $first = $arr | Select-Object -First 1
        if (-not $first -or -not $first[2]) { throw "No garturlres payload found." }

        $innerArr = ($first[2] | ConvertFrom-Json)
        $decodedUrl = $innerArr[1]

        if (-not $decodedUrl -or ($decodedUrl -like "*news.google.com*")) {
            throw "Decoded URL empty or still Google News."
        }

        $script:GoogleDecodeCache[$SourceUrl] = $decodedUrl
        return $decodedUrl
    } catch {
        $script:GoogleDecodeCache[$SourceUrl] = $SourceUrl
        return $SourceUrl
    }
}

# ---------------------------
# Run
# ---------------------------
Send-TelegramMessage -Message "<b>Daily News Brief - $currentDate</b>"

$sentHistory = Get-SentLinksHistory
$sentHistory = Prune-SentLinksHistory $sentHistory

$runSeen = [System.Collections.Generic.HashSet[string]]::new()
$allNewsData = @()

foreach ($topicName in $topics.Keys) {
    $rawQuery = $topics[$topicName]
    $encodedQuery = [uri]::EscapeDataString($rawQuery)

    $topicContent = "<b>$topicName</b>`n`n"
    $allItems = @()

    try {
        $bingUrl = "https://www.bing.com/news/search?q=$encodedQuery&format=rss"
        $response = Invoke-WebRequest -Uri $bingUrl -UseBasicParsing -UserAgent $script:userAgent -ErrorAction Stop
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

    try {
        $googleUrl = "https://news.google.com/rss/search?q=$encodedQuery+when:30d&hl=en-ID&gl=ID&ceid=ID:en"
        $response = Invoke-WebRequest -Uri $googleUrl -UseBasicParsing -UserAgent $script:userAgent -ErrorAction Stop
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

    $cutoffDate = (Get-Date).AddDays(-30)
    $candidateItems = $allItems | Where-Object {
        try { ([DateTime]::Parse($_.PubDate)) -ge $cutoffDate } catch { $true }
    } | Sort-Object {
        try { [DateTime]::Parse($_.PubDate) } catch { Get-Date }
    } -Descending | Select-Object -First 10

    $sentCount = 0
    $counter = 1

    foreach ($item in $candidateItems) {
        if ($sentCount -ge 5) { break }

        $title   = $item.Title
        $rawDesc = $item.Description
        $source  = $item.Source

        $link = $item.Link
        if ($source -eq "Google") { $link = Decode-GoogleNewsUrlToPublisher -SourceUrl $link -MinDelayMs 450 }
        else { $link = Resolve-FinalUrl -Url $link }

        $canonicalKey = Get-CanonicalUrlKey -Url $link

        if ($runSeen.Contains($canonicalKey)) { continue }
        if (Test-LinkAlreadySent -CanonicalKey $canonicalKey -History $sentHistory) { continue }

        [void]$runSeen.Add($canonicalKey)

        $translatedDesc = Get-GoogleTranslation -Text $rawDesc

        $allNewsData += [PSCustomObject]@{
            Topic          = $topicName
            Title          = $title
            SummaryEncoded = $translatedDesc
            Link           = $link
            Source         = $source
            Date           = (Get-Date).ToString("yyyy-MM-dd HH:mm")
        }

        $sentHistory = Add-LinkToHistory -CanonicalKey $canonicalKey -Url $link -Title $title -Topic $topicName -Source $source -History $sentHistory

        $safeTitle = $title.Replace("<", "&lt;").Replace(">", "&gt;")
        $safeDesc  = $translatedDesc.Replace("<", "&lt;").Replace(">", "&gt;")

        $topicContent += "$counter. <b>$safeTitle</b> <i>($source)</i>`n$safeDesc`n<a href='$link'>Baca Selengkapnya</a>`n`n"
        $counter++
        $sentCount++
    }

    if ($sentCount -eq 0) {
        $topicContent += "No fresh/unique news found (last 30 days).`n"
    }

    Send-TelegramMessage -Message $topicContent
}

$sentHistory = Prune-SentLinksHistory $sentHistory
Save-SentLinksHistory $sentHistory

$jsonPath = Join-Path $PSScriptRoot "news.json"
$allNewsData | ConvertTo-Json -Depth 6 | Out-File $jsonPath -Encoding UTF8
Write-Host "Exported news to $jsonPath"
Write-Host "Updated history: $($script:historyPath)"


