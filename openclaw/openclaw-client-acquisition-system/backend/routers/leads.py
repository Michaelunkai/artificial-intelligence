from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from pydantic import BaseModel

from database import get_db
from models import Lead

router = APIRouter(prefix="/api/leads", tags=["leads"])


class LeadCreate(BaseModel):
    business_name: str
    email: str
    phone: Optional[str] = None
    website: Optional[str] = None
    niche: str = "general"
    status: str = "new"


class LeadUpdate(BaseModel):
    business_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    website: Optional[str] = None
    niche: Optional[str] = None
    status: Optional[str] = None


class LeadOut(BaseModel):
    id: int
    business_name: str
    email: str
    phone: Optional[str]
    website: Optional[str]
    niche: str
    status: str
    created_at: datetime
    emailed_at: Optional[datetime]

    class Config:
        from_attributes = True


@router.get("/", response_model=List[LeadOut])
def get_leads(
    status: Optional[str] = Query(None),
    niche: Optional[str] = Query(None),
    search: Optional[str] = Query(None),
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
):
    query = db.query(Lead)
    if status:
        query = query.filter(Lead.status == status)
    if niche:
        query = query.filter(Lead.niche == niche)
    if search:
        query = query.filter(
            Lead.business_name.ilike(f"%{search}%") | Lead.email.ilike(f"%{search}%")
        )
    return query.offset(skip).limit(limit).all()


@router.post("/", response_model=LeadOut, status_code=201)
def create_lead(lead: LeadCreate, db: Session = Depends(get_db)):
    existing = db.query(Lead).filter(Lead.email == lead.email).first()
    if existing:
        raise HTTPException(status_code=409, detail="Lead with this email already exists")
    db_lead = Lead(**lead.model_dump())
    db.add(db_lead)
    db.commit()
    db.refresh(db_lead)
    return db_lead


@router.patch("/{lead_id}", response_model=LeadOut)
def update_lead(lead_id: int, update: LeadUpdate, db: Session = Depends(get_db)):
    lead = db.query(Lead).filter(Lead.id == lead_id).first()
    if not lead:
        raise HTTPException(status_code=404, detail="Lead not found")
    for field, value in update.model_dump(exclude_none=True).items():
        setattr(lead, field, value)
    db.commit()
    db.refresh(lead)
    return lead


@router.delete("/{lead_id}", status_code=204)
def delete_lead(lead_id: int, db: Session = Depends(get_db)):
    lead = db.query(Lead).filter(Lead.id == lead_id).first()
    if not lead:
        raise HTTPException(status_code=404, detail="Lead not found")
    db.delete(lead)
    db.commit()
