# Daily News Brief Bot

[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/indfir/daily-news-bot/daily_brief.yml?label=Daily%20Run&logo=github)](https://github.com/indfir/daily-news-bot/actions)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue?logo=powershell)
![License](https://img.shields.io/badge/License-MIT-green.svg)

An automated bot that collects current news trends from multiple RSS sources and sends them to Telegram every day at 06:00 WIB.

## Table of Contents

- [Features](#features)
- [News Topics](#news-topics)
- [How It Works](#how-it-works)
- [Setup](#setup)
- [Configuration](#configuration)
- [File Structure](#file-structure)
- [Troubleshooting](#troubleshooting)

## Features

### Core Features

- **Multi-source RSS aggregation** - Collects news from hundreds of trusted RSS sources
- **Smart topic filtering** - Filters news by keywords for each topic
- **Deduplication system** - Prevents duplicate news items with a 30-day history
- **Auto-translation** - Translates news titles into Indonesian using Google Translate
- **Smart image detection** - Detects images from `og:image`, `twitter:image`, or a Wikipedia fallback
- **Scheduled execution** - Runs automatically every day using GitHub Actions
- **Telegram integration** - Sends news directly to a personal or group Telegram chat

### Advanced Features

- **Feed randomizer** - Randomly selects feeds on each run for content variety
- **Domain blocklist** - Blocks selected domains such as paywalled sites, podcasts, and other excluded sources
- **Content filter** - Filters irrelevant content such as events, webinars, and similar items
- **WIB timezone** - Outputs time in WIB (Asia/Jakarta)
- **No web preview** - Disables Telegram link previews for a cleaner message layout

## News Topics

This bot covers 8 main news categories:

| Topic | Example Sources |
|-------|-----------------|
| **Economy** | CNBC, Reuters, Forbes, Bloomberg, Kontan, Bisnis |
| **Trading & Crypto** | CoinDesk, Cointelegraph, Decrypt, Investing.com |
| **Science** | Nature, Science, Scientific American, LiveScience |
| **Technology** | TechCrunch, The Verge, Wired, Ars Technica |
| **Astronomy** | NASA, ESA, Space.com, Universe Today |
| **Movies** | Variety, Hollywood Reporter, Deadline, IndieWire |
| **Data / AI** | OpenAI, Google AI, KDnuggets, Towards Data Science |
| **General News** | BBC, CNN, Reuters, AP News, Kompas, Detik |

Each topic displays a maximum of **5 news items** per day with randomized sources.

## How It Works

```text
+----------------------------------------------------------------+
|                    GitHub Actions (Cron)                       |
|                    Schedule: 20:00 UTC                         |
|                    (03:00 WIB - Next Day)                      |
+----------------------------------------------------------------+
                              |
                              v
+----------------------------------------------------------------+
|              fetch_news_cloud.ps1 (PowerShell)                 |
|                                                                |
|  1. Load RSS feeds from 8 topics                               |
|  2. Randomize and select up to 5 feeds per topic               |
|  3. Parse XML/Atom feeds                                      |
|  4. Filter by:                                                 |
|     - Domain blocklist                                         |
|     - Content blocklist                                        |
|     - Topic keyword relevance                                  |
|     - Deduplication (30-day history)                           |
|  5. Translate titles into Indonesian                           |
|  6. Extract feature image (og:image -> Wikipedia fallback)     |
|  7. Send to Telegram using HTML formatting                     |
|  8. Update news.json and sent_links_history.json               |
+----------------------------------------------------------------+
                              |
                              v
+----------------------------------------------------------------+
|                    Telegram Bot API                            |
|              - Send formatted message                          |
|              - Disable web page preview                        |
+----------------------------------------------------------------+
```

## Setup

### Prerequisites

- GitHub account
- Telegram account
- Git installed (optional for local setup)

### Step 1: Create a Repository

1. Open [github.com/new](https://github.com/new)
2. Set the repository name to `daily-news-bot`
3. Check **Private** (recommended for token security)
4. Click **Create repository**

### Step 2: Upload Files

Upload the following files to the repository:

- `fetch_news_cloud.ps1` - Main bot script
- `.github/workflows/daily_brief.yml` - GitHub Actions workflow

### Step 3: Create a Telegram Bot

1. Open Telegram and search for **@BotFather**
2. Send the `/newbot` command
3. Follow the instructions to create the bot
4. Save the **Bot Token** provided by BotFather
5. To get the Chat ID:
   - Start a chat with the new bot
   - Send any message
   - Open `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
   - Find the `chat.id` value in the JSON response

### Step 4: Add Secrets

1. Open your GitHub repository
2. Go to the **Settings** tab
3. Select **Secrets and variables** -> **Actions**
4. Click **New repository secret**
5. Add the following secrets:

| Secret Name | Description | Example Value |
|-------------|-------------|---------------|
| `TELEGRAM_TOKEN` | Bot token from BotFather | `123456789:ABCdefGHIjklMNOpqrsTUVwxyz` |
| `TELEGRAM_CHAT_ID` | Recipient chat ID | `-1001234567890` |

> **Security:** Never commit Telegram tokens to the repository.

### Step 5: Enable the Workflow

1. Go to the **Actions** tab in the repository
2. Click **I understand my workflows, go ahead and enable them**
3. For a manual test, select **Daily News Brief** -> **Run workflow**

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `TELEGRAM_TOKEN` | Yes | Telegram Bot API token |
| `TELEGRAM_CHAT_ID` | Yes | Recipient chat ID |
| `TELEGRAM_TOKEN_2` | No | Optional second bot token |
| `TELEGRAM_CHAT_ID_2` | No | Optional second chat ID |

### Custom Topics

To add or modify topics, edit the `$topics` section in `fetch_news_cloud.ps1`:

```powershell
$topics = @{
    "Your Topic" = @(
        "https://example.com/rss",
        "https://another-feed.com/rss"
    )
}
```

### Keyword Filter

Each topic has its own keyword filter in `$topicKeywords`. News will be displayed when the title contains at least one matching keyword.

### Blocklists

Edit `$domainBlocklist` and `$contentBlocklist` to block unwanted content:

```powershell
$domainBlocklist = @("nytimes.com", "bloomberg.com", ...)
$contentBlocklist = @("Podcast", "Webinar", "Conference", ...)
```

## File Structure

```text
daily-news-bot/
|-- .github/
|   `-- workflows/
|       `-- daily_brief.yml    # GitHub Actions workflow
|-- fetch_news_cloud.ps1       # Main bot script
|-- news.json                  # Output: fetched news data
|-- sent_links_history.json    # Deduplication history (30 days)
|-- README.md                  # Documentation
`-- .gitignore                 # Git ignore rules
```

### Output Files

**news.json** contains fetched news data:

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

**sent_links_history.json** contains link history for deduplication:

```json
[
  {
    "CanonicalKey": "https://example.com/article",
    "SentDate": "2024-01-15 06:00:00"
  }
]
```

## Troubleshooting

### Workflow Does Not Run

1. Make sure the workflow is enabled in the Actions tab
2. Check workflow run logs for error messages
3. Ensure `.github/workflows/daily_brief.yml` exists and is valid

### Bot Does Not Send Messages

1. Verify `TELEGRAM_TOKEN` and `TELEGRAM_CHAT_ID` in GitHub Secrets
2. Make sure the bot has been started in Telegram
3. Check whether the Chat ID is correct, especially for groups that use the `-100...` format

### News Items Do Not Appear

1. Check workflow logs for RSS parsing errors
2. Make sure the RSS feeds are still active
3. Verify that the keyword filter is not too strict

### Deduplication Issues

1. Delete `sent_links_history.json` to reset history
2. History is automatically removed after 30 days

## License

MIT License - see the [LICENSE](LICENSE) file for details.

## Contributing

1. Fork this repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

---

**Built with care for daily news automation.**
