# Quick Start Guide - AI Job Application Bot

## 🎯 Goal

Get the bot running in under 30 minutes and have it automatically find jobs + generate custom resumes.

## ✅ Prerequisites Check

Before starting, make sure you have:

- [ ] Windows PC (you have this ✅)
- [ ] Node.js 18+ (you have this ✅)
- [ ] n8n installed (you have this ✅)
- [ ] Internet connection
- [ ] Gmail/Google account
- [ ] 30 minutes of time

## 🚀 5-Step Setup

### Step 1: Get API Keys (10 minutes)

#### OpenAI API Key
1. Go to https://platform.openai.com/api-keys
2. Sign up / Log in
3. Click "Create new secret key"
4. Name: `ai-job-bot`
5. Copy the key (starts with `sk-proj-...`)
6. **Save it somewhere safe!** (you can't see it again)

**Cost:** ~$2-5/month for 200 jobs

#### Apify API Token
1. Go to https://apify.com/
2. Sign up (free tier)
3. Go to https://console.apify.com/account/integrations
4. Copy API token (starts with `apify_api_...`)

**Cost:** FREE ($5/month free credits)

#### Google Service Account
**Follow:** [docs/setup-google.md](docs/setup-google.md) (5 minutes)

**Quick version:**
1. Create Google Cloud project
2. Enable Docs/Sheets/Drive APIs
3. Create service account
4. Download JSON key
5. Create Drive folder + Share with service account
6. Create Google Sheet + Share with service account

### Step 2: Configure .env File (3 minutes)

1. Open project folder:
   ```powershell
   cd F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\ai-job-bot
   ```

2. Copy template:
   ```powershell
   Copy-Item .env.template .env
   ```

3. Edit `.env` with Notepad:
   ```powershell
   notepad .env
   ```

4. Fill in:
   ```env
   # OpenAI
   OPENAI_API_KEY=sk-proj-YOUR_KEY_HERE
   
   # Apify
   APIFY_API_TOKEN=apify_api_YOUR_TOKEN_HERE
   
   # Google
   GOOGLE_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
   GOOGLE_DRIVE_FOLDER_ID=YOUR_FOLDER_ID
   GOOGLE_SHEETS_ID=YOUR_SHEET_ID
   
   # Job preferences
   JOB_KEYWORDS=AI Engineer, ML Engineer, Python Developer, DevOps Engineer
   JOB_LOCATION=Israel, Remote
   JOB_REMOTE_ONLY=true
   MIN_RELEVANCE_SCORE=7
   ```

5. Save and close

### Step 3: Customize Resume Data (5 minutes)

1. Open `resume-data.json`:
   ```powershell
   notepad resume-data.json
   ```

2. Update with YOUR information:
   - Name
   - Email
   - Phone
   - Skills
   - Experience
   - Projects
   - Job preferences

3. Save

### Step 4: Start n8n (2 minutes)

1. Run startup script:
   ```powershell
   .\start-n8n.ps1
   ```

2. Wait for n8n to start (30 seconds)

3. Open browser: http://localhost:5678

4. Create n8n account (first time only):
   - Email
   - Password
   - Click "Sign up"

### Step 5: Import Workflow (5 minutes)

1. In n8n UI, click **Import workflow**
2. Select `workflow-ai-job-bot.json`
3. Click **Import**

4. **Configure Credentials** (one-time setup):
   
   **a) OpenAI:**
   - Click any GPT-4o node
   - Click "Create New Credential"
   - Paste OpenAI API key
   - Test connection
   - Save

   **b) Apify:**
   - Click Apify node
   - Create credential
   - Paste Apify token
   - Test
   - Save

   **c) Google Docs:**
   - Click Google Docs node
   - Create credential
   - Paste service account JSON
   - Test
   - Save

   **d) Google Sheets:**
   - Click Google Sheets node
   - Create credential
   - Same service account JSON
   - Test
   - Save

5. Click **Save** (top-right)

## 🧪 Test Run (5 minutes)

### Manual Test

1. Click **Test workflow** button
2. Watch execution:
   - ✅ Parameters set
   - ✅ LinkedIn jobs scraped (5-10 jobs)
   - ✅ GPT-4o filters relevance
   - ✅ Custom resumes generated
   - ✅ Google Docs created
   - ✅ Google Sheets logged

3. Check results:
   - **Google Drive:** See new resume Docs
   - **Google Sheets:** See job log with scores

### Verify Quality

1. Open one resume Doc
2. Check:
   - ✅ Customized for the specific job
   - ✅ Highlights relevant skills
   - ✅ Professional formatting
   - ✅ Correct personal info

## 🔄 Activate Automation (2 minutes)

1. In n8n, toggle workflow **Active** (switch at top)
2. It will now run automatically every day at 9 AM
3. You'll get new resumes without doing anything!

## 📊 Monitoring

### Daily Routine

1. Check Google Sheets for new jobs
2. Review resume Docs
3. Apply to jobs you like (copy resume content)

### Email Notifications (Optional)

Add your email to `.env`:
```env
NOTIFICATION_EMAIL=your@email.com
```

Get daily summary of new jobs!

## ⚡ Quick Commands

Start n8n:
```powershell
.\start-n8n.ps1
```

Stop n8n:
```powershell
# Press Ctrl+C
```

Restart n8n:
```powershell
# Stop (Ctrl+C), then start again
.\start-n8n.ps1
```

Edit config:
```powershell
notepad .env
```

Edit resume:
```powershell
notepad resume-data.json
```

## 🎯 Expected Results

After first run:

- ✅ 5-10 jobs scraped from LinkedIn
- ✅ 3-5 relevant jobs filtered (score >= 7)
- ✅ 3-5 custom resumes created in Google Docs
- ✅ All logged in Google Sheets

**Total time:** ~5 minutes per run

## 🔧 Troubleshooting

**"n8n command not found"**
- Run: `npm install -g n8n`

**"OpenAI API error"**
- Check API key is correct
- Verify you have credits: https://platform.openai.com/usage

**"Apify rate limit"**
- You hit daily limit
- Wait 24 hours OR upgrade Apify plan

**"Google permission denied"**
- Check service account has Editor access to folder/sheet
- Verify folder ID and sheet ID are correct

**"No jobs found"**
- Check job keywords make sense
- Try broader search terms
- Verify location is correct

## 📈 Scaling Up

Once it's working:

1. **Increase job count:**
   - Edit `.env`: `MAX_JOBS_PER_RUN=100`
   - More jobs = more resumes

2. **Adjust filters:**
   - Lower score: `MIN_RELEVANCE_SCORE=6` (more permissive)
   - Higher score: `MIN_RELEVANCE_SCORE=8` (more selective)

3. **Run more frequently:**
   - Edit workflow Schedule node
   - Change to twice daily (9 AM + 6 PM)

4. **Add more job boards:**
   - Duplicate Apify node
   - Use different scrapers (Indeed, Glassdoor, etc.)

## ✅ Success Checklist

You're done when:

- [ ] n8n starts without errors
- [ ] Workflow runs successfully
- [ ] At least 1 job is scraped
- [ ] At least 1 resume is created in Google Docs
- [ ] Job logged in Google Sheets
- [ ] Resume is customized (not generic)
- [ ] All personal info is correct
- [ ] Workflow is set to Active

## 🎉 Next Steps

1. Let it run for 1 week
2. Review the resumes it generates
3. Apply to jobs manually (for now)
4. Fine-tune prompts if needed
5. Share success stories!

## 📞 Support

- n8n Docs: https://docs.n8n.io
- Apify Help: https://docs.apify.com
- OpenAI Support: https://help.openai.com
- Google Cloud: https://cloud.google.com/support

---

**Made with ❤️ for Till | March 2026**
