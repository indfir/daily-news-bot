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
        if ($Title -m
