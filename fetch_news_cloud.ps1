# News Fetcher for GitHub Actions
# Sources:
# - Bing News RSS (open language)
# - GDELT DOC API RSS (global, English-only via sourcelang:english) [web:64]
# Feature:
# - Daily dedup: do not broadcast the same news twice across days (persistent history file)

$topics = @{
    "Astronomy"  = "Astronomy"
    "Science"    = "Science"
    "Technology" = "Technology"
    "Data / AI"  = "Artificial Intelligence Data Science"
    "Movies"     = "Movies"
}

# Telegram secrets
$botToken  = $env:TELEGRAM_TOKEN
$chatId    = $env:TELEGRAM_CHAT_ID
$botToken2 = $env:TELEGRAM_TOKEN_2
$chatId2   = $env:TELEGRAM_CHAT_ID_2

$targets = @()
if ($botToken -and $chatId)   { $targets += @{ Token = $botToken;  ChatId = $chatId  } }
if ($botToken2 -and $chatId2) { $targets += @{ Token = $botToken2; ChatId = $chatId2 } }

if ($targets.Count -eq 0) {
    Write-Error "No valid TELEGRAM_TOKEN or TELEGRAM_CHAT_ID found."
    exit 1
}

$currentDate = Get-Date -Format "MMMM dd, yyyy"
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

# ---------------------------
# Persistent history (dedup)
# ---------------------------
$historyPath = Join-Path $PSScriptRoot "sent_links.json"

function Load-History {
    if (Test-Path $script:historyPath) {
        try {
            $raw = Get-Content $script:historyPath -Raw -ErrorAction Stop
            if ($raw.Trim().Length -eq 0) { return @{} }
            $obj = $raw | ConvertFrom-Json
            # Convert PSCustomObject -> hashtable
            $ht = @{}
            foreach ($p in $obj.PSObject.Properties) { $ht[$p.Name] = [bool]$p.Value }
            return $ht
        } catch {
            return @{}
        }
    }
    return @{}
}

function Save-History {
    param([hashtable]$History)
    # keep file deterministic
    $History | ConvertTo-Json -Depth 3 | Out-File $script:historyPath -Encoding UTF8
}

function Get-Fingerprint {
    param(
        [string]$FinalUrl,
        [string]$Title
    )

    # Prefer URL as key
    if ($FinalUrl) {
        return ("url:" + $FinalUrl.Trim().ToLowerInvariant())
    }

    # Fallback: title+host if URL missing
    $t = ($Title ?? "").Trim().ToLowerInvariant()
    return ("title:" + $t)
}

$sentHistory = Load-History

# ---------------------------
# Helpers
# ---------------------------
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

# GDELT DOC API RSS (global, English-only in query) [web:64]
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

# ---------------------------
# Start
# ---------------------------
$headerMsg = "<b>Daily News Brief - $currentDate</b>"
Send-TelegramMessage -Message $headerMsg

$allNewsData = @()

foreach ($topicName in $topics.Keys) {
    $rawQuery = $topics[$topicName]
    $encodedQuery = [uri]::EscapeDataString($rawQuery)

    $topicContent = "<b>$topicName</b>`n`n"
    $allItems = @()

    # Bing RSS
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

    # GDELT RSS (English-only) [web:64]
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

    # Filter last 30 days, sort desc
    $cutoffDate = (Get-Date).AddDays(-30)
    $sortedItems = $allItems | Where-Object {
        try { ([DateTime]::Parse($_.PubDate)) -ge $cutoffDate } catch { $true }
    } | Sort-Object {
        try { [DateTime]::Parse($_.PubDate) } catch { Get-Date }
    } -Descending

    # Build message: take first 5 that are NOT in history
    $counter = 1
    foreach ($item in $sortedItems) {
        if ($counter -gt 5) { break }

        $title   = $item.Title
        $rawDesc = $item.Description
        $source  = $item.Source

        $finalLink = Resolve-FinalUrl -Url $item.Link
        $fp = Get-Fingerprint -FinalUrl $finalLink -Title $title

        if ($sentHistory.ContainsKey($fp)) {
            continue
        }

        # Mark as sent immediately (avoid duplicates within same run)
        $sentHistory[$fp] = $true

        $translatedDesc = Get-GoogleTranslation -Text $rawDesc

        $allNewsData += [PSCustomObject]@{
            Topic          = $topicName
            Title          = $title
            SummaryEncoded = $translatedDesc
            Link           = $finalLink
            Source         = $source
            Date           = (Get-Date).ToString("yyyy-MM-dd HH:mm")
        }

        $safeTitle = SafeHtml $title
        $safeDesc  = SafeHtml $translatedDesc

        $topicContent += "$counter. <b>$safeTitle</b> <i>($source)</i>`n$safeDesc`n<a href='$finalLink'>Baca Selengkapnya</a>`n`n"
        $counter++
    }

    if ($counter -eq 1) {
        $topicContent += "No new (deduped) news found.`n"
    }

    Send-TelegramMessage -Message $topicContent
}

# Save history (must persist across runs via commit/artifact/cache)
Save-History -History $sentHistory
Write-Host "Saved dedup history to $historyPath"

# Export to JSON
$jsonPath = Join-Path $PSScriptRoot "news.json"
$allNewsData | ConvertTo-Json -Depth 5 | Out-File $jsonPath -Encoding UTF8
Write-Host "Exported news to $jsonPath"
