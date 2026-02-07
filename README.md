# Daily News Brief Bot (Cloud)

This bot automatically fetches trending news and sends it to your Telegram at 06:00 WIB every day.

## Setup Instructions

### 1. Create a Repository
1. Go to [github.com/new](https://github.com/new).
2. Name it `daily-news-bot`.
3. Check "Private" (recommended).
4. Click **Create repository**.

### 2. Upload Files
1. In your new repository, click **Add file** > **Upload files**.
2. Drag and drop the contents of this folder (`fetch_news_cloud.ps1` and `.github` folder).
3. Click **Commit changes**.

### 3. Add Secrets (Important!)
1. Go to **Settings** tab in your repository.
2. Go to **Secrets and variables** > **Actions**.
3. Click **New repository secret**.
4. Add these two secrets:
   - Name: `TELEGRAM_TOKEN`
     - Value: `8248679184:AAFnxVYCy3r3CJR23cJc5sdzxZ4EiLAdqzA`
   - Name: `TELEGRAM_CHAT_ID`
     - Value: `484973817`

### 4. Enable Workflow
1. Go to **Actions** tab.
2. Click **I understand my workflows, go ahead and enable them**.
3. Select **Daily News Brief** on the left.
4. Click **Run workflow** to test it immediately!
