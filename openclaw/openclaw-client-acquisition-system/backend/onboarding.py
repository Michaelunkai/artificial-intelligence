"""
Onboarding module: Generates custom OpenClaw workspace configs and sends welcome emails.
"""
import os
import json
import logging
from pathlib import Path
from datetime import datetime

logger = logging.getLogger(__name__)

CONFIGS_DIR = Path(__file__).parent.parent / "configs"
TEMPLATES_DIR = Path(__file__).parent.parent / "templates" / "onboarding"
DATA_DIR = Path(__file__).parent.parent / "data" / "clients"

NICHE_MAP = {
    "Law Firm": "law_firm",
    "Insurance": "insurance",
    "Real Estate": "real_estate",
    "Other": "law_firm",  # Default to law_firm config for "Other"
}


def load_base_config(niche_key: str) -> dict:
    """Load base configuration for a niche."""
    config_file = CONFIGS_DIR / f"{niche_key}_base.json"
    if not config_file.exists():
        config_file = CONFIGS_DIR / "law_firm_base.json"
    with open(config_file, "r") as f:
        return json.load(f)


def generate_client_config(prospect: dict) -> str:
    """
    Generate a custom OpenClaw config for a prospect.
    Saves to data/clients/{business_name}/config.json
    Returns the path to the generated config.
    """
    industry = prospect.get("industry", "Other")
    niche_key = NICHE_MAP.get(industry, "law_firm")

    config = load_base_config(niche_key)
    config["client"] = {
        "business_name": prospect.get("business_name", ""),
        "email": prospect.get("email", ""),
        "industry": industry,
        "pain_points": prospect.get("pain_point", ""),
        "onboarded_at": datetime.utcnow().isoformat(),
    }
    config["niche"] = niche_key

    # Create client directory
    safe_name = "".join(c if c.isalnum() or c in "-_" else "_" for c in prospect.get("business_name", "client"))
    client_dir = DATA_DIR / safe_name
    client_dir.mkdir(parents=True, exist_ok=True)

    config_path = client_dir / "config.json"
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)

    logger.info(f"Generated config for {prospect.get('business_name')} at {config_path}")
    return str(config_path)


def send_welcome_email(prospect: dict, config_path: str) -> bool:
    """Send welcome email with attached config to the prospect."""
    try:
        template_file = TEMPLATES_DIR / "welcome.html"
        html = template_file.read_text(encoding="utf-8")
        html = html.replace("{{business_name}}", prospect.get("business_name", "there"))
        html = html.replace("{{industry}}", prospect.get("industry", "your industry"))
        html = html.replace("{{email}}", prospect.get("email", ""))

        subject = f"Welcome to OpenClaw — Your Custom Setup is Ready, {prospect.get('business_name', '')}!"

        from outreach import send_email
        return send_email(
            to_email=prospect.get("email", ""),
            to_name=prospect.get("business_name", ""),
            subject=subject,
            html_body=html,
            attachments=[(config_path, "openclaw-config.json")],
        )
    except Exception as e:
        logger.error(f"Error sending welcome email: {e}")
        return False


def onboard_prospect(prospect: dict, db=None) -> bool:
    """
    Full onboarding flow:
    1. Generate config
    2. Send welcome email
    3. Create client record
    4. Mark prospect as onboarded
    """
    try:
        config_path = generate_client_config(prospect)
        email_sent = send_welcome_email(prospect, config_path)

        if db:
            from models import Client, Prospect
            from sqlalchemy.orm import Session

            # Create client record
            industry = prospect.get("industry", "Other")
            niche_key = NICHE_MAP.get(industry, "general")

            client = Client(
                business_name=prospect.get("business_name", ""),
                email=prospect.get("email", ""),
                niche=niche_key,
                config_path=config_path,
                notes=prospect.get("pain_point", ""),
                revenue=0.0,
            )
            db.add(client)

            # Mark prospect as onboarded
            if "id" in prospect:
                db_prospect = db.query(Prospect).filter(Prospect.id == prospect["id"]).first()
                if db_prospect:
                    db_prospect.onboarded = True

            db.commit()

        return True

    except Exception as e:
        logger.error(f"Onboarding failed for {prospect.get('business_name')}: {e}")
        return False
