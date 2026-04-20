"""
Scraper module: Uses requests + BeautifulSoup to find law firm/insurance email contacts.
"""
import re
import time
import random
import logging
import os
from typing import List, Dict

import requests
from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/121.0.0.0 Safari/537.36"
    ),
    "Accept-Language": "en-US,en;q=0.9",
}

EMAIL_REGEX = re.compile(r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}")

SEARCH_QUERIES = {
    "law_firm": [
        '"law firm" "contact us" email',
        'attorney "contact" email site:il',
        '"law office" "email us" contact',
    ],
    "insurance": [
        '"insurance agency" "contact" email',
        '"insurance broker" "email" contact site:il',
        '"insurance company" "get a quote" email',
    ],
    "real_estate": [
        '"real estate agent" "contact" email',
        '"real estate agency" email contact site:il',
        '"realtor" "email us" contact',
    ],
}


def extract_emails_from_html(html: str) -> List[str]:
    """Extract email addresses from HTML content."""
    soup = BeautifulSoup(html, "html.parser")

    emails = set()

    # Find mailto links
    for tag in soup.find_all("a", href=True):
        href = tag["href"]
        if href.startswith("mailto:"):
            email = href[7:].split("?")[0].strip()
            if EMAIL_REGEX.match(email):
                emails.add(email.lower())

    # Find emails in text
    text = soup.get_text()
    found = EMAIL_REGEX.findall(text)
    for email in found:
        # Filter out common non-contact emails
        if not any(skip in email.lower() for skip in ["example.com", "test.", "noreply", "no-reply"]):
            emails.add(email.lower())

    return list(emails)


def scrape_website_for_contact(url: str) -> Dict:
    """Scrape a website's contact page for email addresses."""
    result = {"url": url, "emails": [], "business_name": "", "error": None}

    try:
        resp = requests.get(url, headers=HEADERS, timeout=10)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "html.parser")

        # Get business name from title
        title = soup.find("title")
        if title:
            result["business_name"] = title.get_text().strip()[:100]

        emails = extract_emails_from_html(resp.text)

        # Try to find contact page
        contact_links = []
        for a in soup.find_all("a", href=True):
            text = a.get_text().lower()
            href = a["href"].lower()
            if "contact" in text or "contact" in href:
                contact_links.append(a["href"])

        for contact_href in contact_links[:3]:
            try:
                if contact_href.startswith("/"):
                    from urllib.parse import urlparse
                    parsed = urlparse(url)
                    contact_url = f"{parsed.scheme}://{parsed.netloc}{contact_href}"
                elif contact_href.startswith("http"):
                    contact_url = contact_href
                else:
                    continue

                time.sleep(random.uniform(0.5, 1.5))
                contact_resp = requests.get(contact_url, headers=HEADERS, timeout=10)
                contact_emails = extract_emails_from_html(contact_resp.text)
                emails.extend(contact_emails)
            except Exception:
                pass

        result["emails"] = list(set(emails))

    except Exception as e:
        result["error"] = str(e)
        logger.warning(f"Error scraping {url}: {e}")

    return result


def scrape_google_for_leads(niche: str, max_results: int = 20) -> List[Dict]:
    """
    Scrape Google search results for business contacts.
    Returns list of lead dicts.
    """
    queries = SEARCH_QUERIES.get(niche, SEARCH_QUERIES["law_firm"])
    leads = []

    for query in queries[:2]:  # Limit to 2 queries per niche to avoid rate limits
        try:
            search_url = f"https://www.google.com/search?q={requests.utils.quote(query)}&num=20"
            time.sleep(random.uniform(1.0, 2.0))

            resp = requests.get(search_url, headers=HEADERS, timeout=15)
            soup = BeautifulSoup(resp.text, "html.parser")

            # Extract result links
            for result in soup.select("div.g"):
                link_tag = result.find("a", href=True)
                if not link_tag:
                    continue
                link = link_tag["href"]
                if not link.startswith("http"):
                    continue

                # Try to get business name from result title
                title_tag = result.find("h3")
                business_name = title_tag.get_text().strip() if title_tag else ""

                # Extract emails from the snippet
                snippet_tag = result.find("div", class_=re.compile("VwiC3b|s3v9rd"))
                snippet = snippet_tag.get_text() if snippet_tag else ""
                emails_in_snippet = EMAIL_REGEX.findall(snippet)

                if emails_in_snippet:
                    for email in emails_in_snippet:
                        if not any(skip in email for skip in ["example.com", "noreply"]):
                            leads.append({
                                "business_name": business_name,
                                "email": email.lower(),
                                "website": link,
                                "niche": niche,
                                "status": "new",
                            })

                if len(leads) >= max_results:
                    break

            logger.info(f"Scraped query '{query}': found {len(leads)} leads so far")

        except Exception as e:
            logger.error(f"Error scraping Google for '{query}': {e}")

        time.sleep(random.uniform(2.0, 4.0))

    return leads[:max_results]


def run_scraper(db=None) -> int:
    """
    Main scraper entry point. Scrapes all niches and saves leads to DB.
    Returns count of new leads added.
    """
    if db is None:
        from database import SessionLocal
        db = SessionLocal()
        close_db = True
    else:
        close_db = False

    from models import Lead
    from sqlalchemy.exc import IntegrityError

    total_new = 0

    for niche in ["law_firm", "insurance", "real_estate"]:
        logger.info(f"Scraping niche: {niche}")
        leads = scrape_google_for_leads(niche, max_results=10)

        for lead_data in leads:
            try:
                # Check if email already exists
                existing = db.query(Lead).filter(Lead.email == lead_data["email"]).first()
                if existing:
                    continue

                lead = Lead(**lead_data)
                db.add(lead)
                db.commit()
                total_new += 1
            except IntegrityError:
                db.rollback()
            except Exception as e:
                db.rollback()
                logger.error(f"Error saving lead: {e}")

    if close_db:
        db.close()

    logger.info(f"Scraper complete. Added {total_new} new leads.")
    return total_new
