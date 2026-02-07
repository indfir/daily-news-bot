# Cloud Version of News Fetcher for GitHub Actions
# Uses Environment Variables for Secrets

$topics = @{
    "Astronomy"  = "Astronomy"
    "Science"    = "Science"
    "Technology" = "Technology"
    "Data / AI"  = "Artificial Intelligence Data Science"
    "Movies"     = "Movies"
}

# Read Secrets from Environment Variables (GitHub Secrets)
# Primary Bot
$botToken = $env:TELEGRAM_TOKEN
$chatId = $env:TELEGRAM_CHAT_ID

# Secondary Bot (Optional - for OpenClaw)
$botToken2 = $env:TELEGRAM_TOKEN_2
$chatId2 = $env:TELEGRAM_CHAT_ID_2

# Build List of Targets
$targets = @()
if ($botToken -and $chatId) {
    $targets += @{ Token = $botToken; ChatId = $chatId }
}
if ($botToken2 -and $chatId2) {
    $targets += @{ Token = $botToken2; ChatId = $chatId2 }
}

if ($targets.Count -eq 0) {
    Write-Error "No valid TELEGRAM_TOKEN or TELEGRAM_CHAT_ID found."
    exit 1
}

$currentDate = Get-Date -Format "MMMM dd, yyyy"

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
                if ($segment[0]) {
                    $translatedText += $segment[0]
                }
            }
            return $translatedText
        }
    }
    catch {
        return $Text 
    }
    return $Text
}

function Send-TelegramMessage {
    param (
        [string]$Message
    )
    
    # Send to ALL targets
    foreach ($target in $script:targets) {
        $tToken = $target.Token
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
        }
        catch {
            Write-Host "Failed to send to $tChatId : $($_.Exception.Message)"
        }
    }
}

# Send Header Message
$headerMsg = "<b>Daily News Brief - " + $currentDate + "</b>"
Send-TelegramMessage -Message $headerMsg

# User Agent for Scrapers
$userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36"

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
                # Bing provides good descriptions
                $allItems += [PSCustomObject]@{
                    Title       = $item.title
                    Link        = $item.link
                    Description = $item.description
                    PubDate     = $item.pubDate
                    Source      = "Bing"
                }
            }
        }
    }
    catch {
        Write-Host "Bing Error for $topicName : $($_.Exception.Message)"
    }

    # --- Source 2: Google News ---
    try {
        # Google News RSS (International) - Filter by date query to help
        $googleUrl = "https://news.google.com/rss/search?q=" + $encodedQuery + "+when:30d&hl=en-US&gl=US&ceid=US:en"
        $response = Invoke-WebRequest -Uri $googleUrl -UseBasicParsing -UserAgent $userAgent -ErrorAction Stop
        [xml]$rssXml = $response.Content
        if ($rssXml.rss.channel.item) {
            foreach ($item in $rssXml.rss.channel.item) {
                # Google News descriptions are often just HTML snippets or empty of real summary
                # We use Title as the Description fallback to ensure we have something to translate
                $allItems += [PSCustomObject]@{
                    Title       = $item.title
                    Link        = $item.link
                    Description = $item.title 
                    PubDate     = $item.pubDate
                    Source      = "Google"
                }
            }
        }
    }
    catch {
        Write-Host "Google Error for $topicName : $($_.Exception.Message)"
    }

    # --- Filter & Sort ---
    $cutoffDate = (Get-Date).AddDays(-30)
    $finalItems = $allItems | Where-Object { 
        try { 
            # Parse dates carefully
            $d = [DateTime]::Parse($_.PubDate)
            $d -ge $cutoffDate 
        }
        catch { $true } 
    } | Sort-Object { 
        try { [DateTime]::Parse($_.PubDate) } catch { Get-Date } 
    } -Descending | Select-Object -First 5

    # --- Process & Send ---
    if ($finalItems) {
        $counter = 1
        foreach ($item in $finalItems) {
            $title = $item.Title
            $link = $item.Link
            $rawDesc = $item.Description
            $source = $item.Source

            # Translate Description
            $translatedDesc = Get-GoogleTranslation -Text $rawDesc
            
            # Add to JSON Data
            $allNewsData += [PSCustomObject]@{
                Topic          = $topicName
                Title          = $title
                SummaryEncoded = $translatedDesc # Translated
                Link           = $link
                Source         = $source
                Date           = (Get-Date).ToString("yyyy-MM-dd HH:mm")
            }
            
            # Format
            $safeTitle = $title.Replace("<", "&lt;").Replace(">", "&gt;")
            $safeDesc = $translatedDesc.Replace("<", "&lt;").Replace(">", "&gt;")
            
            # Add Source Tag
            $topicContent += "$counter. <b>$safeTitle</b> <i>($source)</i>`n$safeDesc`n<a href='$link'>Baca Selengkapnya</a>`n`n"
            $counter++
        }
    }
    else {
        $topicContent += "No fresh news found in last 30 days (Bing/Google).`n"
    }

    Send-TelegramMessage -Message $topicContent
}

# Export to JSON for OpenClaw
$jsonPath = "$PSScriptRoot\news.json"
$allNewsData | ConvertTo-Json -Depth 3 | Out-File $jsonPath -Encoding UTF8
Write-Host "Exported news to $jsonPath"
