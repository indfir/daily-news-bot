# fetch_news_cloud.ps1
# Daily News Fetcher: Randomized, No Paywall, No Podcast, Limit 5 Items
# Features:
# - Custom RSS Feeds per topic (Universal RSS/Atom Parser)
# - Feed Randomizer (picks random feeds per run for performance)
# - Domain + content blocklist
# - Dedup per-run + lintas-run (history 30 hari)
# - Translate title to Indonesian (Google translate gtx)
# - Feature image: og:image/twitter:image + Wikipedia fallback
# - Date output in WIB (Asia/Jakarta / SE Asia Standard Time)
# - Added Source Domain in caption
# - Disabled Telegram Web Page Preview for clean look
# - Fixed XML parsing issue for CDATA titles

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------
# 1. CONFIG & BLOCKLISTS
# ---------------------------

# Maksimal feed yang dicek per topik dalam 1x run agar tidak timeout
$maxFeedsPerTopic = 5

$topics = @{
    "Economy" = @(
        "https://www.cnbc.com/id/100003114/device/rss/rss.html", "https://www.bloomberg.com/feed/podcast/law.xml", "https://www.ft.com/?format=rss",
        "https://www.reutersagency.com/feed/", "https://feeds.a.dj.com/rss/RSSMarketsMain.xml", "https://www.forbes.com/business/feed/",
        "https://fortune.com/feed", "https://www.businessinsider.com/rss", "https://feeds.harvardbusiness.org/harvardbusiness/ideacast",
        "https://www.economist.com/the-world-this-week/rss.xml", "https://economictimes.indiatimes.com/rssfeedsdefault.cms",
        "https://www.business-standard.com/rss/home_page_top_stories.rss", "https://www.financialexpress.com/feed/",
        "https://www.moneycontrol.com/rss/latestnews.xml", "https://feeds.feedburner.com/ndtvnews-top-stories",
        "https://www.livemint.com/rss/homepage", "https://www.businesslive.co.za/rss/", "https://www.afr.com/rss",
        "money.kompas.com/feed", "https://finance.detik.com/feed", "https://www.kontan.co.id/rss",
        "https://www.bisnis.com/rss", "https://bisnis.tempo.co/rss", "https://www.cnbcindonesia.com/rss"
    )
    "Trading & Crypto" = @(
        "https://www.coindesk.com/arc/outboundfeeds/rss/", "https://cointelegraph.com/rss", "https://decrypt.co/feed",
        "https://www.theblockcrypto.com/rss", "https://www.ig.com/en/news-and-trade-ideas", "https://bitcoinmagazine.com/.rss/feed/index.xml",
        "https://cryptoslate.com/feed/", "https://www.coinbureau.com/feed/"
    )
    "Science" = @(
        "https://www.nature.com/nature.rss", "https://www.science.org/action/showFeed?type=ac_topnews", "https://www.scientificamerican.com/science/rss/",
        "https://rss.sciam.com/sciam/60secsciencepodcast", "http://rss.sciam.com/ScientificAmerican-Global", "https://www.newscientist.com/subject/space/feed/",
        "https://www.newscientist.com/feed/home/", "https://phys.org/rss-feed/", "https://www.sciencedaily.com/rss/all.xml",
        "https://www.sciencedaily.com/rss/top.xml", "https://www.sciencenews.org/feed", "https://arstechnica.com/science/feed/",
        "https://www.livescience.com/feeds/rss/home.xml", "https://gizmodo.com/tag/science/rss", "https://theconversation.com/science/articles?format=rss",
        "https://www.pnas.org/action/showFeed?jc=pnas", "https://journals.plos.org/plosone/feed", "https://www.cell.com/cell/current.rss",
        "https://www.nejm.org/rss/current", "https://feeds.npr.org/510308/podcast.xml", "https://feeds.npr.org/510307/podcast.xml",
        "http://feeds.wnyc.org/radiolab", "https://sciencebasedmedicine.org/feed/", "https://flowingdata.com/feed", "https://www.kdnuggets.com/feed",
        "https://towardsdatascience.com/feed", "https://machinelearningmastery.com/feed/", "https://sains.kompas.com/feed",
        "https://www.detik.com/sains/feed", "https://riset.kompas.com/feed"
    )
    "Technology" = @(
        "https://techcrunch.com/feed/", "https://www.theverge.com/rss/index.xml", "https://www.wired.com/feed/rss",
        "https://www.wired.com/feed/category/science/latest/rss", "https://arstechnica.com/feed/", "https://www.engadget.com/rss.xml",
        "https://www.cnet.com/rss/news/", "https://gizmodo.com/rss", "https://mashable.com/feeds/rss/all", "https://thenextweb.com/feed/",
        "https://readwrite.com/feed/", "https://news.ycombinator.com/rss", "http://rss.slashdot.org/Slashdot/slashdotMain",
        "https://www.infoq.com/feed", "https://dev.to/feed", "https://stackoverflow.com/feeds", "https://github.blog/feed/",
        "https://www.technologyreview.com/topic/artificial-intelligence/feed/", "https://artificialintelligence-news.com/feed/",
        "https://venturebeat.com/category/ai/feed/", "https://www.oreilly.com/ai/rss.xml", "https://openai.com/blog/rss/",
        "https://deepmind.com/blog/rss.xml", "https://atp.fm/rss", "https://www.relay.fm/analogue/feed", "https://www.relay.fm/clockwise/feed",
        "https://www.youtube.com/feeds/videos.xml?user=LinusTechTips", "https://www.youtube.com/feeds/videos.xml?user=marquesbrownlee",
        "https://www.youtube.com/feeds/videos.xml?user=unboxtherapy", "http://stratechery.com/feed/", "https://www.blog.google/rss/",
        "https://tim.blog/feed/", "https://tekno.kompas.com/feed", "https://inet.detik.com/feed", "https://www.techinasia.com/id/feed",
        "https://daily.social/feed/"
    )
    "Astronomy" = @(
        "https://www.nasa.gov/rss/dyn/breaking_news.rss",
        "https://www.esa.int/var/esa/storage/plain/esa_multimedia/ESS/ESA_RSS_Feed.xml", "https://www.jaxa.jp/pr/press/press_xml_e.xml",
        "https://www.space.com/feeds/rss/all.xml", "https://www.space.com/feeds/all", "https://spacenews.com/feed",
        "https://www.skyandtelescope.com/astronomy-news/feed/", "https://www.skyandtelescope.com/feed/", "https://www.astronomy.com/feed/",
        "https://www.universetoday.com/feed/", "https://www.theguardian.com/science/space/rss", "https://www.newscientist.com/subject/space/feed/",
        "https://reddit.com/r/space/.rss?format=xml", "https://www.reddit.com/r/astronomy/.rss", "https://www.youtube.com/feeds/videos.xml?user=spacexchannel",
        "https://www.blueorigin.com/rss/", "https://www.planetary.org/feed/articles.xml"
    )
    "Movies" = @(
        "https://variety.com/feed/", "https://www.hollywoodreporter.com/feed/", "https://www.indiewire.com/feed",
        "https://deadline.com/feed/", "https://screenrant.com/feed/", "https://collider.com/feed/", "https://www.empireonline.com/movies/feed/rss/",
        "https://editorial.rottentomatoes.com/feed/", "https://feeds2.feedburner.com/slashfilm", "https://www.aintitcool.com/node/feed/",
        "https://www.comingsoon.net/feed", "https://filmschoolrejects.com/feed/", "https://www.firstshowing.net/feed/",
        "https://film.avclub.com/rss", "https://www.bleedingcool.com/movies/feed/", "https://ew.com/feed/", "https://www.vulture.com/feed.xml",
        "https://www.tmz.com/rss.xml", "https://people.com/rss/index.xml", "https://www.streamingmedia.com/rss/feed.asp",
        "https://www.cordcuttersnews.com/rss/", "https://decider.com/feed/", "https://www.layar-21.com/feed/", "https://www.filmapik.com/feed/",
        "https://www.duniaku.net/feed"
    )
    "Data / AI" = @(
        "https://www.technologyreview.com/topic/artificial-intelligence/feed/", "https://artificialintelligence-news.com/feed/",
        "https://venturebeat.com/category/ai/feed/", "https://www.oreilly.com/ai/rss.xml", "https://openai.com/blog/rss/",
        "https://deepmind.com/blog/rss.xml", "https://www.anthropic.com/rss", "https://www.kdnuggets.com/feed", "https://towardsdatascience.com/feed",
        "https://machinelearningmastery.com/feed/", "https://www.datasciencecentral.com/profiles/blog/feed", "https://www.analyticsvidhya.com/blog/feed/",
        "https://www.datacamp.com/community/rss", "https://www.oreilly.com/data/rss.xml", "https://arxiv.org/rss/cs.AI",
        "https://arxiv.org/rss/cs.LG", "https://arxiv.org/rss/cs.CV", "https://paperswithcode.com/latest",
        "https://ml-compiled.readthedocs.io/en/latest/rss.xml", "https://www.forbes.com/ai/feed/", "https://www.zdnet.com/topic/artificial-intelligence/rss.xml",
        "https://www.infoworld.com/rss.xml"
    )
    "General News" = @(
        "http://feeds.bbci.co.uk/news/rss.xml", "http://rss.cnn.com/rss/edition.rss", "https://www.reutersagency.com/feed/",
        "https://apnews.com/rss", "https://www.theguardian.com/world/rss", "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml",
        "https://feeds.washingtonpost.com/rss/national", "https://www.npr.org/rss/rss.php?id=1001", "https://www.nbcnews.com/rss",
        "https://abcnews.go.com/abcnews/topstories", "https://timesofindia.indiatimes.com/rssfeedstopstories.cms", "https://www.thehindu.com/feeder/default.rss",
        "https://www.straitstimes.com/rss", "https://www.scmp.com/rss/91/feed", "https://www.japantimes.co.jp/feed/topstories/",
        "https://english.kyodonews.net/rss/all.xml", "https://rss.dw.com/rdf/rss-en-all", "http://newsfeed.zeit.de/index",
        "https://rss.focus.de/fol/XML/rss_folnews.xml", "http://www.tagesschau.de/xml/rss2", "https://feeds.thelocal.com/rss",
        "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada", "https://www.lemonde.fr/rss/une.xml", "https://www.france24.com/en/rss",
        "https://www.kompas.id/rss", "https://www.detik.com/feed", "https://www.tempo.co/rss", "https://www.antaranews.com/rss",
        "https://www.republika.co.id/rss/", "https://www.tribunnews.com/rss", "https://www.merdeka.com/feed/", "https://www.suara.com/rss"
    )
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
    throw "No valid TELEGRAM_TOKEN found."
}

# ---------------------------
# 3. HELPERS
# ---------------------------

function Get-WIBTime {
    try {
        $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("SE Asia Standard Time")
    } catch {
        $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById("Asia/Jakarta")
    }
    return [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $tz)
}

function Get-SafeProp {
    param($Obj, [string]$Name)
    if ($null -eq $Obj) { return $null }
    $p = $Obj.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Resolve-FinalUrl {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -Method Head -MaximumRedirection 10 -UserAgent $script:userAgent -TimeoutSec 12 -ErrorAction Stop
        $final = $r.BaseResponse.ResponseUri.AbsoluteUri
        if ($final) { return $final }
        return $Url
    } catch {
        return $Url
    }
}

function Get-CanonicalUrlKey {
    param([string]$Url)
    try {
        $u      = [Uri]$Url
        $host   = $u.Host.ToLowerInvariant().Replace("www.", "")
        $path   = $u.AbsolutePath.TrimEnd("/")
        $scheme = $u.Scheme.ToLowerInvariant()
        return "${scheme}://${host}${path}".ToLowerInvariant()
    } catch {
        return ($Url.Trim().ToLowerInvariant())
    }
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
        $response = Invoke-WebRequest -Uri $Url -UserAgent $script:userAgent -TimeoutSec 10 -ErrorAction Stop
        $html = $response.Content

        $r1 = "<meta[^>]+property=[`"']og:image[`"'][^>]+content=[`"']([^`"'>]+)[`"']"
        $r2 = "<meta[^>]+content=[`"']([^`"'>]+)[`"'][^>]+property=[`"']og:image[`"']"
        $r3 = "<meta[^>]+name=[`"']twitter:image[`"'][^>]+content=[`"']([^`"'>]+)[`"']"
        $r4 = "<meta[^>]+content=[`"']([^`"'>]+)[`"'][^>]+name=[`"']twitter:image[`"']"

        if ($html -match $r1) { return $Matches[1] }
        if ($html -match $r2) { return $Matches[1] }
        if ($html -match $r3) { return $Matches[1] }
        if ($html -match $r4) { return $Matches[1] }
    } catch { }
    return $null
}

function Get-WikipediaImage {
    param([string]$Title)
    try {
        $keywords = ($Title -split "\s+" | Select-Object -First 4) -join " "
        $encoded  = [uri]::EscapeDataString($keywords)

        $searchUrl    = "https://en.wikipedia.org/w/api.php?action=query&list=search&srsearch=$encoded&format=json&srlimit=1"
        $searchResult = Invoke-RestMethod -Uri $searchUrl -TimeoutSec 10 -ErrorAction Stop

        $pageTitle = Get-SafeProp -Obj ($searchResult.query.search | Select-Object -First 1) -Name "title"
        if (-not $pageTitle) { return $null }

        $encodedTitle = [uri]::EscapeDataString($pageTitle)
        $thumbUrl     = "https://en.wikipedia.org/w/api.php?action=query&titles=$encodedTitle&prop=pageimages&format=json&pithumbsize=800"
        $thumbResult  = Invoke-RestMethod -Uri $thumbUrl -TimeoutSec 10 -ErrorAction Stop

        $pagesProp = $thumbResult.query.pages.PSObject.Properties | Select-Object -First 1
        if (-not $pagesProp) { return $null }

        $thumb = Get-SafeProp -Obj $pagesProp.Value -Name "thumbnail"
        if ($thumb) { return (Get-SafeProp -Obj $thumb -Name "source") }
    } catch { }
    return $null
}

function Get-GoogleTranslation {
    param([string]$Text)
    $encoded = [uri]::EscapeDataString($Text)
    $url     = "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=id&dt=t&q=$encoded"

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10 -ErrorAction Stop
        $translated = ""
        foreach ($seg in $response[0]) {
            if ($seg[0]) { $translated += $seg[0] }
        }
        if ([string]::IsNullOrWhiteSpace($translated)) { return $Text }
        return $translated
    } catch {
        return $Text
    }
}

function Send-TelegramMessage {
    param([string]$Message)
    foreach ($target in $script:targets) {
        $body = @{
            chat_id                  = $target.ChatId
            text                     = $Message
            parse_mode               = "HTML"
            disable_web_page_preview = "true"
        }
        try {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$($target.Token)/sendMessage" -Method Post -Body $body -TimeoutSec 15 | Out-Null
        } catch {
            Write-Host "Failed to send message to $($target.ChatId)"
        }
    }
}

# ---------------------------
# 4. MAIN ENGINE
# ---------------------------

if (-not (Test-Path $script:historyPath)) { "[]" | Out-File $script:historyPath -Encoding UTF8 }

$rawHistory = Get-Content $script:historyPath -Raw -Encoding UTF8
$sentHistory = @()
if (-not [string]::IsNullOrWhiteSpace($rawHistory)) {
    try { $sentHistory = @(ConvertFrom-Json $rawHistory) } 
    catch { $sentHistory = @() }
}

$cutoff = (Get-WIBTime).AddDays(-$script:historyRetentionDays)
$sentHistory = @(
    $sentHistory | Where-Object {
        $d = Get-SafeProp -Obj $_ -Name "SentDate"
        if (-not $d) { return $false }
        try { return ([DateTime]$d -gt $cutoff) } catch { return $false }
    }
)

$wibNow = Get-WIBTime
$currentDate = $wibNow.ToString("MMMM dd, yyyy")

Send-TelegramMessage -Message "<b>Daily News Brief - $currentDate</b>`n<i>Random Selection • 5 Items per Topic</i>"

$allNewsData = @()
$runSeen = [System.Collections.Generic.HashSet[string]]::new()

foreach ($topicName in $topics.Keys) {
    
    $items = @()
    # Acak feed di topik ini, dan batasi jumlah request agar proses script tidak berjalan berjam-jam
    $shuffledFeeds = $topics[$topicName] | Sort-Object { Get-Random } | Select-Object -First $maxFeedsPerTopic

    foreach ($feedUrl in $shuffledFeeds) {
        try {
            # Tambahkan "https://" jika user lupa menulisnya (misal: "money.kompas.com/feed")
            $safeUrl = $feedUrl
            if (-not ($safeUrl -match "^https?://")) { $safeUrl = "https://$safeUrl" }

            [xml]$xml = (Invoke-WebRequest -Uri $safeUrl -UserAgent $script:userAgent -TimeoutSec 10 -ErrorAction Stop).Content
            $nodes = $null

            # Universal parser untuk RSS / Atom / RDF
            if ($xml.rss.channel.item) { $nodes = $xml.rss.channel.item }
            elseif ($xml.feed.entry) { $nodes = $xml.feed.entry }
            elseif ($xml.RDF.item) { $nodes = $xml.RDF.item }

            if ($nodes) {
                foreach ($node in $nodes) {
                    
                    # Ekstrak judul yang formatnya berupa XML Element (seperti CDATA) agar tidak tampil System.Xml.XmlElement
                    $title = $null
                    if ($node.title -is [string]) { 
                        $title = $node.title 
                    } elseif ($node.title.InnerText) { 
                        $title = $node.title.InnerText 
                    } elseif ($node.title."#cdata-section") {
                        $title = $node.title."#cdata-section"
                    } elseif ($node.title."#text") {
                        $title = $node.title."#text"
                    }
                    
                    # Handle Atom link (bisa berupa object href, array, dll) vs RSS link (string)
                    $link = $null
                    if ($node.link -is [string]) { $link = $node.link }
                    elseif ($node.link.href) { $link = $node.link.href }
                    elseif ($node.link[0].href) { $link = $node.link[0].href }

                    if ($title -and $link) {
                        $items += [PSCustomObject]@{
                            Title = [string]$title
                            Link  = [string]$link
                        }
                    }
                }
            }
        } catch {
            Write-Host "Warning: Could not fetch or parse $feedUrl"
        }
    }

    $randomItems = $items | Sort-Object { Get-Random }
    $sentCount = 0

    if (($randomItems | Measure-Object).Count -gt 0) {
        $topicEmoji = switch ($topicName) {
            "Astronomy"        { "🔭" }
            "Science"          { "🔬" }
            "Technology"       { "💻" }
            "Data / AI"        { "🤖" }
            "Movies"           { "🎬" }
            "Economy"          { "📈" }
            "Trading & Crypto" { "₿" }
            "General News"     { "📰" }
            default            { "📌" }
        }

        Send-TelegramMessage -Message "$topicEmoji <b>$topicName</b>"
        Start-Sleep -Seconds 1
    }

    foreach ($item in $randomItems) {
        if ($sentCount -ge 5) { break }

        $fullLink = Resolve-FinalUrl -Url $item.Link
        $canonicalKey = Get-CanonicalUrlKey -Url $fullLink

        if (Test-ShouldBlock -Url $fullLink -Title $item.Title) { continue }

        $alreadySent = $false
        foreach ($h in $sentHistory) {
            $hKey = Get-SafeProp -Obj $h -Name "CanonicalKey"
            if ($hKey -and ($hKey -eq $canonicalKey)) { $alreadySent = $true; break }
        }
        if ($alreadySent -or $runSeen.Contains($canonicalKey)) { continue }

        [void]$runSeen.Add($canonicalKey)

        $translatedTitle = Get-GoogleTranslation -Text $item.Title
        # Mengamankan karakter HTML agar tidak error saat dikirim via Telegram (HTML parse mode)
        $safeTitle = $translatedTitle.Replace("<", "<").Replace(">", ">")

        $imageUrl = Get-ArticleImage -Url $fullLink
        $imageSource = "og:image"
        Start-Sleep -Milliseconds 250

        if (-not $imageUrl) {
            $imageUrl = Get-WikipediaImage -Title $item.Title
            $imageSource = "wikipedia"
            Start-Sleep -Milliseconds 150
        }

        if (-not $imageUrl) { $imageSource = "none" }

        # Ekstrak nama domain dari URL dan format pesan untuk Telegram
        $sourceDomain = ([uri]$fullLink).Host.Replace("www.", "")
        $caption = "<b>$($sentCount + 1). $safeTitle</b>`n<a href='$fullLink'>Baca Selengkapnya</a>`nSource : $sourceDomain"
        
        Send-TelegramMessage -Message $caption
        Start-Sleep -Seconds 1

        $sentDate = (Get-WIBTime).ToString("yyyy-MM-dd HH:mm:ss")

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
# 5. PERSISTENCE
# ---------------------------
$sentHistory | ConvertTo-Json -Depth 6 | Out-File $script:historyPath -Encoding UTF8
$allNewsData | ConvertTo-Json -Depth 6 | Out-File (Join-Path $PSScriptRoot "news.json") -Encoding UTF8

Write-Host "Done. Exported $($allNewsData.Count) items to news.json"
