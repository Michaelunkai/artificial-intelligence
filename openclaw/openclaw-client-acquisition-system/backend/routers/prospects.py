from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks
from sqlalchemy.orm import Session
from pydantic import BaseModel

from database import get_db
from models import Prospect

router = APIRouter(prefix="/api/prospects", tags=["prospects"])


class ProspectCreate(BaseModel):
    business_name: str
    industry: str
    pain_point: Optional[str] = None
    email: str
    phone: Optional[str] = None
    schedule_call: bool = False


class ProspectOut(BaseModel):
    id: int
    business_name: str
    industry: str
    pain_point: Optional[str]
    email: str
    phone: Optional[str]
    schedule_call: bool
    created_at: datetime
    onboarded: bool

    class Config:
        from_attributes = True


def run_onboarding_background(prospect_dict: dict, prospect_id: int, db_url: str):
    """Run onboarding in background thread."""
    from sqlalchemy import create_engine
    from sqlalchemy.orm import sessionmaker
    engine = create_engine(db_url, connect_args={"check_same_thread": False})
    Session = sessionmaker(bind=engine)
    db = Session()
    try:
        from onboarding import onboard_prospect
        prospect_dict["id"] = prospect_id
        onboard_prospect(prospect_dict, db=db)
    finally:
        db.close()


@router.get("/", response_model=List[ProspectOut])
def get_prospects(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
):
    return db.query(Prospect).offset(skip).limit(limit).all()


@router.post("/", response_model=ProspectOut, status_code=201)
def create_prospect(
    prospect: ProspectCreate,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
):
    db_prospect = Prospect(**prospect.model_dump())
    db.add(db_prospect)
    db.commit()
    db.refresh(db_prospect)

    # Trigger onboarding in background
    import os
    db_url = os.getenv("DATABASE_URL", "sqlite:///./data/app.db")
    prospect_dict = prospect.model_dump()
    background_tasks.add_task(
        run_onboarding_background,
        prospect_dict,
        db_prospect.id,
        db_url,
    )

    return db_prospect


@router.get("/{prospect_id}", response_model=ProspectOut)
def get_prospect(prospect_id: int, db: Session = Depends(get_db)):
    prospect = db.query(Prospect).filter(Prospect.id == prospect_id).first()
    if not prospect:
        raise HTTPException(status_code=404, detail="Prospect not found")
    return prospect
