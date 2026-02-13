# fetch_news_cloud.ps1
# Daily News Fetcher: Randomized, Anti-Paywall, and De-duplicated

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------
# 1. KONFIGURASI
# ---------------------------
$topics = @{
    "Astronomy"  = "Astronomy"
    "Science"    = "Science"
    "Technology" = "Technology"
    "Data / AI"  = "Artificial Intelligence Data Science"
    "Movies"     = "Movies"
}

# Daftar situs yang sering paywall (ditambah sesuai kebutuhan)
$paywallBlocklist = @(
    "nytimes.com", "wsj.com", "bloomberg.com", "ft.com", "economist.com", 
    "hbr.org", "medium.com", "washingtonpost.com", "thetimes.co.uk",
    "barrons.com", "businessinsider.com", "nikkei.com", "kompas.id", "tempo.co"
)

$script:userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"
$currentDate = Get-Date -Format "MMMM dd, yyyy"

# Penyimpanan riwayat (History)
$script:historyPath = Join-Path $PSScriptRoot "sent_links_history.json"
$script:historyRetentionDays = 30

# ---------------------------
# 2. SECRETS (TELEGRAM)
# ---------------------------
$botToken  = $env:TELEGRAM_TOKEN
$chatId    = $env:TELEGRAM_CHAT_ID
$script:targets = @()
if ($botToken -and $chatId) { $script:targets += @{ Token = $botToken; ChatId = $chatId } }

if ($script:targets.Count -eq 0) {
    Write-Error "Token Telegram tidak ditemukan di Env Vars."
    exit 1
}

# ---------------------------
# 3. FUNGSI HELPER (DEDUP & URL)
# ---------------------------

# Membersihkan URL dari UTM parameter agar deteksi duplikasi akurat
function Get-CanonicalUrlKey {
    param([string]$Url)
    try {
        $u = [Uri]$Url
        $scheme = $u.Scheme.ToLowerInvariant()
        $host   = $u.Host.ToLowerInvariant().Replace("www.", "")
        $path   = $u.AbsolutePath.TrimEnd("/")
        return "${scheme}://${host}${path}"
    } catch { return $Url.Trim().ToLowerInvariant() }
}

# Mengikuti redirect untuk mendapatkan URL asli (Bukan landing page)
function Resolve-FinalUrl {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 -UserAgent $script:userAgent -ErrorAction Stop
        return $r.BaseResponse.ResponseUri.AbsoluteUri
    } catch { return $Url }
}

# Cek apakah website masuk daftar paywall
function Test-IsPaywall {
    param([string]$Url)
    foreach ($domain in $paywallBlocklist) {
        if ($Url -like "*$domain*") { return $true }
    }
    return $false
}

# ---------------------------
# 4. MANAJEMEN HISTORY (ANTI-DUPLIKASI)
# ---------------------------
function Get-SentLinksHistory {
    if (-not (Test-Path $script:historyPath)) { return @() }
    try {
        $raw = Get-Content $script:historyPath -Raw -Encoding UTF8
        return if ($raw) { @(ConvertFrom-Json $raw) } else { @() }
    } catch { return @() }
}

function Save-SentLinksHistory {
    param($History)
    $History | ConvertTo-Json -Depth 6 | Out-File $script:historyPath -Encoding UTF8
}

# ---------------------------
# 5. TRANSLASI & TELEGRAM
# ---------------------------
function Get-GoogleTranslation {
    param([string]$Text)
    $encoded = [uri]::EscapeDataString($Text)
    $url = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=id&dt=t&q=$encoded"
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get
        return ($response[0] | ForEach-Object { $_[0] }) -join ""
    } catch { return $Text }
}

function Send-TelegramMessage {
    param([string]$Message)
    foreach ($target in $script:targets) {
        $body = @{ chat_id = $target.ChatId; text = $Message; parse_mode = "HTML"; disable_web_page_preview = "false" }
        Invoke-RestMethod -Uri "https://api.telegram.org/bot$($target.Token)/sendMessage" -Method Post -Body $body
    }
}

# ---------------------------
# 6. LOGIKA UTAMA (FETCH & RANDOMIZE)
# ---------------------------

$sentHistory = Get-SentLinksHistory
# Pruning: Hapus history yang sudah lebih dari 30 hari
$cutoff = (Get-Date).AddDays(-$script:historyRetentionDays)
$sentHistory = $sentHistory | Where-Object { [DateTime]$_.SentDate -gt $cutoff }

Send-TelegramMessage -Message "<b>Daily News Brief - $currentDate</b>"

foreach ($topicName in $topics.Keys) {
    $encodedQuery = [uri]::EscapeDataString($topics[$topicName])
    $allItems = @()

    # Fetch Google News RSS
    try {
        $url = "https://news.google.com/rss/search?q=$encodedQuery+when:7d&hl=en-ID&gl=ID&ceid=ID:en"
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -UserAgent $script:userAgent
        [xml]$xml = $resp.Content
        foreach ($item in $xml.rss.channel.item) {
            $allItems += [PSCustomObject]@{ Title = $item.title; Link = $item.link; Desc = $item.title }
        }
    } catch { Write-Host "Gagal fetch $topicName" }

    # RANDOMIZE: Mengacak semua berita yang masuk
    $candidateItems = $allItems | Sort-Object { Get-Random }

    $sentCount = 0
    $topicContent = "<b>$topicName</b>`n`n"

    foreach ($item in $candidateItems) {
        if ($sentCount -ge 5) { break }

        # 1. Resolve URL asli
        $fullLink = Resolve-FinalUrl -Url $item.Link
        $canonicalKey = Get-CanonicalUrlKey -Url $fullLink

        # 2. Filter: Paywall
        if (Test-IsPaywall -Url $fullLink) { continue }

        # 3. Filter: Apakah sudah pernah dikirim sebelumnya?
        if ($sentHistory.CanonicalKey -contains $canonicalKey) { continue }

        # Jika lolos filter, proses pengiriman
        $translatedDesc = Get-GoogleTranslation -Text $item.Desc
        $safeTitle = $item.Title.Replace("<", "&lt;").Replace(">", "&gt;")
        
        $topicContent += "$($sentCount + 1). <b>$safeTitle</b>`n$translatedDesc`n<a href='$fullLink'>Baca Selengkapnya</a>`n`n"
        
        # Tambahkan ke history
        $sentHistory += [PSCustomObject]@{
            CanonicalKey = $canonicalKey
            SentDate     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        $sentCount++
    }

    if ($sentCount -gt 0) {
        Send-TelegramMessage -Message $topicContent
        Start-Sleep -Seconds 2 # Hindari spam limit Telegram
    }
}

# Simpan history terbaru ke file
Save-SentLinksHistory -History $sentHistory
