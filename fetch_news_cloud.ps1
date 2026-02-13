# fetch_news_cloud.ps1
# Daily News Fetcher: Fixed Syntax & Strict-Mode Safe

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------
# 1. CONFIG & PAYWALL BLOCKLIST
# ---------------------------
$topics = @{
    "Astronomy"  = "Astronomy"
    "Science"    = "Science"
    "Technology" = "Technology"
    "Data / AI"  = "Artificial Intelligence Data Science"
    "Movies"     = "Movies"
}

$paywallBlocklist = @(
    "nytimes.com", "wsj.com", "bloomberg.com", "ft.com", "economist.com", 
    "hbr.org", "medium.com", "washingtonpost.com", "thetimes.co.uk",
    "barrons.com", "businessinsider.com", "nikkei.com", "kompas.id", "tempo.co"
)

$script:userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
$currentDate = Get-Date -Format "MMMM dd, yyyy"
$script:historyPath = Join-Path $PSScriptRoot "sent_links_history.json"
$script:historyRetentionDays = 30

# ---------------------------
# 2. TELEGRAM TARGETS
# ---------------------------
$script:targets = @()
if ($env:TELEGRAM_TOKEN -and $env:TELEGRAM_CHAT_ID) { 
    $script:targets += @{ Token = $env:TELEGRAM_TOKEN; ChatId = $env:TELEGRAM_CHAT_ID } 
}

if ($script:targets.Count -eq 0) {
    Write-Error "No valid TELEGRAM_TOKEN found."
    exit 1
}

# ---------------------------
# 3. HELPER FUNCTIONS (FIXED SYNTAX)
# ---------------------------

function Get-SafeProp {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    # Menggunakan Ternary Operator PS 7+
    return ($null -ne $p ? $p.Value : $null)
}

function Resolve-FinalUrl {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 -UserAgent $script:userAgent -ErrorAction Stop
        $final = $r.BaseResponse.ResponseUri.AbsoluteUri
        return ($null -ne $final ? $final : $Url)
    } catch { return $Url }
}

function Get-CanonicalUrlKey {
    param([string]$Url)
    try {
        $u = [Uri]$Url
        $host = $u.Host.ToLowerInvariant().Replace("www.", "")
        $path = $u.AbsolutePath.TrimEnd("/")
        return "$($u.Scheme)://$host$path".ToLowerInvariant()
    } catch { return $Url.Trim().ToLowerInvariant() }
}

function Test-IsPaywall {
    param([string]$Url)
    foreach ($domain in $paywallBlocklist) {
        if ($Url -like "*$domain*") { return $true }
    }
    return $false
}

# ---------------------------
# 4. HISTORY MANAGEMENT
# ---------------------------
function Get-SentLinksHistory {
    if (-not (Test-Path $script:historyPath)) { return @() }
    try {
        $raw = Get-Content $script:historyPath -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        $json = ConvertFrom-Json $raw
        return ($null -ne $json ? @($json) : @())
    } catch { return @() }
}

# ---------------------------
# 5. TRANSLATION & TELEGRAM
# ---------------------------
function Get-GoogleTranslation {
    param([string]$Text)
    $encoded = [uri]::EscapeDataString($Text)
    $url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=id&dt=t&q=$encoded"
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get
        $translated = ""
        foreach ($seg in $response[0]) { if ($seg[0]) { $translated += $seg[0] } }
        return $translated
    } catch { return $Text }
}

function Send-TelegramMessage {
    param([string]$Message)
    foreach ($target in $script:targets) {
        $body = @{
            chat_id = $target.ChatId
            text = $Message
            parse_mode = "HTML"
            disable_web_page_preview = "false"
        }
        try {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$($target.Token)/sendMessage" -Method Post -Body $body | Out-Null
        } catch { Write-Host "Failed to send to $($target.ChatId)" }
    }
}

# ---------------------------
# 6. MAIN ENGINE
# ---------------------------

$sentHistory = Get-SentLinksHistory
$cutoff = (Get-Date).AddDays(-$script:historyRetentionDays)
$sentHistory = @($sentHistory | Where-Object { 
    $d = Get-SafeProp -Obj $_ -Name "SentDate"
    if ($d) { [DateTime]$d -gt $cutoff } else { $false }
})

Send-TelegramMessage -Message "<b>Daily News Brief - $currentDate</b>`n(Random Selection, No Paywalls)"

$allNewsData = @()
$runSeen = [System.Collections.Generic.HashSet[string]]::new()

foreach ($topicName in $topics.Keys) {
    $encodedQuery = [uri]::EscapeDataString($topics[$topicName])
    $items = @()

    try {
        $url = "https://news.google.com/rss/search?q=$encodedQuery+when:7d&hl=en-ID&gl=ID&ceid=ID:en"
        [xml]$xml = (Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $script:userAgent).Content
        if ($null -ne $xml.rss.channel.item) {
            foreach ($node in $xml.rss.channel.item) {
                $items += [PSCustomObject]@{ Title = $node.title; Link = $node.link; Desc = $node.title }
            }
        }
    } catch { Write-Host "Error fetching $topicName" }

    # RANDOMIZE
    $randomItems = $items | Sort-Object { Get-Random }

    $sentCount = 0
    $topicContent = "<b>$topicName</b>`n`n"

    foreach ($item in $randomItems) {
        if ($sentCount -ge 5) { break }

        $fullLink = Resolve-FinalUrl -Url $item.Link
        $canonicalKey = Get-CanonicalUrlKey -Url $fullLink

        if (Test-IsPaywall -Url $fullLink) { continue }

        # Cek History
        $alreadySent = $false
        foreach ($h in $sentHistory) {
            if ((Get-SafeProp -Obj $h -Name "CanonicalKey") -eq $canonicalKey) {
                $alreadySent = $true; break
            }
        }
        if ($alreadySent -or $runSeen.Contains($canonicalKey)) { continue }

        [void]$runSeen.Add($canonicalKey)
        $translatedDesc = Get-GoogleTranslation -Text $item.Desc
        $safeTitle = $item.Title.Replace("<", "&lt;").Replace(">", "&gt;")

        $topicContent += "$($sentCount + 1). <b>$safeTitle</b>`n$translatedDesc`n<a href='$fullLink'>Baca Selengkapnya</a>`n`n"

        $sentDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $sentHistory += [PSCustomObject]@{ CanonicalKey = $canonicalKey; SentDate = $sentDate }
        $allNewsData += [PSCustomObject]@{ Topic = $topicName; Title = $item.Title; Link = $fullLink; Date = $sentDate }

        $sentCount++
    }

    if ($sentCount -gt 0) {
        Send-TelegramMessage -Message $topicContent
        Start-Sleep -Seconds 2
    }
}

# ---------------------------
# 7. PERSISTENCE
# ---------------------------
$sentHistory | ConvertTo-Json -Depth 6 | Out-File $script:historyPath -Encoding UTF8
$allNewsData | ConvertTo-Json -Depth 6 | Out-File (Join-Path $PSScriptRoot "news.json") -Encoding UTF8
