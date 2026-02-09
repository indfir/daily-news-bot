# Cloud Version of News Fetcher for GitHub Actions
# Uses Environment Variables for Secrets
# Sources:
# - Bing News RSS
# - GDELT 2.1 DOC API (RSS mode=artlist)

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

# User Agent
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

function Get-GoogleTranslation {
    param([string]$Text, [string]$TargetLanguage = "id")

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
    param([string]$Message)

    foreach ($target in $script:targets) {
        $tToken  = $target.Token
        $tChatId = $target.ChatId

        $url = "https://api.telegram.org/bot$tToken/sendMessage"
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

# GDELT DOC 2.1 -> RSS (artlist)
# DOC API supports query syntax and timespans like "30d", and can return RSS. [web:64]
function Get-GdeltRssUrl {
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$Timespan = "7d",
        [int]$MaxRecords = 50
    )

    # We use: mode=artlist (list of articles), format=rss.
    # Docs: query operators and timespan usage are described in DOC 2.1 API notes. [web:64]
    $q = [uri]::EscapeDataString($Query)
    return "https://api.gdeltproject.org/api/v2/doc/doc?query=$q&mode=artlist&format=rss&timespan=$Timespan&maxrecords=$MaxRecords&sort=hybridrel"
}

function SafeHtml {
    param([string]$Text)
    if (-not $Text) { return "" }
    return $Text.Replace("<","&lt;").Replace(">","&gt;")
}

# Send Header Message
$headerMsg = "<b>Daily News Brief - $currentDate</b>"
Send-TelegramMessage -Message $headerMsg

# JSON export
$allNewsData = @()

foreach ($topicName in $topics.Keys) {
    $rawQuery = $topics[$topicName]
    $encodedQuery = [uri]::EscapeDataString($rawQuery)

    $topicContent = "<b>$topicName</b>`n`n"
    $allItems = @()

    # -----------------------
    # Source 1: Bing News RSS
    # -----------------------
    try {
        $bingUrl = "https://www.bing.com/news/search?q=$encodedQuery&format=rss"
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

    # -----------------------
    # Source 2: GDELT Global RSS
    # -----------------------
    try {
        # Broaden query a bit for global coverage:
        # - Keep raw query, rely on GDELT query engine. [web:64]
        $gdeltUrl = Get-GdeltRssUrl -Query $rawQuery -Timespan "7d" -MaxRecords 50
        $response = Invoke-WebRequest -Uri $gdeltUrl -UseBasicParsing -UserAgent $userAgent -ErrorAction Stop
        [xml]$rssXml = $response.Content

        if ($rssXml.rss.channel.item) {
            foreach ($item in $rssXml.rss.channel.item) {
                # GDELT RSS item typically contains title/link/pubDate/description
                $allItems += [PSCustomObject]@{
                    Title       = [string]$item.title
                    Link        = [string]$item.link
                    Description = ([string]$item.description)
                    PubDate     = [string]$item.pubDate
                    Source      = "GDELT"
                }
            }
        }
    } catch {
        Write-Host "GDELT Error for $topicName : $($_.Exception.Message)"
    }

    # --- Filter & Sort (last 30 days, top 5) ---
    $cutoffDate = (Get-Date).AddDays(-30)

    $finalItems = $allItems | Where-Object {
        try {
            $d = [DateTime]::Parse($_.PubDate)
            $d -ge $cutoffDate
        } catch { $true }
    } | Sort-Object {
        try { [DateTime]::Parse($_.PubDate) } catch { Get-Date }
    } -Descending | Select-Object -First 5

    if ($finalItems) {
        $counter = 1
        foreach ($item in $finalItems) {
            $title   = $item.Title
            $rawDesc = $item.Description
            $source  = $item.Source

            $link = Resolve-FinalUrl -Url $item.Link

            # Translate (description can be HTML-ish; we just translate raw string)
            $translatedDesc = Get-GoogleTranslation -Text $rawDesc

            $allNewsData += [PSCustomObject]@{
                Topic          = $topicName
                Title          = $title
                SummaryEncoded = $translatedDesc
                Link           = $link
                Source         = $source
                Date           = (Get-Date).ToString("yyyy-MM-dd HH:mm")
            }

            $safeTitle = SafeHtml $title
            $safeDesc  = SafeHtml $translatedDesc

            $topicContent += "$counter. <b>$safeTitle</b> <i>($source)</i>`n$safeDesc`n<a href='$link'>Baca Selengkapnya</a>`n`n"
            $counter++
        }
    } else {
        $topicContent += "No fresh news found in last 30 days (Bing/GDELT).`n"
    }

    Send-TelegramMessage -Message $topicContent
}

$jsonPath = Join-Path $PSScriptRoot "news.json"
$allNewsData | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8
Write-Host "Exported news to $jsonPath"
