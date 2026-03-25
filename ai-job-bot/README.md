# AI Job Application Bot

**Autonomous n8n workflow that finds LinkedIn jobs, filters for relevance, and generates custom resumes for each position.**

## Features

- 🔍 **Scrapes 100s of LinkedIn jobs** using Apify
- 🤖 **AI-powered filtering** with GPT-4o to match your skills
- 📝 **Auto-generates custom HTML resumes** for each relevant job
- 📄 **Creates Google Docs** for each resume
- 📊 **Logs everything** in Google Sheets database
- ⏰ **Runs automatically** on schedule (daily/weekly)

## Tech Stack

- **n8n** - Workflow automation platform
- **Apify** - LinkedIn job scraping
- **OpenAI GPT-4o** - Job relevance filtering & resume customization
- **Google Workspace** - Docs & Sheets for storage

## Setup Instructions

### 1. Prerequisites

- Node.js 18+ (installed: ✅)
- npm (installed: ✅)
- n8n (installing...)
- Apify account (free tier works)
- OpenAI API key
- Google Workspace account

### 2. Installation

```powershell
# n8n is installing globally...
npm install -g n8n

# Navigate to project
cd F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\ai-job-bot

# Copy environment template
cp .env.template .env

# Edit .env with your API keys
notepad .env
```

### 3. Configuration

Fill in `.env` with your credentials:

```env
# OpenAI API Key
OPENAI_API_KEY=sk-...

# Apify API Token
APIFY_API_TOKEN=apify_api_...

# Google Service Account JSON (for Docs/Sheets)
GOOGLE_SERVICE_ACCOUNT={"type":"service_account",...}

# Job Search Parameters
JOB_KEYWORDS=AI Engineer, ML Engineer, Python Developer, DevOps Engineer
JOB_LOCATION=Israel, Remote
JOB_REMOTE_ONLY=true
```

### 4. Resume Data

Edit `resume-data.json` with your professional details. This is the master resume that AI will customize for each job.

### 5. Import Workflow

```powershell
# Start n8n
n8n start

# Open browser: http://localhost:5678
# Import workflow-ai-job-bot.json
# Configure credentials for Apify, OpenAI, Google
```

### 6. Test Run

1. Trigger workflow manually
2. Check that jobs are scraped
3. Verify AI filtering works
4. Check resume generation
5. Confirm Google Docs/Sheets creation

### 7. Schedule Automation

In n8n:
- Add "Schedule Trigger" node
- Set to run daily at 9 AM
- Save & activate workflow

## Workflow Parts (from video)

| Part | Function | Description |
|------|----------|-------------|
| 1-2 | Setup | Initialize job search parameters |
| 3 | Scraping | Apify LinkedIn job scraper |
| 4 | Filtering | GPT-4o checks job relevance |
| 5 | Data Processing | Clean & structure job data |
| 6 | Resume Generation | GPT-4o creates custom HTML resume |
| 7 | Google Docs | Creates Doc for each resume |
| 8 | Logging | Logs to Google Sheets database |

## Project Structure

```
ai-job-bot/
├── README.md                    # This file
├── .env                         # Your API keys (DO NOT COMMIT)
├── .env.template                # Environment template
├── resume-data.json             # Your resume master data
├── workflow-ai-job-bot.json     # n8n workflow export
├── docs/
│   ├── setup-apify.md          # Apify setup guide
│   ├── setup-google.md         # Google Workspace setup
│   └── customization.md        # How to customize prompts
└── logs/
    └── job-applications.log    # Execution logs
```

## Customization

### Job Search Criteria

Edit in n8n workflow → "Set Parameters" node:
- Keywords
- Location
- Remote only
- Experience level
- Company size

### AI Prompts

Edit in n8n workflow → "Filter Jobs" and "Generate Resume" nodes:
- Job relevance criteria
- Resume style/tone
- Skills to emphasize
- Industries to prioritize

## Monitoring

- **n8n Dashboard**: http://localhost:5678 → Executions
- **Google Sheets**: See all processed jobs
- **Google Drive**: All generated resume Docs

## Troubleshooting

### Apify scraping fails
- Check Apify credits (free tier: 5 USD/month)
- Verify LinkedIn scraper is active
- Reduce job count in parameters

### GPT-4o filtering too strict/loose
- Adjust relevance prompt in "Filter Jobs" node
- Change scoring threshold (default: 7/10)

### Google Docs not creating
- Verify Service Account has Docs/Drive permissions
- Check Google Workspace API is enabled
- Confirm credentials are valid

## Cost Estimate

- **Apify**: Free tier (5 USD/month) = ~200 jobs/month
- **OpenAI GPT-4o**: ~$0.01 per job filtered + resume = ~$2-5/month for 200 jobs
- **n8n**: Self-hosted = Free
- **Google Workspace**: Free (personal account)

**Total: ~$2-5/month for 200 automated job applications**

## Security

- ✅ All API keys in `.env` (gitignored)
- ✅ Resume data stays local
- ✅ Generated resumes in your Google Drive only
- ❌ DO NOT commit `.env` or `resume-data.json` to Git

## Next Steps

1. ✅ Install n8n
2. ✅ Create Apify account
3. ✅ Get OpenAI API key
4. ✅ Set up Google Service Account
5. ✅ Fill resume data
6. ✅ Import workflow
7. ✅ Test run
8. ✅ Activate automation

## Support

- n8n Docs: https://docs.n8n.io
- Apify Docs: https://docs.apify.com
- OpenAI API: https://platform.openai.com/docs
- Original Video: https://youtu.be/lq8OaM-SeJo

---

**Built for Till Thelet | 2026-03-09**
