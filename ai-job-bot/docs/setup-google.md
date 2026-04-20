# Google Workspace Setup Guide

## What We Need

- **Google Docs** - To create custom HTML resumes for each job
- **Google Sheets** - To log all job applications in a database
- **Google Drive** - To store all resume documents

## Why Google?

- ✅ Free (personal Gmail account works)
- ✅ Cloud storage (access resumes anywhere)
- ✅ Easy sharing with recruiters
- ✅ Automatic versioning and backup
- ✅ Native n8n integration

## Setup Steps

### Step 1: Create Google Cloud Project

1. Go to https://console.cloud.google.com/
2. Click **Select a project** → **New Project**
3. Project name: `ai-job-bot`
4. Click **Create**
5. Wait 30 seconds for project creation

### Step 2: Enable Required APIs

1. Go to **APIs & Services** → **Library**
2. Search and enable these 3 APIs:
   - ✅ **Google Docs API**
   - ✅ **Google Sheets API**
   - ✅ **Google Drive API**

For each:
- Click the API name
- Click **Enable**
- Wait for activation

### Step 3: Create Service Account

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **Service Account**
3. Service account name: `ai-job-bot-service`
4. Service account ID: auto-generated
5. Click **Create and Continue**
6. Grant role: **Editor**
7. Click **Done**

### Step 4: Generate Service Account Key

1. Click on the service account you just created
2. Go to **Keys** tab
3. Click **Add Key** → **Create new key**
4. Key type: **JSON**
5. Click **Create**
6. Save the JSON file (e.g., `service-account-key.json`)

### Step 5: Add Key to .env

1. Open the downloaded JSON file
2. Copy the entire JSON content
3. In your `.env` file, paste it as one line:
   ```env
   GOOGLE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"ai-job-bot-123456",...}
   ```

**Important:** Remove all line breaks from the JSON (make it one continuous line).

### Step 6: Create Google Drive Folder

1. Go to https://drive.google.com/
2. Click **New** → **Folder**
3. Name: `AI Job Bot Resumes`
4. Click **Create**
5. Right-click folder → **Share**
6. Add service account email (e.g., `ai-job-bot-service@ai-job-bot-123456.iam.gserviceaccount.com`)
7. Give **Editor** permission
8. Click **Share**

### Step 7: Get Folder ID

1. Open the folder in Drive
2. Look at URL: `https://drive.google.com/drive/folders/ABC123XYZ`
3. Copy the folder ID: `ABC123XYZ`
4. Add to `.env`:
   ```env
   GOOGLE_DRIVE_FOLDER_ID=ABC123XYZ
   ```

### Step 8: Create Google Sheet for Logging

1. Go to https://docs.google.com/spreadsheets/
2. Click **Blank** to create new sheet
3. Name: `AI Job Bot - Application Log`
4. Add column headers in Row 1:
   - A1: `Timestamp`
   - B1: `Position`
   - C1: `Company`
   - D1: `Location`
   - E1: `Relevance Score`
   - F1: `Matching Skills`
   - G1: `Resume Doc URL`
   - H1: `Job URL`
   - I1: `Status`

5. Right-click sheet name → **Share**
6. Add service account email
7. Give **Editor** permission
8. Click **Share**

### Step 9: Get Sheet ID

1. Look at URL: `https://docs.google.com/spreadsheets/d/ABC123XYZ/edit`
2. Copy sheet ID: `ABC123XYZ`
3. Add to `.env`:
   ```env
   GOOGLE_SHEETS_ID=ABC123XYZ
   ```

### Step 10: Configure in n8n

When you import the workflow:

1. **Google Docs Credential:**
   - Go to n8n **Credentials**
   - Add **Google Docs OAuth2 API**
   - Paste service account JSON
   - Test connection

2. **Google Sheets Credential:**
   - Add **Google Sheets OAuth2 API**
   - Paste service account JSON
   - Test connection

## Verification Checklist

- ✅ Google Cloud project created
- ✅ 3 APIs enabled (Docs, Sheets, Drive)
- ✅ Service account created
- ✅ Service account JSON key downloaded
- ✅ JSON key added to `.env`
- ✅ Drive folder created and shared with service account
- ✅ Drive folder ID added to `.env`
- ✅ Google Sheet created with headers
- ✅ Sheet shared with service account
- ✅ Sheet ID added to `.env`

## Expected Folder Structure

After workflow runs:

```
Google Drive → AI Job Bot Resumes/
├── Resume - TechCorp - AI Engineer.docx
├── Resume - StartupX - ML Engineer.docx
├── Resume - CloudCo - DevOps Engineer.docx
└── ...
```

## Google Sheets Database

| Timestamp | Position | Company | Location | Relevance Score | Matching Skills | Resume Doc URL | Job URL | Status |
|-----------|----------|---------|----------|----------------|-----------------|----------------|---------|--------|
| 2026-03-09 09:00 | AI Engineer | TechCorp | Tel Aviv | 9 | Python, ML, AWS | https://docs.google.com/... | https://linkedin.com/... | Pending |
| 2026-03-09 09:05 | ML Engineer | StartupX | Remote | 8 | PyTorch, NLP | https://docs.google.com/... | https://linkedin.com/... | Pending |

## Troubleshooting

**Problem:** "Permission denied" when creating Doc
- **Solution:** Check that service account email has Editor access to Drive folder

**Problem:** "Spreadsheet not found"
- **Solution:** Verify Sheet ID is correct and sheet is shared with service account

**Problem:** "Invalid credentials"
- **Solution:** 
  - Re-download service account JSON key
  - Make sure JSON is on one line in `.env`
  - No extra spaces or line breaks

**Problem:** Docs are created but empty
- **Solution:** Check HTML content is being generated by GPT-4o node

## Security

- ✅ Service account has access ONLY to specific folder/sheet
- ✅ No access to your personal Gmail/Drive
- ✅ API keys stay in `.env` (never committed to Git)
- ✅ Resumes are private (only you and service account can access)

## Cost

**FREE** - Personal Google account includes:
- 15 GB Google Drive storage
- Unlimited Docs/Sheets
- API usage is free for personal use

---

**Next:** [Workflow Customization Guide](customization.md)
