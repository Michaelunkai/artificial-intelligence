# Apify Setup Guide

## What is Apify?

Apify is a web scraping and automation platform that provides pre-built scrapers (called "Actors") for popular websites like LinkedIn, Twitter, Google, etc.

## Why We Need It

We use Apify's **LinkedIn Jobs Scraper** to automatically find job postings matching your criteria without manually searching LinkedIn every day.

## Setup Steps

### 1. Create Free Account

1. Go to https://apify.com/
2. Click "Start for free"
3. Sign up with email/Google/GitHub
4. Verify your email

**Free Tier Includes:**
- $5/month free credits
- ~200-300 LinkedIn job scrapes/month
- Perfect for this automation

### 2. Get API Token

1. Log in to Apify Console: https://console.apify.com/
2. Click your profile (top-right) → **Integrations**
3. Copy your **API token** (starts with `apify_api_`)
4. Save it to `.env` file:
   ```env
   APIFY_API_TOKEN=apify_api_YOUR_TOKEN_HERE
   ```

### 3. Test LinkedIn Jobs Scraper

1. Go to: https://console.apify.com/actors/apify~linkedin-jobs-scraper
2. Click **Try for free**
3. Configure input:
   ```json
   {
     "positions": ["AI Engineer", "ML Engineer"],
     "location": "Israel",
     "maxItems": 10,
     "remote": true
   }
   ```
4. Click **Start**
5. Wait ~30 seconds
6. Check results → should show 10 LinkedIn jobs

**Expected output format:**
```json
{
  "positionName": "Senior AI Engineer",
  "companyName": "TechCorp",
  "location": "Tel Aviv, Israel",
  "description": "We're looking for...",
  "url": "https://linkedin.com/jobs/view/123456",
  "postedDate": "2 days ago"
}
```

### 4. Configure in n8n

When you import the workflow in n8n:

1. Go to **Credentials** → Add **Apify API**
2. Paste your API token
3. Save
4. Test connection

### 5. Monitor Usage

- Dashboard: https://console.apify.com/account/usage
- Free tier: $5/month = ~200 jobs
- Each job scrape costs ~$0.02
- If you exceed limit, Apify will notify you

### Troubleshooting

**Problem:** "Actor failed" or "Rate limit exceeded"
- **Solution:** LinkedIn may be blocking. Wait 30 minutes and retry.

**Problem:** "No jobs found"
- **Solution:** Check your search keywords and location are valid

**Problem:** "Out of credits"
- **Solution:** 
  - Wait for monthly reset
  - OR upgrade to paid plan ($49/month for $49 credits)
  - OR reduce `maxItems` in workflow

### Alternative: Manual CSV Upload

If Apify doesn't work for some reason:

1. Search LinkedIn manually
2. Export job list to CSV
3. Upload CSV to n8n instead of using Apify node
4. Workflow will still filter and create resumes

## Cost Calculation

| Jobs/Month | Apify Cost | Free Tier? |
|------------|------------|------------|
| 50         | $1         | ✅ Yes     |
| 100        | $2         | ✅ Yes     |
| 200        | $4         | ✅ Yes     |
| 500        | $10        | ❌ No      |

**Recommendation:** Start with 50 jobs/month to stay well within free tier.

## Security

- ✅ API token is private (don't share)
- ✅ Apify doesn't access your LinkedIn account (no login needed)
- ✅ Only scrapes publicly available job postings
- ✅ Complies with LinkedIn's public data policy

---

**Next:** [Setup Google Workspace](setup-google.md)
