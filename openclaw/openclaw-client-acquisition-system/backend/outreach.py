"""
Outreach module: Sends cold emails to leads via Gmail SMTP SSL.
"""
import os
import smtplib
import logging
from datetime import datetime, date
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "465"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASS = os.getenv("SMTP_PASS", "")
FROM_NAME = os.getenv("FROM_NAME", "OpenClaw Team")
MAX_DAILY_EMAILS = int(os.getenv("MAX_DAILY_EMAILS", "50"))

TEMPLATES_DIR = Path(__file__).parent.parent / "templates" / "outreach"

SUBJECTS = {
    "law_firm": "AI Automation for Law Firms — Free Setup Demo",
    "insurance": "Automate Your Insurance Workflow — No Code Required",
    "real_estate": "AI Tools for Real Estate Professionals",
    "general": "Automate Your Business with AI — Free Setup Demo",
}


def load_template(niche: str) -> str:
    """Load HTML email template for given niche."""
    template_file = TEMPLATES_DIR / f"{niche}.html"
    if not template_file.exists():
        template_file = TEMPLATES_DIR / "law_firm.html"
    return template_file.read_text(encoding="utf-8")


def send_email(
    to_email: str,
    to_name: str,
    subject: str,
    html_body: str,
    attachments: Optional[list] = None,
) -> bool:
    """Send an email via Gmail SMTP SSL. Returns True on success."""
    if not SMTP_USER or not SMTP_PASS:
        logger.warning("SMTP credentials not configured. Email not sent.")
        return False

    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = f"{FROM_NAME} <{SMTP_USER}>"
        msg["To"] = to_email

        msg.attach(MIMEText(html_body, "html"))

        if attachments:
            from email.mime.base import MIMEBase
            from email import encoders
            mixed = MIMEMultipart("mixed")
            mixed.attach(msg)
            for filepath, filename in attachments:
                with open(filepath, "rb") as f:
                    part = MIMEBase("application", "octet-stream")
                    part.set_payload(f.read())
                    encoders.encode_base64(part)
                    part.add_header("Content-Disposition", f'attachment; filename="{filename}"')
                    mixed.attach(part)
            msg = mixed

        with smtplib.SMTP_SSL(SMTP_HOST, SMTP_PORT) as server:
            server.login(SMTP_USER, SMTP_PASS)
            server.sendmail(SMTP_USER, to_email, msg.as_string())

        logger.info(f"Email sent to {to_email}")
        return True

    except Exception as e:
        logger.error(f"Failed to send email to {to_email}: {e}")
        return False


def count_emails_sent_today(db) -> int:
    """Count emails sent today."""
    from models import Lead
    today_start = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    return db.query(Lead).filter(
        Lead.status != "new",
        Lead.emailed_at >= today_start,
    ).count()


def run_outreach(db=None) -> int:
    """
    Main outreach entry point. Sends emails to all 'new' leads up to daily limit.
    Returns count of emails sent.
    """
    if db is None:
        from database import SessionLocal
        db = SessionLocal()
        close_db = True
    else:
        close_db = False

    from models import Lead

    sent_today = count_emails_sent_today(db)
    remaining = MAX_DAILY_EMAILS - sent_today

    if remaining <= 0:
        logger.info(f"Daily email limit ({MAX_DAILY_EMAILS}) reached.")
        if close_db:
            db.close()
        return 0

    new_leads = (
        db.query(Lead)
        .filter(Lead.status == "new")
        .limit(remaining)
        .all()
    )

    sent_count = 0
    for lead in new_leads:
        template = load_template(lead.niche)
        # Personalize template
        html = template.replace("{{business_name}}", lead.business_name or "there")
        subject = SUBJECTS.get(lead.niche, SUBJECTS["general"])

        success = send_email(
            to_email=lead.email,
            to_name=lead.business_name or "",
            subject=subject,
            html_body=html,
        )

        if success:
            lead.status = "emailed"
            lead.emailed_at = datetime.utcnow()
            db.commit()
            sent_count += 1

    if close_db:
        db.close()

    logger.info(f"Outreach complete. Sent {sent_count} emails.")
    return sent_count
