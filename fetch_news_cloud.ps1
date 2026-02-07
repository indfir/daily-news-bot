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

foreach ($topicName in $topics.Keys) {
    $query = $topics[$topicName]
    $encodedQuery = [uri]::EscapeDataString($query)
    $url = "https://www.bing.com/news/search?q=" + $encodedQuery + "&format=rss"
    
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        [xml]$rssXml = $response.Content
        
        $telegramMessage = "<b>" + $topicName + "</b>`n`n"
        
        $items = $rssXml.rss.channel.item 
        
        # Filter for last 30 days
        $cutoffDate = (Get-Date).AddDays(-30)
        $recentItems = @()
        
        if ($items) {
            if ($items -isnot [array]) { $items = @($items) }
             
            foreach ($item in $items) {
                try {
                    $pDate = [DateTime]::Parse($item.pubDate)
                    if ($pDate -ge $cutoffDate) {
                        $recentItems += $item
                    }
                }
                catch {
                    $recentItems += $item 
                }
            }
        }
        
        # Take top 5
        $finalItems = $recentItems | Select-Object -First 5
             
        if ($finalItems) {
            $counter = 1
            foreach ($item in $finalItems) {
                $title = $item.title
                $link = $item.link
                $description = $item.description

                # Translate Description
                $translatedDesc = Get-GoogleTranslation -Text $description
                
                # Telegram Message Format
                $safeTitle = $title.Replace("<", "&lt;").Replace(">", "&gt;")
                $safeDesc = $translatedDesc.Replace("<", "&lt;").Replace(">", "&gt;")
                
                $telegramMessage += "$counter. <b>$safeTitle</b>`n$safeDesc`n<a href='$link'>Baca Selengkapnya</a>`n`n"
                $counter++
            }
        }
        else {
            $telegramMessage += "No fresh news found in last 30 days.`n"
        }
        
        Send-TelegramMessage -Message $telegramMessage
    }
    catch {
        Write-Host "Error processing $topicName : $($_.Exception.Message)"
        Send-TelegramMessage -Message "<b>$topicName</b>`nFailed to fetch news."
    }
}
