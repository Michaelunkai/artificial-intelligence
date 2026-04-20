"""
OpenClaw Client Acquisition System — FastAPI Backend
Serves the React frontend as static files from /frontend/dist
"""
import os
import logging
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from database import create_tables, get_db
from scheduler import start_scheduler, stop_scheduler

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
)
logger = logging.getLogger(__name__)

# Resolve frontend/dist — works both locally and in Docker/Render
BASE_DIR = Path(__file__).parent
# Try relative to backend: ../frontend/dist (local dev)
# Then try /app/frontend/dist (Docker)
_candidates = [
    BASE_DIR.parent / "frontend" / "dist",
    Path("/app/frontend/dist"),
]
FRONTEND_DIST = next((p for p in _candidates if p.exists()), None)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting OpenClaw Client Acquisition System...")
    create_tables()
    start_scheduler()
    yield
    stop_scheduler()
    logger.info("Shutdown complete.")


app = FastAPI(
    title="OpenClaw Client Acquisition API",
    description="Automated client acquisition pipeline for OpenClaw",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/api/docs",
    redoc_url="/api/redoc",
    openapi_url="/api/openapi.json",
)

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount routers
from routers import leads, prospects, clients
app.include_router(leads.router)
app.include_router(prospects.router)
app.include_router(clients.router)


@app.get("/health")
def health():
    return {"status": "healthy", "timestamp": datetime.utcnow().isoformat()}


@app.get("/api/stats")
def get_stats(db: Session = Depends(get_db)):
    from models import Lead, Prospect, Client

    total_leads = db.query(Lead).count()
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    emails_sent_today = db.query(Lead).filter(
        Lead.emailed_at >= today_start
    ).count()
    emailed_total = db.query(Lead).filter(Lead.status != "new").count()
    opened = db.query(Lead).filter(Lead.status.in_(["opened", "replied", "converted"])).count()
    open_rate = round((opened / emailed_total * 100), 1) if emailed_total > 0 else 0.0
    total_prospects = db.query(Prospect).count()
    total_clients = db.query(Client).count()
    revenue_result = db.query(Client).all()
    estimated_revenue = sum(c.revenue for c in revenue_result)

    return {
        "total_leads": total_leads,
        "emails_sent_today": emails_sent_today,
        "open_rate": open_rate,
        "total_prospects": total_prospects,
        "total_clients": total_clients,
        "estimated_revenue": estimated_revenue,
    }


@app.post("/api/scrape/trigger")
def trigger_scrape():
    from scraper import run_scraper
    count = run_scraper()
    return {"message": f"Scrape complete. Added {count} new leads."}


@app.post("/api/outreach/trigger")
def trigger_outreach():
    from outreach import run_outreach
    count = run_outreach()
    return {"message": f"Outreach complete. Sent {count} emails."}


# Serve React frontend (must be LAST — catches all non-API routes)
if FRONTEND_DIST and FRONTEND_DIST.exists():
    assets_dir = FRONTEND_DIST / "assets"
    if assets_dir.exists():
        app.mount("/assets", StaticFiles(directory=str(assets_dir)), name="assets")

    @app.get("/")
    def root():
        return FileResponse(str(FRONTEND_DIST / "index.html"))

    @app.get("/{full_path:path}")
    def serve_spa(full_path: str):
        """Catch-all: serve React SPA index.html for all non-API routes."""
        # Don't catch API routes
        if full_path.startswith("api/"):
            from fastapi import HTTPException
            raise HTTPException(status_code=404)
        return FileResponse(str(FRONTEND_DIST / "index.html"))
else:
    logger.warning("Frontend dist not found — API-only mode")

    @app.get("/")
    def root():
        return {
            "message": "OpenClaw Client Acquisition API",
            "version": "1.0.0",
            "note": "Frontend not built. Run: cd frontend && npm install && npm run build"
        }
