# OpenClaw Client Acquisition System

**Fully automated client acquisition pipeline for OpenClaw Setup-as-a-Service business.**

Scrapes law firms & insurance companies → sends personalized cold emails → captures leads via intake form → auto-generates custom OpenClaw configs → tracks everything in a dashboard.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/Michaelunkai/openclaw-client-acquisition-system)

## 🌐 Live Demo

> **Deploy URL:** [Click "Deploy to Render" above — live in ~5 minutes, free forever]

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | Python 3.11, FastAPI, SQLAlchemy, APScheduler |
| Frontend | React 18, Vite, Tailwind CSS, Recharts |
| Database | SQLite (auto-created) |
| Deploy | Docker on Render (free tier) |
| Emails | Gmail SMTP SSL |
| Scraping | requests + BeautifulSoup4 |

## Features

- **Lead Scraper** — Auto-finds law firms & insurance companies via Google
- **Cold Outreach Engine** — Sends niche-specific emails daily (max 50/day)
- **Intake Form** — Public form at `/intake` for interested prospects
- **Auto-Onboarding** — Generates custom OpenClaw config per prospect's niche
- **Dashboard** — Funnel stats: leads → emailed → opened → prospects → clients → revenue
- **Template Editor** — Edit outreach emails per niche in the UI

## 🚀 Deploy to Render (Free, Always-On)

Click the button above. That's it. Render reads `render.yaml` and:
1. Builds React frontend (`npm run build`)
2. Installs Python deps
3. Runs FastAPI serving the built frontend
4. Assigns a free `.onrender.com` URL

**After deploy, add these env vars in Render dashboard:**
- `SMTP_USER` — your Gmail address
- `SMTP_PASS` — your Gmail App Password

## 💻 Run Locally

```powershell
cd openclaw-client-acquisition-system
.\start.ps1
```

Opens at `http://localhost:3000`

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `SMTP_USER` | Gmail address | required for email |
| `SMTP_PASS` | Gmail App Password | required for email |
| `SMTP_HOST` | SMTP server | `smtp.gmail.com` |
| `SMTP_PORT` | SMTP port | `465` |
| `MAX_DAILY_EMAILS` | Daily send limit | `50` |
| `DATABASE_URL` | DB connection string | SQLite auto |

## Project Structure

```
├── backend/          # FastAPI app
├── frontend/         # React/Vite app
├── templates/        # HTML email templates
├── configs/          # Niche base configs
├── Dockerfile        # Single-container build
├── render.yaml       # Render blueprint
└── start.ps1         # Local launcher
```

---

*Built with OpenClaw — automated client acquisition for the OpenClaw Setup-as-a-Service business model.*
