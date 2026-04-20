"""
APScheduler setup: Runs scraper daily at 9am, outreach daily at 10am.
"""
import logging
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.cron import CronTrigger

logger = logging.getLogger(__name__)

scheduler = BackgroundScheduler()


def scrape_job():
    """Daily scraping job."""
    logger.info("Running scheduled scrape job...")
    try:
        from scraper import run_scraper
        count = run_scraper()
        logger.info(f"Scheduled scrape complete: {count} new leads")
    except Exception as e:
        logger.error(f"Scheduled scrape failed: {e}")


def outreach_job():
    """Daily outreach email job."""
    logger.info("Running scheduled outreach job...")
    try:
        from outreach import run_outreach
        count = run_outreach()
        logger.info(f"Scheduled outreach complete: {count} emails sent")
    except Exception as e:
        logger.error(f"Scheduled outreach failed: {e}")


def start_scheduler():
    """Initialize and start the scheduler."""
    # Scrape leads daily at 9:00 AM UTC
    scheduler.add_job(
        scrape_job,
        CronTrigger(hour=9, minute=0),
        id="daily_scrape",
        replace_existing=True,
        name="Daily Lead Scraper",
    )

    # Send outreach emails daily at 10:00 AM UTC
    scheduler.add_job(
        outreach_job,
        CronTrigger(hour=10, minute=0),
        id="daily_outreach",
        replace_existing=True,
        name="Daily Outreach Emails",
    )

    scheduler.start()
    logger.info("Scheduler started. Jobs: daily_scrape @ 9am, daily_outreach @ 10am (UTC)")


def stop_scheduler():
    """Stop the scheduler gracefully."""
    if scheduler.running:
        scheduler.shutdown()
        logger.info("Scheduler stopped.")
