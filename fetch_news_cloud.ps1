# fetch_news_cloud.ps1
# Daily News Fetcher: Randomized, No Paywall, No Podcast, Limit 3 Items
# Updated: Feature Image (og:image + Wikipedia fallback), ImageSource tracking

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------
# 1. CONFIG & BLOCKLISTS
# ---------------------------
$topics = @{
    "Astronomy"        = "Astronomy"
    "Science"          = "Science"
    "Technology"       = "Technology"
    "Data / AI"        = "Artificial Intelligence Data Science"
    "Movies"           = "Movies"
    "Economy"          = "Economy Business Finance"
    "Trading & Crypto" = "Trading Forex Bitcoin Cryptocurrency Market-Analysis"
}

$domainBlocklist = @(
    "nytimes.com", "wsj.com", "bloomberg.com", "ft.com", "economist.com",
    "hbr.org", "medium.com", "washingtonpost.com", "thetimes.co.uk",
    "barrons.com", "businessinsider.com", "nikkei.com", "kompas.id", "tempo.co",
    "spotify.com", "apple.com", "podcasts.google.com", "podbean.com", "soundcloud.com", "youtube.com"
)

$contentBlocklist = @(
    "Register", "Admission", "Seminar", "Webinar", "Workshop", "Talk",
    "Conference", "Symposium", "Registration", "Tickets", "Eventbrite",
    "Podcast", "Episode", "Ep.", "Listen", "Audio", "Season", "Stream", "Show"
)

$script:userAgent            = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
$currentDate                 = Get-Date -Format "MMMM dd, yyyy"
$script:historyPath          = Join-Path $PSScriptRoot "sent_links_history.json"
$script:historyRetentionDays = 30

# ---------------------------
# 2. TELEGRAM TARGETS
# ---------------------------
$script:targets = @()
if ($env:TELEGRAM_TOKEN -and $env:TELEGRAM_CHAT_ID) {
    $script:targets += @{ Token = $env:TELEGRAM_TOKEN; ChatId = $env:TELEGRAM_CHAT_ID }
}
if ($env:TELEGRAM_TOKEN_2 -and $env:TELEGRAM_CHAT_ID_2) {
    $script:targets += @{ Token = $env:TELEGRAM_TOKEN_2; ChatId = $env:TELEGRAM_CHAT_ID_2 }
}

if ($script:targets.Count -eq 0) {
    Write-Error "No valid TELEGRAM_TOKEN found."
    exit 1
}

# ---------------------------
# 3. HELPER FUNCTIONS
# ---------------------------

function Get-SafeProp {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    return ($null -ne $p ? $p.Value : $null)
}

function Resolve-FinalUrl {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 `
            -UserAgent $script:userAgent -TimeoutSec 10 -ErrorAction Stop
        $final = $r.BaseResponse.ResponseUri.AbsoluteUri
        return ($null -ne $final ? $final : $Url)
    } catch { return $Url }
}

function Get-CanonicalUrlKey {
    param([string]$Url)
    try {
        $u      = [Uri]$Url
        $host   = $u.Host.ToLowerInvariant().Replace("www.", "")
        $path   = $u.AbsolutePath.TrimEnd("/")
        $scheme = $u.Scheme
        return "$($scheme)://$host$path".ToLowerInvariant()
    } catch { return $Url.Trim().ToLowerInvariant() }
}

function Test-ShouldBlock {
    param([string]$Url, [string]$Title)
    foreach ($domain in $domainBlocklist) {
        if ($Url -like "*$domain*") { return $true }
    }
    foreach ($word in $contentBlocklist) {
        if ($Title -match "\b$word\b") { return $true }
    }
    return $false
}

function Get-ArticleImage {
    param([string]$Url)
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing `
            -UserAgent $script:userAgent -TimeoutSec 8 -ErrorAction Stop
        $html = $response.Content

        $r1 = "<meta[^>]+property=[`"']og:image[`"'][^>]+content=[`"']([^`"'>]+)[`"']"
        $r2 = "<meta[^>]+content=[`"']([^`"'>]+)[`"'][^>]+property=[`"']og:image[`"']"
        $r3 = "<meta[^>]+name=[`"']twitter:image[`"'][^>]+content=[`"']([^`"'>]+)[`"']"
        $r4 = "<meta[^>]+content=[`"']([^`"'>]+)[`"'][^>]+name=[`"']twitter:image[`"']"

        if ($html -match $r1) { return $Matches[1] }
        if ($html -match $r2) { return $Matches[1] }
        if ($html -match $r3) { return $Matches[1] }
        if ($html -match $r4) { return $Matches[1] }

    } catch {
        Write-Host "  [og:image] Failed: $Url"
    }
    return $null
}

function Get-WikipediaImage {
    param([string]$Title)
    try {
        $keywords = ($Title -split "\s+" | Select-Object -First 4) -join " "
        $encoded  = [uri]::EscapeDataString($keywords)

        $searchUrl    = "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=$encoded&format=json&srlimit=1"
        $searchResult = Invoke-RestMethod -Uri $searchUrl -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop

        $pageTitle = Get-SafeProp -Obj ($searchResult.query.search | Select-Object -First 1) -Name "title"
        if (-not $pageTitle) { return $null }

        $encodedTitle = [uri]::EscapeDataString($pageTitle)
        $thumbUrl     = "https://en.wikipedia.org/w/api.php?action=query&titles=$encodedTitle&prop=pageimages&format=json&pithumbsize=800"
        $thumbResult  = Invoke-RestMethod -Uri $thumbUrl -UseBasicParsing -TimeoutSec 8 -ErrorAction Stop

        $pages = $thumbResult.query.pages.PSObject.Properties | Select-Object -First 1
        $thumb = Get-SafeProp -Obj $pages.Value -Name "thumbnail"
        if ($thumb) { return (Get-SafeProp -Obj $thumb -Name "source") }

    } catch {
        Write-Host "  [wiki-img] Failed for: $Title"
    }
    return $null
}

# ---------------------------
# 4. TRANSLATION & TELEGRAM
# ---------------------------

function Get-GoogleTranslation {
    param([string]$Text)
    $encoded = [uri]::EscapeDataString($Text)
    $url     = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=id&dt=t&q=$encoded"
    try {
        $response   = Invoke-RestMethod -Uri $url -Method Get
        $translated = ""
        foreach ($seg in $response[0]) { if ($seg[0]) { $translated += $seg[0] } }
        return $translated
    } catch { return $Text }
}

function Send-TelegramMessage {
    param([string]$Message)
    foreach ($target in $script:targets) {
        $body = @{
            chat_id                  = $target.ChatId
            text                     = $Message
            parse_mode               = "HTML"
            disable_web_page_preview = "false"
        }
        try {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$($target.Token)/sendMessage" `
                -Method Post -Body $body | Out-Null
        } catch {
            Write-Host "Failed to send message to $($target.ChatId)"
        }
    }
}

# ---------------------------
# 5. MAIN ENGINE
# ---------------------------

# Load & prune history
if (-not (Test-Path $script:historyPath)) { "[]" | Out-File $script:historyPath -Encoding UTF8 }
$rawHistory  = Get-Content $script:historyPath -Raw -Encoding UTF8
$sentHistory = if ([string]::IsNullOrWhiteSpace($rawHistory)) { @() } else { @(ConvertFrom-Json $rawHistory) }

$cutoff      = (Get-Date).AddDays(-$script:historyRetentionDays)
$sentHistory = @($sentHistory | Where-Object {
    $d = Get-SafeProp -Obj $_ -Name "SentDate"
    if ($d) { [DateTime]$d -gt $cutoff } else { $false }
})

Send-TelegramMessage -Message "<b>📰 Daily News Brief - $currentDate</b>`n<i>Random Selection • 3 Items per Topic</i>"

$allNewsData = @()
$runSeen     = [System.Collections.Generic.HashSet[string]]::new()

foreach ($topicName in $topics.Keys) {
    $encodedQuery = [uri]::EscapeDataString($topics[$topicName])
    $items        = @()

    try {
        $rssUrl = "https://news.google.com/rss/search?q=$encodedQuery+when:14d&hl=en-ID&gl=ID&ceid=ID:en"
        [xml]$xml = (Invoke-WebRequest -Uri $rssUrl -UseBasicParsing -UserAgent $script:userAgent).Content
        if ($null -ne $xml.rss.channel.item) {
            foreach ($node in $xml.rss.channel.item) {
                $cleanTitle = $node.title -replace " - [^-]+$", ""
                $items += [PSCustomObject]@{ Title = $cleanTitle; Link = $node.link }
            }
        }
    } catch {
        Write-Host "Error fetching RSS for: $topicName"
    }

    $randomItems = $items | Sort-Object { Get-Random }
    $sentCount   = 0

    if (($randomItems | Measure-Object).Count -gt 0) {
        $topicEmoji = switch ($topicName) {
            "Astronomy"        { "🔭" }
            "Science"          { "🔬" }
            "Technology"       { "💻" }
            "Data / AI"        { "🤖" }
            "Movies"           { "🎬" }
            "Economy"          { "📈" }
            "Trading & Crypto" { "₿" }
            default            { "📌" }
        }
        Send-TelegramMessage -Message "$topicEmoji <b>$topicName</b>"
        Start-Sleep -Seconds 1
    }

    foreach ($item in $randomItems) {
        if ($sentCount -ge 3) { break }

        $fullLink     = Resolve-FinalUrl -Url $item.Link
        $canonicalKey = Get-CanonicalUrlKey -Url $fullLink

        if (Test-ShouldBlock -Url $fullLink -Title $item.Title) { continue }

        $alreadySent = $false
        foreach ($h in $sentHistory) {
            $hKey = Get-SafeProp -Obj $h -Name "CanonicalKey"
            if ($null -ne $hKey -and $hKey -eq $canonicalKey) {
                $alreadySent = $true; break
            }
        }
        if ($alreadySent -or $runSeen.Contains($canonicalKey)) { continue }

        [void]$runSeen.Add($canonicalKey)

        $translatedTitle = Get-GoogleTranslation -Text $item.Title
        $safeTitle       = $translatedTitle.Replace("<", "&lt;").Replace(">", "&gt;")

        # Step 1: og:image dari artikel
        $imageUrl    = Get-ArticleImage -Url $fullLink
        $imageSource = "og:image"
        Start-Sleep -Milliseconds 300

        # Step 2: fallback Wikipedia
        if (-not $imageUrl) {
            Write-Host "  [img] Trying Wikipedia fallback for: $($item.Title)"
            $imageUrl    = Get-WikipediaImage -Title $item.Title
            $imageSource = "wikipedia"
            Start-Sleep -Milliseconds 200
        }

        if (-not $imageUrl) { $imageSource = "none" }

        $caption = "<b>$($sentCount + 1). $safeTitle</b>`n<a href='$fullLink'>🔗 Baca Selengkapnya</a>"
        Send-TelegramMessage -Message $caption
        Start-Sleep -Seconds 1

        $sentDate     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $sentHistory += [PSCustomObject]@{
            CanonicalKey = $canonicalKey
            SentDate     = $sentDate
        }
        $allNewsData += [PSCustomObject]@{
            Topic       = $topicName
            Title       = $item.Title
            Link        = $fullLink
            ImageUrl    = $imageUrl
            ImageSource = $imageSource
            Date        = $sentDate
        }

        $sentCount++
    }

    if ($sentCount -gt 0) { Start-Sleep -Seconds 2 }
}

# ---------------------------
# 6. PERSISTENCE
# ---------------------------
$sentHistory | ConvertTo-Json -Depth 6 | Out-File $script:historyPath -Encoding UTF8
$allNewsData | ConvertTo-Json -Depth 6 | Out-File (Join-Path $PSScriptRoot "news.json") -Encoding UTF8
Write-Host "Done. Exported $($allNewsData.Count) items to news.json"
