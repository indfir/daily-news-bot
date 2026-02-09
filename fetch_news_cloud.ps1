# Cloud Version of News Fetcher for GitHub Actions
# Uses Environment Variables for Secrets
# Sources:
# - Bing News RSS (search)
# - GDELT DOC API RSS (global)
# Requirement:
# - Broadcast ONLY English articles (filter at source for GDELT, and heuristic filter for Bing)

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

function SafeHtml {
    param([string]$Text)
    if (-not $Text) { return "" }
    return $Text.Replace("<","&lt;").Replace(">","&gt;")
}

function LooksLikeEnglish {
    param([string]$Text)

    if (-not $Text) { return $false }

    # Quick heuristic:
    # - If contains lots of non-ASCII letters (common in many non-English scripts), reject.
    # - If has some common English stopwords, accept.
    $t = $Text.Trim()

    $nonLatin = [regex]::Matches($t, "[\u0100-\uFFFF]").Count
    if ($nonLatin -gt 0) { return $false }

    $lower = $t.ToLowerInvariant()
    $hits = 0
    foreach ($w in @(" the "," and "," to "," of "," in "," for "," with "," on "," from "," by "," as ")) {
        if ($lower.Contains($w)) { $hits++ }
    }
    return ($hits -ge 1)
}

# GDELT DOC API RSS (global)
# Use sourcelang to force original publication language. GDELT docs show sourcelang:spanish and explain it filters original language; we apply sourcelang:english. [web:64][web:67]
function Get-GdeltRssUrl {
    param(
        [Parameter(Mandatory)][string]$Query,
        [string]$Timespan = "7d",
        [int]$MaxRecords = 50
    )

    $finalQuery = "($Query) sourcelang:english"
    $q = [uri]::EscapeDataString($finalQuery)

    return "https://api.gdeltproject.org/api/v2/doc/doc?query=$q&mode=artlist&format=rss&timespan=$Timespan&maxrecords=$MaxRecords&sort=hybridrel"
}

# Header
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
    # We bias toward English by adding "language:en" keyword to query (best-effort),
    # then apply a heuristic filter on title/description to reduce non-English leakage.
    # -----------------------
    try {
        $bingQuery = "$rawQuery language:en"
        $bingUrl = "https://www.bing.com/news/search?q=$([uri]::EscapeDataString($bingQuery))&format=rss"
        $response = Invoke-WebRequest -Uri $bingUrl -UseBasicParsing -UserAgent $userAgent -ErrorAction Stop
        [xml]$rssXml = $response.Content

        if ($rssXml.rss.channel.item) {
            foreach ($item in $rssXml.rss.channel.item) {
                $title = [string]$item.title
                $desc  = [string]$item.description

                if (-not (LooksLikeEnglish "$title $desc")) { continue }

                $allItems += [PSCustomObject]@{
                    Title       = $title
                    Link        = [string]$item.link
                    Description = $desc
                    PubDate     = [string]$item.pubDate
                    Source      = "Bing"
                }
            }
        }
    } catch {
        Write-Host "Bing Error for $topicName : $($_.Exception.Message)"
    }

    # -----------------------
    # Source 2: GDELT Global RSS (English-only enforced by sourcelang:english) [web:64][web:67]
    # -----------------------
    try {
        $gdeltUrl = Get-GdeltRssUrl -Query $rawQuery -Timespan "7d" -MaxRecords 50
        $response = Invoke-WebRequest -Uri $gdeltUrl -UseBasicParsing -UserAgent $userAgent -ErrorAction Stop
        [xml]$rssXml = $response.Content

        if ($rssXml.rss.channel.item) {
            foreach ($item in $rssXml.rss.channel.item) {
                $allItems += [PSCustomObject]@{
                    Title       = [string]$item.title
                    Link        = [string]$item.link
                    Description = [string]$item.description
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

            # Translate Description -> Indonesian
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
        $topicContent += "No fresh English news found in last 30 days (Bing/GDELT).`n"
    }

    Send-TelegramMessage -Message $topicContent
}

# Export to JSON
$jsonPath = Join-Path $PSScriptRoot "news.json"
$allNewsData | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8
Write-Host "Exported news to $jsonPath"
