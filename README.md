# Daily News Brief Bot

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/indfir/daily-news-bot/daily_brief.yml?label=Daily%20Run&logo=github)](https://github.com/indfir/daily-news-bot/actions)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![License](https://img.shields.io/badge/License-MIT-green.svg)

Bot otomatis yang mengumpulkan tren berita terkini dari berbagai sumber RSS dan mengirimkannya ke Telegram setiap hari pada pukul 06:00 WIB.

## 📋 Daftar Isi

- [Fitur](#-fitur)
- [Topik Berita](#-topik-berita)
- [Cara Kerja](#-cara-kerja)
- [Setup](#-setup)
- [Konfigurasi](#-konfigurasi)
- [Struktur File](#-struktur-file)
- [Troubleshooting](#-troubleshooting)

## ✨ Fitur

### Core Features
- **📰 Multi-Source RSS Aggregation** - Mengumpulkan berita dari ratusan sumber RSS terpercaya
- **🎯 Smart Topic Filtering** - Filter berita berdasarkan kata kunci untuk setiap topik
- **🔄 Deduplication System** - Mencegah duplikasi berita dengan history 30 hari
- **🌐 Auto-Translation** - Menerjemahkan judul berita ke Bahasa Indonesia menggunakan Google Translate
- **🖼️ Smart Image Detection** - Mendeteksi gambar dari og:image, twitter:image, atau Wikipedia fallback
- **⏰ Scheduled Execution** - Berjalan otomatis setiap hari menggunakan GitHub Actions
- **📱 Telegram Integration** - Mengirim berita langsung ke chat Telegram pribadi/kelompok

### Advanced Features
- **Feed Randomizer** - Memilih feed secara acak setiap run untuk variasi konten
- **Domain Blocklist** - Memblokir domain tertentu (paywall, podcast, dll)
- **Content Filter** - Filter konten yang tidak relevan (event, webinar, dll)
- **WIB Timezone** - Output waktu dalam zona waktu WIB (Asia/Jakarta)
- **No Web Preview** - Menonaktifkan preview link Telegram untuk tampilan yang bersih

## 📰 Topik Berita

Bot ini mencakup 7 kategori topik utama:

| Topik | Emoji | Contoh Sumber |
|-------|-------|---------------|
| **Economy** | 📈 | CNBC, Reuters, Forbes, Bloomberg, Kontan, Bisnis |
| **Trading & Crypto** | ₿ | CoinDesk, Cointelegraph, Decrypt, Investing.com |
| **Science** | 🔬 | Nature, Science, Scientific American, LiveScience |
| **Technology** | 💻 | TechCrunch, The Verge, Wired, Ars Technica |
| **Astronomy** | 🔭 | NASA, ESA, Space.com, Universe Today |
| **Movies** | 🎬 | Variety, Hollywood Reporter, Deadline, IndieWire |
| **Data / AI** | 🤖 | OpenAI, Google AI, KDnuggets, Towards Data Science |
| **General News** | 📰 | BBC, CNN, Reuters, AP News, Kompas, Detik |

Setiap topik menampilkan **maksimal 5 berita** per hari dengan sumber yang diacak.

## 🔧 Cara Kerja

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions (Cron)                    │
│                    Schedule: 20:00 UTC                      │
│                    (03:00 WIB - Next Day)                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              fetch_news_cloud.ps1 (PowerShell)              │
│                                                             │
│  1. Load RSS feeds dari 7 topik                            │
│  2. Acak dan pilih max 5 feed per topik                    │
│  3. Parse XML/Atom feed                                    │
│  4. Filter berdasarkan:                                    │
│     - Domain blocklist                                     │
│     - Content blocklist                                    │
│     - Topic keyword relevance                              │
│     - Deduplication (30 hari history)                      │
│  5. Translate judul ke Bahasa Indonesia                    │
│  6. Extract feature image (og:image → Wikipedia fallback)  │
│  7. Send ke Telegram dengan format HTML                    │
│  8. Update news.json dan sent_links_history.json           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Telegram Bot API                         │
│              - Send formatted message                       │
│              - Disable web page preview                     │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 Setup

### Prerequisites
- GitHub account
- Telegram account
- Git installed (optional, untuk setup lokal)

### Langkah 1: Buat Repository

1. Buka [github.com/new](https://github.com/new)
2. Nama repository: `daily-news-bot`
3. Centang **Private** (recommended untuk keamanan token)
4. Klik **Create repository**

### Langkah 2: Upload Files

Upload file-file berikut ke repository:
- `fetch_news_cloud.ps1` - Script utama bot
- `.github/workflows/daily_brief.yml` - GitHub Actions workflow

### Langkah 3: Buat Telegram Bot

1. Buka Telegram dan cari **@BotFather**
2. Kirim perintah `/newbot`
3. Ikuti instruksi untuk membuat bot
4. Simpan **Bot Token** yang diberikan
5. Untuk mendapatkan Chat ID:
   - Mulai chat dengan bot yang baru dibuat
   - Kirim pesan apapun
   - Akses `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
   - Cari nilai `chat.id` di response JSON

### Langkah 4: Add Secrets

1. Buka repository GitHub Anda
2. Pergi ke **Settings** tab
3. Pilih **Secrets and variables** → **Actions**
4. Klik **New repository secret**
5. Tambahkan secrets berikut:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `TELEGRAM_TOKEN` | Bot token dari BotFather | `123456789:ABCdefGHIjklMNOpqrsTUVwxyz` |
| `TELEGRAM_CHAT_ID` | Chat ID penerima pesan | `-1001234567890` |

> ⚠️ **Keamanan**: Jangan pernah commit token Telegram ke repository!

### Langkah 5: Enable Workflow

1. Pergi ke tab **Actions** di repository
2. Klik **I understand my workflows, go ahead and enable them**
3. Untuk test manual: pilih **Daily News Brief** → **Run workflow**

## ⚙️ Konfigurasi

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_TOKEN` | ✅ | Telegram Bot API token |
| `TELEGRAM_CHAT_ID` | ✅ | Chat ID penerima |
| `TELEGRAM_TOKEN_2` | ❌ | Token bot kedua (opsional) |
| `TELEGRAM_CHAT_ID_2` | ❌ | Chat ID kedua (opsional) |

### Custom Topics

Untuk menambahkan atau memodifikasi topik, edit bagian `$topics` di `fetch_news_cloud.ps1`:

```powershell
$topics = @{
    "Your Topic" = @(
        "https://example.com/rss",
        "https://another-feed.com/rss"
    )
}
```

### Keyword Filter

Setiap topik memiliki filter kata kunci di `$topicKeywords`. Berita akan ditampilkan jika judul mengandung minimal satu kata kunci.

### Blocklists

Edit `$domainBlocklist` dan `$contentBlocklist` untuk memblokir konten yang tidak diinginkan:

```powershell
$domainBlocklist = @("nytimes.com", "bloomberg.com", ...)
$contentBlocklist = @("Podcast", "Webinar", "Conference", ...)
```

## 📁 Struktur File

```
daily-news-bot/
├── .github/
│   └── workflows/
│       └── daily_brief.yml    # GitHub Actions workflow
├── fetch_news_cloud.ps1       # Script utama bot
├── news.json                  # Output: data berita yang di-fetch
├── sent_links_history.json    # Deduplication history (30 hari)
├── README.md                  # Dokumentasi
└── .gitignore                 # Git ignore rules
```

### Output Files

**news.json** - Berisi data berita yang di-fetch:
```json
[
  {
    "Topic": "Technology",
    "Title": "Original Title",
    "Link": "https://example.com/article",
    "ImageUrl": "https://example.com/image.jpg",
    "ImageSource": "og:image",
    "Date": "2024-01-15 06:00:00"
  }
]
```

**sent_links_history.json** - History link untuk deduplication:
```json
[
  {
    "CanonicalKey": "https://example.com/article",
    "SentDate": "2024-01-15 06:00:00"
  }
]
```

## 🔍 Troubleshooting

### Workflow tidak berjalan
1. Pastikan workflow sudah di-enable di tab Actions
2. Cek status workflow runs untuk error messages
3. Pastikan file `.github/workflows/daily_brief.yml` ada dan valid

### Bot tidak mengirim pesan
1. Verifikasi `TELEGRAM_TOKEN` dan `TELEGRAM_CHAT_ID` di Secrets
2. Pastikan bot sudah di-start di Telegram
3. Cek apakah Chat ID benar (gunakan format yang tepat untuk group: `-100...`)

### Berita tidak muncul
1. Cek log workflow untuk error parsing RSS
2. Pastikan feed RSS masih aktif
3. Verifikasi keyword filter tidak terlalu ketat

### Deduplication bermasalah
1. Hapus file `sent_links_history.json` untuk reset history
2. History otomatis dihapus setelah 30 hari

## 📝 License

MIT License - lihat [LICENSE](LICENSE) file untuk detail.

## 🤝 Contributing

1. Fork repository ini
2. Buat feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit perubahan (`git commit -m 'Add some AmazingFeature'`)
4. Push ke branch (`git push origin feature/AmazingFeature`)
5. Buka Pull Request

---

**Dibuat dengan ❤️ untuk automasi berita harian**