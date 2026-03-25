# AI Job Bot - Complete Test Checklist

## Pre-Test Verification

### Environment Setup
- [ ] n8n version 2.11.2 installed (`n8n --version`)
- [ ] `.env` file exists and filled out
- [ ] `resume-data.json` has your actual data
- [ ] All API keys are valid

### API Keys Check
```powershell
# Test OpenAI
curl https://api.openai.com/v1/models -H "Authorization: Bearer YOUR_KEY"
# Should return model list

# Test Apify
curl https://api.apify.com/v2/acts -H "Authorization: Bearer YOUR_TOKEN"
# Should return HTTP 200

# Google - tested in n8n UI
```

## Test 1: n8n Startup ✅

**Goal:** Verify n8n starts without errors

**Steps:**
1. Run `.\start-n8n.ps1`
2. Check terminal output
3. Open http://localhost:5678

**Expected:**
- ✅ n8n loads in browser
- ✅ No errors in terminal
- ✅ Login page or dashboard appears

**Pass Criteria:**
- Web UI is accessible
- No "port already in use" errors

---

## Test 2: Workflow Import ✅

**Goal:** Import workflow successfully

**Steps:**
1. In n8n, click "Import from file"
2. Select `workflow-ai-job-bot.json`
3. Click "Import"

**Expected:**
- ✅ Workflow appears with all nodes
- ✅ 14 nodes visible:
  - Schedule Trigger
  - Set Parameters
  - Scrape LinkedIn Jobs
  - Read Resume Data
  - Merge Jobs with Resume
  - Filter Jobs with GPT-4o
  - Keep Only Relevant Jobs
  - Generate Custom Resume
  - Create Google Doc
  - Log to Google Sheets
  - Summarize Results
  - Send Telegram Notification

**Pass Criteria:**
- All nodes connected correctly
- No missing nodes

---

## Test 3: Credential Setup ✅

**Goal:** Configure all API credentials

**For each credential:**

### OpenAI
- [ ] Create credential
- [ ] Paste API key
- [ ] Test connection → ✅ Success

### Apify
- [ ] Create credential
- [ ] Paste token
- [ ] Test connection → ✅ Success

### Google Docs
- [ ] Create credential
- [ ] Paste service account JSON
- [ ] Test connection → ✅ Success

### Google Sheets
- [ ] Create credential
- [ ] Paste service account JSON
- [ ] Test connection → ✅ Success

**Pass Criteria:**
- All 4 credentials show green checkmark
- Test connections succeed

---

## Test 4: Resume Data Loading ✅

**Goal:** Verify resume data file is readable

**Steps:**
1. Click "Read Resume Data" node
2. Click "Test step"
3. Check output

**Expected:**
- ✅ JSON file loads
- ✅ Contains your name
- ✅ Contains skills array
- ✅ Contains experience array

**Pass Criteria:**
- File loads without errors
- Data structure is valid

---

## Test 5: Job Scraping (Apify) ✅

**Goal:** Scrape 5 LinkedIn jobs

**Steps:**
1. Click "Part 3: Scrape LinkedIn Jobs" node
2. Click "Test step"
3. Wait 30-60 seconds

**Expected:**
- ✅ Apify run starts
- ✅ Returns 5-10 job objects
- ✅ Each job has:
  - positionName
  - companyName
  - location
  - description
  - url

**Sample Output:**
```json
{
  "positionName": "AI Engineer",
  "companyName": "TechCorp",
  "location": "Tel Aviv, Israel",
  "description": "We are looking for...",
  "url": "https://linkedin.com/jobs/view/123"
}
```

**Pass Criteria:**
- At least 3 jobs returned
- All jobs have required fields
- Descriptions are not empty

---

## Test 6: AI Job Filtering (GPT-4o) ✅

**Goal:** Filter jobs by relevance

**Steps:**
1. Run workflow up to "Part 4: Filter Jobs with GPT-4o"
2. Check output from GPT-4o

**Expected:**
- ✅ Each job gets a relevance score (0-10)
- ✅ Reasoning provided
- ✅ Matching skills listed
- ✅ Missing skills listed

**Sample Output:**
```json
{
  "relevanceScore": 9,
  "reasoning": "Excellent match - requires Python, ML, AWS which candidate has",
  "matchingSkills": ["Python", "Machine Learning", "AWS"],
  "missingSkills": ["Java"]
}
```

**Pass Criteria:**
- Scores are between 0-10
- Reasoning makes sense
- At least 1 job scores >= 7

---

## Test 7: Resume Generation (GPT-4o) ✅

**Goal:** Generate custom HTML resume

**Steps:**
1. Run workflow through "Part 6: Generate Custom HTML Resume"
2. Check output

**Expected:**
- ✅ HTML code generated
- ✅ Contains your name
- ✅ Mentions the company name
- ✅ Highlights relevant skills for the job
- ✅ Professional formatting

**Sample Output:**
```html
<!DOCTYPE html>
<html>
<head>
  <style>
    body { font-family: Arial; }
    h1 { color: #333; }
  </style>
</head>
<body>
  <h1>Michael Fedorovsky</h1>
  <h2>AI Engineer</h2>
  <p>Experienced AI Engineer with 5+ years...</p>
  ...
</body>
</html>
```

**Pass Criteria:**
- Valid HTML
- Personalized for the job
- Not generic

---

## Test 8: Google Docs Creation ✅

**Goal:** Create resume Doc in Google Drive

**Steps:**
1. Run workflow through "Part 7: Create Google Doc"
2. Check Google Drive folder

**Expected:**
- ✅ New Doc appears in Drive folder
- ✅ Title: "Resume - [Company] - [Position]"
- ✅ Content matches generated HTML
- ✅ Formatting is readable

**Example:**
- Folder: `AI Job Bot Resumes`
- Doc: `Resume - TechCorp - AI Engineer`

**Pass Criteria:**
- Doc exists
- Content is correct
- Shared with service account

---

## Test 9: Google Sheets Logging ✅

**Goal:** Log job to tracking sheet

**Steps:**
1. Complete full workflow run
2. Open Google Sheet

**Expected:**
- ✅ New row added
- ✅ Contains:
  - Timestamp
  - Position
  - Company
  - Location
  - Relevance Score
  - Resume Doc URL
  - Job URL
  - Status = "Pending"

**Pass Criteria:**
- Row exists with all fields filled
- Links are clickable

---

## Test 10: End-to-End Workflow ✅

**Goal:** Run complete automation

**Steps:**
1. Click "Execute workflow" (not "Test workflow")
2. Wait for completion (2-5 minutes)
3. Check all outputs

**Expected Flow:**
```
Schedule Trigger
   ↓
Set Parameters
   ↓
Scrape LinkedIn (5-10 jobs)
   ↓
Merge with Resume Data
   ↓
Filter with GPT-4o (score 0-10)
   ↓
Keep jobs with score >= 7 (3-5 jobs)
   ↓
Generate Custom Resume for each
   ↓
Create Google Doc for each
   ↓
Log to Google Sheets
   ↓
Summarize Results
   ↓
Send Telegram Notification
```

**Pass Criteria:**
- ✅ Workflow completes without errors
- ✅ At least 1 resume created
- ✅ At least 1 job logged
- ✅ Execution time < 5 minutes

---

## Test 11: Resume Quality Check ✅

**Goal:** Verify resumes are actually customized

**Steps:**
1. Open 2 different resume Docs
2. Compare them

**Expected:**
- ✅ Different skills emphasized based on job
- ✅ Different summary based on company
- ✅ Different projects highlighted
- ✅ NOT identical

**Example:**
- Resume for AI job → emphasizes ML, Python, TensorFlow
- Resume for DevOps job → emphasizes K8s, Docker, AWS

**Pass Criteria:**
- Resumes are clearly customized
- Not generic copy-paste

---

## Test 12: Schedule Automation ✅

**Goal:** Set up daily automation

**Steps:**
1. Click "Schedule Trigger" node
2. Verify cron: `0 9 * * *` (9 AM daily)
3. Toggle workflow "Active"

**Expected:**
- ✅ Workflow shows "Active" badge
- ✅ Next execution time displayed
- ✅ Will run tomorrow at 9 AM automatically

**Pass Criteria:**
- Active toggle is ON
- Cron schedule is correct

---

## Final Verification Checklist

Before marking as complete:

- [ ] All 12 tests passed
- [ ] At least 3 jobs scraped
- [ ] At least 1 job scored >= 7
- [ ] At least 1 custom resume created
- [ ] Resume Doc exists in Google Drive
- [ ] Job logged in Google Sheets
- [ ] Resume quality is good (not generic)
- [ ] All API keys working
- [ ] No errors in workflow execution
- [ ] Workflow set to Active
- [ ] Till's personal data is correct

---

## Success Metrics

**You succeed when:**

✅ **Functional:**
- Workflow runs without errors
- Finds at least 1 relevant job
- Creates at least 1 customized resume
- Logs job to sheet

✅ **Quality:**
- Resumes are actually customized (not generic)
- Relevance filtering makes sense
- Skills match job requirements

✅ **Automation:**
- Runs daily at 9 AM
- No manual intervention needed
- Till gets resumes automatically

---

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| No jobs found | Check keywords/location in `.env` |
| GPT-4o timeout | Reduce `MAX_JOBS_PER_RUN` |
| Google permission error | Re-share folder/sheet with service account |
| Apify quota exceeded | Wait 24h or upgrade plan |
| Resume not customized | Adjust GPT-4o prompt in workflow |
| Workflow stuck | Check node execution logs |

---

## Post-Test Actions

After all tests pass:

1. ✅ Mark workflow as Active
2. ✅ Add Telegram notifications (optional)
3. ✅ Set up email alerts (optional)
4. ✅ Document any customizations
5. ✅ Let it run for 1 week
6. ✅ Review results and iterate

---

**Test Date:** ________________

**Tested By:** Till Thelet

**Overall Status:** ☐ PASS | ☐ FAIL | ☐ NEEDS WORK

**Notes:**
_______________________________________________
_______________________________________________
_______________________________________________
