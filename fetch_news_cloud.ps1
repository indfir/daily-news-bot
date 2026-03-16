# fetch_news_cloud.ps1
# Daily News Fetcher: Randomized, No Paywall, No Podcast, Limit 5 Items
# Features:
# - Custom RSS Feeds per topic (Universal RSS/Atom Parser)
# - Feed Randomizer (picks random feeds per run for performance)
# - Domain + content blocklist
# - Topic keyword filter (OR logic: specific feed OR matching title)
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

$maxFeedsPerTopic = 5

# -------------------------------------------------------
# TOPIC FEEDS — Sudah diganti ke kategori spesifik
# -------------------------------------------------------
$topics = @{
    "Economy" = @(
        # --- Internasional (kategori ekonomi/market spesifik) ---
        "https://www.cnbc.com/id/100003114/device/rss/rss.html",
        "https://www.cnbc.com/id/10000664/device/rss/rss.html",
        "https://www.reutersagency.com/feed/",
        "https://www.forbes.com/markets/feed/",
        "https://www.forbes.com/money/feed/",
        "https://fortune.com/section/finance/feed/",
        "https://feeds.marketwatch.com/marketwatch/topstories/",
        "https://www.nasdaq.com/feed/nasdaq-original/rss.xml",
        "https://seekingalpha.com/feed.xml",
        "https://seekingalpha.com/market_currents.xml",
        "https://finance.yahoo.com/news/rssindex",
        "https://www.investing.com/rss/news_14.rss",
        "https://www.investing.com/rss/news_25.rss",
        "https://moxie.foxbusiness.com/google-publisher/economy.xml",
        "https://moxie.foxbusiness.com/google-publisher/markets.xml",
        "https://feeds.feedburner.com/CalculatedRisk",
        "https://nakedcapitalism.com/feed",
        "https://econlib.org/feed/main",
        "https://economicprism.com/rss_feed.xml",
        "https://gfmag.com/feed",
        "https://financeasia.com/rss/latest",
        "https://investmentwatchblog.com/feed",
        "https://www.thestreet.com/feeds/rss",
        "https://timharford.com/feed",
        # --- India / Asia (kategori bisnis/market) ---
        "https://economictimes.indiatimes.com/markets/rssfeeds/1977021501.cms",
        "https://www.business-standard.com/rss/markets-104.rss",
        "https://www.financialexpress.com/market/feed/",
        "https://www.moneycontrol.com/rss/marketreports.xml",
        "https://feeds.feedburner.com/ndtvnews-top-stories",
        "https://www.livemint.com/rss/markets",
        "https://www.thehindubusinessline.com/markets/feeder/default.rss",
        "https://en.globes.co.il/webservice/rss/rssfeeder.asmx/FeederV2?C_id=516",
        "https://thailand-business-news.com/feed",
        # --- Australia / Africa ---
        "https://www.businesslive.co.za/rss/",
        "https://www.afr.com/rss",
        # --- Indonesia (kategori ekonomi/bisnis spesifik) ---
        "https://money.kompas.com/feed",
        "https://finance.detik.com/feed",
        "https://www.kontan.co.id/rss",
        "https://www.bisnis.com/rss",
        "https://www.cnbcindonesia.com/rss",
        "https://www.antaranews.com/rss/ekonomi",
        "https://www.republika.co.id/rss/ekonomi",
        "https://feed.liputan6.com/rss/bisnis",
        "https://viva.co.id/get/all",
        "https://sindonews.com/feed",
        "https://www.merdeka.com/feed/",
        "https://www.suara.com/rss/bisnis",
        "https://jpnn.com/index.php?mib=rss",
        "https://www.tribunnews.com/rss",
        "https://indianweb2.com/feeds/posts/default"
    )
    "Trading & Crypto" = @(
        # --- Crypto Major (sudah spesifik crypto) ---
        "https://www.coindesk.com/arc/outboundfeeds/rss/",
        "https://cointelegraph.com/rss",
        "https://decrypt.co/feed",
        "https://bitcoinmagazine.com/.rss/feed/index.xml",
        "https://cryptoslate.com/feed/",
        "https://www.coinbureau.com/feed/",
        "https://crypto.news/feed/",
        "https://cryptopotato.com/feed/",
        "https://cryptonews.com/news/feed/",
        "https://thedefiant.io/feed/",
        "https://blog.ethereum.org/feed.xml",
        "https://nulltx.com/feed/",
        "https://bitcoinwarrior.net/feed/",
        "https://dailycoinpost.com/feed/",
        "https://cryptopanic.com/news/rss/",
        "https://99bitcoins.com/feed/",
        "https://news.bitcoin.com/feed/",
        "https://webscrypto.com/feed/",
        "https://cryptocurrencynews.com/feed/",
        "https://www.cryptobreaking.com/feed/",
        "https://smartliquidity.info/feed/",
        "https://coinjournal.net/feed/",
        "https://www.globalcryptopress.com/feeds/posts/default?alt=rss",
        "https://www.cryptoground.com/feeds.xml?format=xml",
        "https://tradersdna.com/feed/",
        "https://fintech.ca/feed/",
        # --- Trading / Forex (sudah spesifik trading) ---
        "https://www.investing.com/rss/news_301.rss",
        "https://www.investing.com/rss/news_1.rss",
        "https://www.investing.com/rss/news_11.rss",
        "https://investinglive.com/feed/",
        "https://actionforex.com/feed/",
        "https://forexcrunch.com/feed/",
        "https://leaprate.com/feed/",
        "https://financemagnates.com/feed/",
        "https://financebrokerage.com/feed/",
        "https://forexnews.world/feed/",
        # --- Exchange / DeFi blogs ---
        "https://blog.kraken.com/feed/",
        "https://blog.coinbase.com/feed/",
        "https://blog.chain.link/feed/",
        "https://fxopen.blog/feed/",
        # --- Indonesia (kategori market) ---
        "https://www.cnbcindonesia.com/rss",
        "https://finance.detik.com/feed",
        "https://www.kontan.co.id/rss",
        "https://www.bisnis.com/rss",
        "https://www.antaranews.com/rss/ekonomi",
        # --- India / Asia (kategori market spesifik) ---
        "https://economictimes.indiatimes.com/markets/rssfeeds/1977021501.cms",
        "https://www.moneycontrol.com/rss/marketreports.xml",
        "https://www.livemint.com/rss/markets",
        "https://www.business-standard.com/rss/markets-104.rss",
        "https://www.thehindubusinessline.com/markets/feeder/default.rss"
    )
    "Science" = @(
        "https://www.nature.com/nature.rss",
        "https://www.science.org/action/showFeed?type=ac_topnews",
        "https://www.scientificamerican.com/science/rss/",
        "http://rss.sciam.com/ScientificAmerican-Global",
        "https://www.newscientist.com/feed/home/",
        "https://phys.org/rss-feed/",
        "https://www.sciencedaily.com/rss/all.xml",
        "https://www.sciencedaily.com/rss/top.xml",
        "https://www.sciencenews.org/feed",
        "https://arstechnica.com/science/feed/",
        "https://www.livescience.com/feeds/rss/home.xml",
        "https://gizmodo.com/tag/science/rss",
        "https://theconversation.com/science/articles?format=rss",
        "https://www.pnas.org/action/showFeed?jc=pnas",
        "https://journals.plos.org/plosone/feed",
        "https://www.cell.com/cell/current.rss",
        "https://www.nejm.org/rss/current",
        "https://sciencebasedmedicine.org/feed/",
        "https://flowingdata.com/feed",
        "https://www.kdnuggets.com/feed",
        "https://towardsdatascience.com/feed",
        "https://machinelearningmastery.com/feed/",
        "https://sains.kompas.com/feed",
        "https://www.detik.com/sains/feed",
        "https://riset.kompas.com/feed"
    )
    "Technology" = @(
        "https://techcrunch.com/feed/",
        "https://www.theverge.com/rss/index.xml",
        "https://www.wired.com/feed/rss",
        "https://www.wired.com/feed/category/science/latest/rss",
        "https://arstechnica.com/feed/",
        "https://www.engadget.com/rss.xml",
        "https://www.cnet.com/rss/news/",
        "https://gizmodo.com/rss",
        "https://mashable.com/feeds/rss/all",
        "https://thenextweb.com/feed/",
        "https://readwrite.com/feed/",
        "https://news.ycombinator.com/rss",
        "http://rss.slashdot.org/Slashdot/slashdotMain",
        "https://www.infoq.com/feed",
        "https://dev.to/feed",
        "https://stackoverflow.com/feeds",
        "https://github.blog/feed/",
        "https://www.technologyreview.com/topic/artificial-intelligence/feed/",
        "https://artificialintelligence-news.com/feed/",
        "https://venturebeat.com/category/ai/feed/",
        "https://www.oreilly.com/ai/rss.xml",
        "https://openai.com/blog/rss/",
        "https://deepmind.com/blog/rss.xml",
        "http://stratechery.com/feed/",
        "https://www.blog.google/rss/",
        "https://tim.blog/feed/",
        "https://tekno.kompas.com/feed",
        "https://inet.detik.com/feed",
        "https://www.techinasia.com/id/feed",
        "https://daily.social/feed/"
    )
    "Astronomy" = @(
        # --- Space Agencies ---
        "https://www.nasa.gov/feed/",
        "https://www.nasa.gov/rss/dyn/breaking_news.rss",
        "https://www.jpl.nasa.gov/feeds/news",
        "https://science.nasa.gov/feeds/science-news",
        "https://blogs.nasa.gov/artemis/feed/",
        "https://blogs.nasa.gov/spacestation/feed/",
        "https://www.esa.int/rssfeed/TopNews",
        "https://www.jaxa.jp/pr/press/press_xml_e.xml",
        # --- Major Space News ---
        "https://www.space.com/feeds/all",
        "https://www.space.com/home/feed/site.xml",
        "https://spacenews.com/feed/",
        "https://spaceflightnow.com/feed/",
        "https://www.universetoday.com/feed/",
        "https://astronomynow.com/feed/",
        "https://www.astronomy.com/feed/",
        "https://www.skyandtelescope.org/astronomy-news/feed/",
        "https://nasawatch.com/feed/",
        "https://americaspace.com/feed/",
        "https://nasaspaceflight.com/feed/",
        # --- Science / Space Sections ---
        "https://www.theguardian.com/science/space/rss",
        "https://www.newscientist.com/subject/space/feed/",
        "https://phys.org/rss-feed/space-news/",
        "https://sciencenews.org/topic/space/feed/",
        "https://www.cbsnews.com/latest/rss/space",
        "https://feeds.npr.org/1026/rss.xml",
        "https://arstechnica.com/science/feed/",
        "https://www.livescience.com/feeds/rss/home.xml",
        # --- Dedicated Space/Astro ---
        "https://www.planetary.org/rss/articles",
        "https://spacedaily.com/spacedaily.xml",
        "https://thespacereview.com/articles.xml",
        "https://marsdaily.com/marsdaily.xml",
        "https://www.moondaily.com/moondaily.xml",
        "https://www.earthobservatory.nasa.gov/feeds/earth-observatory.rss",
        "https://hubblesite.org/api/v3/news?page=all&format=rss",
        "https://feeds.feedburner.com/CollectspaceSpaceHistoryNews",
        # --- Blogs & Independent ---
        "https://www.dailygalaxy.com/feed/",
        "https://earthsky.org/feed/",
        "https://badastronomy.com/feed/",
        "https://www.centauri-dreams.org/feed/",
        "https://manyworlds.space/feed/",
        # --- Rockets & Commercial ---
        "https://rocketlabusa.com/updates/feed/",
        "https://aas.org/feed",
        # --- International ---
        "https://irishspaceblog.blogspot.com/feeds/posts/default?alt=rss",
        # --- Data / Image feeds ---
        "https://apod.nasa.gov/apod.rss",
        "https://www.nasa.gov/rss/dyn/lg_image_of_the_day.rss",
        "https://www.eso.org/public/news/feed/",
        "https://chandra.harvard.edu/rss/blog.xml",
        # --- Extra ---
        "https://www.skyandtelescope.org/feed/",
        "https://www.space.com/feeds/rss/all.xml",
        "https://www.planetary.org/feed/articles.xml"
    )
    "Movies" = @(
        "https://variety.com/v/film/feed/",
        "https://www.hollywoodreporter.com/c/movies/feed/",
        "https://www.indiewire.com/c/film-reviews/feed/",
        "https://deadline.com/category/film/feed/",
        "https://screenrant.com/feed/",
        "https://collider.com/feed/",
        "https://www.empireonline.com/movies/feed/rss/",
        "https://editorial.rottentomatoes.com/feed/",
        "https://feeds2.feedburner.com/slashfilm",
        "https://www.aintitcool.com/node/feed/",
        "https://www.comingsoon.net/feed",
        "https://filmschoolrejects.com/feed/",
        "https://www.firstshowing.net/feed/",
        "https://film.avclub.com/rss",
        "https://www.bleedingcool.com/movies/feed/",
        "https://ew.com/movies/feed/",
        "https://www.vulture.com/feed.xml",
        "https://www.tmz.com/rss.xml",
        "https://people.com/rss/index.xml",
        "https://www.streamingmedia.com/rss/feed.asp",
        "https://www.cordcuttersnews.com/rss/",
        "https://decider.com/feed/",
        "https://www.layar-21.com/feed/",
        "https://www.filmapik.com/feed/",
        "https://www.duniaku.net/feed"
    )
    "Data / AI" = @(
        "https://www.technologyreview.com/topic/artificial-intelligence/feed/",
        "https://artificialintelligence-news.com/feed/",
        "https://venturebeat.com/category/ai/feed/",
        "https://www.oreilly.com/ai/rss.xml",
        "https://openai.com/blog/rss/",
        "https://deepmind.com/blog/rss.xml",
        "https://www.anthropic.com/rss",
        "https://www.kdnuggets.com/feed",
        "https://towardsdatascience.com/feed",
        "https://machinelearningmastery.com/feed/",
        "https://www.datasciencecentral.com/profiles/blog/feed",
        "https://www.analyticsvidhya.com/blog/feed/",
        "https://www.datacamp.com/community/rss",
        "https://www.oreilly.com/data/rss.xml",
        "https://arxiv.org/rss/cs.AI",
        "https://arxiv.org/rss/cs.LG",
        "https://arxiv.org/rss/cs.CV",
        "https://paperswithcode.com/latest",
        "https://ml-compiled.readthedocs.io/en/latest/rss.xml",
        "https://www.forbes.com/ai/feed/",
        "https://www.zdnet.com/topic/artificial-intelligence/rss.xml",
        "https://www.infoworld.com/rss.xml"
    )
    "General News" = @(
        "http://feeds.bbci.co.uk/news/rss.xml",
        "http://rss.cnn.com/rss/edition.rss",
        "https://www.reutersagency.com/feed/",
        "https://apnews.com/rss",
        "https://www.theguardian.com/world/rss",
        "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml",
        "https://feeds.washingtonpost.com/rss/national",
        "https://www.npr.org/rss/rss.php?id=1001",
        "https://www.nbcnews.com/rss",
        "https://abcnews.go.com/abcnews/topstories",
        "https://timesofindia.indiatimes.com/rssfeedstopstories.cms",
        "https://www.thehindu.com/feeder/default.rss",
        "https://www.straitstimes.com/rss",
        "https://www.scmp.com/rss/91/feed",
        "https://www.japantimes.co.jp/feed/topstories/",
        "https://english.kyodonews.net/rss/all.xml",
        "https://rss.dw.com/rdf/rss-en-all",
        "http://newsfeed.zeit.de/index",
        "https://rss.focus.de/fol/XML/rss_folnews.xml",
        "http://www.tagesschau.de/xml/rss2",
        "https://feeds.thelocal.com/rss",
        "https://feeds.elpais.com/mrss-s/pages/ep/site/elpais.com/portada",
        "https://www.lemonde.fr/rss/une.xml",
        "https://www.france24.com/en/rss",
        "https://www.detik.com/feed",
        "https://www.antaranews.com/rss",
        "https://www.republika.co.id/rss/",
        "https://www.tribunnews.com/rss",
        "https://www.merdeka.com/feed/",
        "https://www.suara.com/rss"
    )
}

# -------------------------------------------------------
# TOPIC KEYWORD FILTER (safety net — OR logic)
# Artikel lolos kalau judul mengandung MINIMAL 1 keyword
# General News: semua lolos tanpa filter
# -------------------------------------------------------
$topicKeywords = @{
    "Economy" = @(
        "economy", "economic", "ekonomi", "GDP", "inflation", "inflasi",
        "recession", "resesi", "fiscal", "fiskal", "monetary", "moneter",
        "bank central", "central bank", "interest rate", "suku bunga",
        "trade", "perdagangan", "export", "import", "ekspor", "impor",
        "tax", "pajak", "budget", "anggaran", "debt", "utang", "hutang",
        "market", "pasar", "stock", "saham", "bond", "obligasi",
        "finance", "keuangan", "investment", "investasi", "investor",
        "revenue", "profit", "earnings", "dividen", "dividend",
        "IPO", "IHSG", "Wall Street", "Nasdaq", "S&P", "Dow Jones",
        "commodity", "komoditas", "oil", "minyak", "gold", "emas",
        "rupiah", "dollar", "currency", "mata uang", "forex",
        "business", "bisnis", "startup", "unicorn", "merger", "acquisition",
        "supply chain", "manufacture", "industri", "industry",
        "unemployment", "pengangguran", "wage", "upah", "gaji", "salary",
        "BI rate", "The Fed", "ECB", "IMF", "World Bank", "Bank Dunia",
        "APBN", "BUMN", "OJK", "BEI", "bursa"
    )
    "Trading & Crypto" = @(
        "bitcoin", "BTC", "ethereum", "ETH", "crypto", "kripto",
        "blockchain", "DeFi", "NFT", "altcoin", "token", "coin",
        "mining", "miner", "staking", "yield", "airdrop", "dex",
        "exchange", "binance", "coinbase", "kraken", "bybit", "okx",
        "trading", "trader", "forex", "FX", "currency pair",
        "bull", "bear", "rally", "crash", "pump", "dump",
        "wallet", "ledger", "metamask", "web3", "solana", "SOL",
        "ripple", "XRP", "dogecoin", "DOGE", "cardano", "ADA",
        "polkadot", "DOT", "avalanche", "AVAX", "polygon", "MATIC",
        "stablecoin", "USDT", "USDC", "tether", "liquidity",
        "leverage", "margin", "futures", "options", "derivatives",
        "candlestick", "chart", "technical analysis", "resistance", "support",
        "SEC", "regulation", "regulasi", "halving", "memecoin",
        "commodities", "gold trading", "oil trading", "silver",
        "pip", "spread", "lot", "scalping", "swing trade",
        "signal", "indicator", "RSI", "MACD", "moving average"
    )
    "Science" = @(
        "science", "sains", "research", "penelitian", "riset",
        "study", "studi", "discovery", "penemuan", "experiment",
        "laboratory", "lab", "scientist", "ilmuwan",
        "physics", "fisika", "chemistry", "kimia", "biology", "biologi",
        "genetics", "genetika", "DNA", "RNA", "genome", "gene",
        "climate", "iklim", "environment", "lingkungan", "ecology",
        "evolution", "evolusi", "species", "spesies", "fossil",
        "brain", "otak", "neuroscience", "neuron", "psychology",
        "vaccine", "vaksin", "virus", "bacteria", "disease", "penyakit",
        "medicine", "medical", "health", "kesehatan", "therapy",
        "quantum", "atom", "molecule", "particle", "energy",
        "ocean", "laut", "earthquake", "gempa", "volcano", "gunung",
        "data science", "statistics", "statistik", "algorithm"
    )
    "Technology" = @(
        "tech", "teknologi", "technology", "software", "hardware",
        "AI", "artificial intelligence", "kecerdasan buatan",
        "machine learning", "deep learning", "neural network",
        "robot", "robotics", "automation", "otomasi",
        "smartphone", "laptop", "gadget", "device", "chip", "processor",
        "cloud", "server", "database", "API", "programming", "coding",
        "startup", "app", "aplikasi", "platform", "SaaS",
        "cybersecurity", "hacker", "privacy", "encryption",
        "5G", "internet", "wifi", "broadband", "fiber",
        "Google", "Apple", "Microsoft", "Meta", "Amazon", "Samsung",
        "open source", "Linux", "GitHub", "developer",
        "VR", "AR", "virtual reality", "augmented reality", "metaverse",
        "autonomous", "self-driving", "EV", "electric vehicle",
        "semiconductor", "silicon", "TSMC", "Nvidia", "Intel"
    )
    "Astronomy" = @(
        "space", "luar angkasa", "antariksa", "astronomy", "astronomi",
        "NASA", "ESA", "JAXA", "SpaceX", "rocket", "roket",
        "satellite", "satelit", "orbit", "launch", "peluncuran",
        "planet", "mars", "jupiter", "saturn", "venus", "mercury",
        "moon", "bulan", "lunar", "solar", "sun", "matahari",
        "star", "bintang", "galaxy", "galaksi", "nebula", "cosmos",
        "telescope", "teleskop", "Hubble", "JWST", "Webb",
        "asteroid", "comet", "komet", "meteor", "meteorit",
        "black hole", "dark matter", "dark energy", "supernova",
        "ISS", "space station", "astronaut", "kosmonaut",
        "exoplanet", "light year", "tahun cahaya", "constellation",
        "milky way", "Bima Sakti", "cosmic", "universe", "alam semesta",
        "spacecraft", "rover", "probe", "lander", "mission",
        "starship", "falcon", "artemis", "crew dragon",
        "gravitational wave", "pulsar", "quasar", "magnetar",
        "astrophysics", "astrobiology", "cosmology"
    )
    "Movies" = @(
        "movie", "film", "cinema", "bioskop", "box office",
        "trailer", "teaser", "premiere", "premier",
        "director", "sutradara", "actor", "actress", "aktris",
        "Oscar", "Academy Award", "Golden Globe", "Emmy",
        "Hollywood", "Bollywood", "Netflix", "Disney+", "HBO",
        "streaming", "sequel", "prequel", "reboot", "remake",
        "superhero", "Marvel", "DC", "horror", "thriller",
        "comedy", "komedi", "drama", "action", "animation", "animasi",
        "screenplay", "script", "casting", "review", "rating",
        "blockbuster", "indie", "festival", "Cannes", "Sundance",
        "series", "TV show",
        "documentary", "dokumenter", "short film", "feature film",
        "CGI", "VFX", "special effects", "soundtrack",
        "production", "produksi", "studio", "Warner", "Universal",
        "Paramount", "Sony Pictures", "Lionsgate", "A24"
    )
    "Data / AI" = @(
        "AI", "artificial intelligence", "kecerdasan buatan",
        "machine learning", "deep learning", "neural network",
        "GPT", "LLM", "large language model", "transformer",
        "ChatGPT", "OpenAI", "Anthropic", "Claude", "Gemini", "Llama",
        "data science", "data engineering", "big data",
        "NLP", "natural language", "computer vision",
        "reinforcement learning", "supervised", "unsupervised",
        "training", "fine-tuning", "model", "benchmark",
        "dataset", "annotation", "labeling", "preprocessing",
        "TensorFlow", "PyTorch", "Keras", "scikit-learn",
        "MLOps", "deployment", "inference", "pipeline",
        "ethics", "bias", "fairness", "alignment", "safety",
        "generative AI", "diffusion", "image generation",
        "prompt engineering", "RAG", "retrieval", "embedding",
        "autonomous", "agent", "multimodal", "foundation model",
        "research paper", "arxiv", "ICML", "NeurIPS",
        "robotics", "automation", "prediction", "classification"
    )
    "General News" = @()  # Semua berita lolos tanpa filter
}

# -------------------------------------------------------
# BLOCKLISTS
# -------------------------------------------------------
$domainBlocklist = @(
    "nytimes.com", "wsj.com", "bloomberg.com", "ft.com", "economist.com",
    "hbr.org", "medium.com", "washingtonpost.com", "thetimes.co.uk",
    "barrons.com", "businessinsider.com", "nikkei.com", "kompas.id", "tempo.co",
    "spotify.com", "apple.com", "podcasts.google.com", "podbean.com", "soundcloud.com", "youtube.com"
)

$contentBlocklist = @(
    "Register", "Admission", "Seminar", "Webinar", "Workshop",
    "Conference", "Symposium", "Registration", "Tickets", "Eventbrite",
    "Podcast", "Episode", "Ep.", "Listen", "Audio"
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
        $host_  = $u.Host.ToLowerInvariant().Replace("www.", "")
        $path   = $u.AbsolutePath.TrimEnd("/")
        $scheme = $u.Scheme.ToLowerInvariant()
        return "${scheme}://${host_}${path}".ToLowerInvariant()
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

# -------------------------------------------------------
# TOPIC RELEVANCE CHECK (OR logic / safety net)
# Artikel lolos jika judul mengandung minimal 1 keyword
# General News: semua lolos (keyword list kosong)
# -------------------------------------------------------
function Test-TopicRelevant {
    param([string]$Title, [string]$TopicName)
    
    $keywords = $topicKeywords[$TopicName]
    if (-not $keywords -or $keywords.Count -eq 0) { return $true }
    
    $lowerTitle = $Title.ToLowerInvariant()
    foreach ($kw in $keywords) {
        if ($lowerTitle.Contains($kw.ToLowerInvariant())) {
            return $true
        }
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
    $shuffledFeeds = $topics[$topicName] | Sort-Object { Get-Random } | Select-Object -First $maxFeedsPerTopic

    foreach ($feedUrl in $shuffledFeeds) {
        try {
            $safeUrl = $feedUrl
            if (-not ($safeUrl -match "^https?://")) { $safeUrl = "https://$safeUrl" }

            [xml]$xml = (Invoke-WebRequest -Uri $safeUrl -UserAgent $script:userAgent -TimeoutSec 10 -ErrorAction Stop).Content
            $nodes = $null

            if ($xml.rss.channel.item) { $nodes = $xml.rss.channel.item }
            elseif ($xml.feed.entry) { $nodes = $xml.feed.entry }
            elseif ($xml.RDF.item) { $nodes = $xml.RDF.item }

            if ($nodes) {
                foreach ($node in $nodes) {
                    
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

        # Domain + content blocklist
        if (Test-ShouldBlock -Url $fullLink -Title $item.Title) { continue }

        # Topic relevance keyword filter (OR logic safety net)
        if (-not (Test-TopicRelevant -Title $item.Title -TopicName $topicName)) {
            Write-Host "  Skipped (off-topic for $topicName): $($item.Title)"
            continue
        }

        # Dedup check
        $alreadySent = $false
        foreach ($h in $sentHistory) {
            $hKey = Get-SafeProp -Obj $h -Name "CanonicalKey"
            if ($hKey -and ($hKey -eq $canonicalKey)) { $alreadySent = $true; break }
        }
        if ($alreadySent -or $runSeen.Contains($canonicalKey)) { continue }

        [void]$runSeen.Add($canonicalKey)

        $translatedTitle = Get-GoogleTranslation -Text $item.Title
        $safeTitle = $translatedTitle.Replace("<", "&lt;").Replace(">", "&gt;")

        $imageUrl = Get-ArticleImage -Url $fullLink
        $imageSource = "og:image"
        Start-Sleep -Milliseconds 250

        if (-not $imageUrl) {
            $imageUrl = Get-WikipediaImage -Title $item.Title
            $imageSource = "wikipedia"
            Start-Sleep -Milliseconds 150
        }

        if (-not $imageUrl) { $imageSource = "none" }

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
