from typing import List, Optional
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from pydantic import BaseModel

from database import get_db
from models import Client

router = APIRouter(prefix="/api/clients", tags=["clients"])


class ClientUpdate(BaseModel):
    notes: Optional[str] = None
    revenue: Optional[float] = None
    niche: Optional[str] = None


class ClientOut(BaseModel):
    id: int
    business_name: str
    email: str
    niche: str
    config_path: Optional[str]
    notes: Optional[str]
    revenue: float
    created_at: datetime

    class Config:
        from_attributes = True


@router.get("/", response_model=List[ClientOut])
def get_clients(
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db),
):
    return db.query(Client).offset(skip).limit(limit).all()


@router.get("/{client_id}", response_model=ClientOut)
def get_client(client_id: int, db: Session = Depends(get_db)):
    client = db.query(Client).filter(Client.id == client_id).first()
    if not client:
        raise HTTPException(status_code=404, detail="Client not found")
    return client


@router.patch("/{client_id}", response_model=ClientOut)
def update_client(client_id: int, update: ClientUpdate, db: Session = Depends(get_db)):
    client = db.query(Client).filter(Client.id == client_id).first()
    if not client:
        raise HTTPException(status_code=404, detail="Client not found")
    for field, value in update.model_dump(exclude_none=True).items():
        setattr(client, field, value)
    db.commit()
    db.refresh(client)
    return client
