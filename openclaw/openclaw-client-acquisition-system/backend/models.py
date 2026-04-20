from datetime import datetime
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text
from database import Base


class Lead(Base):
    __tablename__ = "leads"

    id = Column(Integer, primary_key=True, index=True)
    business_name = Column(String(255), nullable=False)
    email = Column(String(255), nullable=False, unique=True)
    phone = Column(String(50), nullable=True)
    website = Column(String(500), nullable=True)
    niche = Column(String(100), nullable=False, default="general")
    status = Column(String(50), nullable=False, default="new")  # new, emailed, opened, replied, converted
    created_at = Column(DateTime, default=datetime.utcnow)
    emailed_at = Column(DateTime, nullable=True)


class Prospect(Base):
    __tablename__ = "prospects"

    id = Column(Integer, primary_key=True, index=True)
    business_name = Column(String(255), nullable=False)
    industry = Column(String(100), nullable=False)
    pain_point = Column(Text, nullable=True)
    email = Column(String(255), nullable=False)
    phone = Column(String(50), nullable=True)
    schedule_call = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    onboarded = Column(Boolean, default=False)


class Client(Base):
    __tablename__ = "clients"

    id = Column(Integer, primary_key=True, index=True)
    business_name = Column(String(255), nullable=False)
    email = Column(String(255), nullable=False)
    niche = Column(String(100), nullable=False)
    config_path = Column(String(500), nullable=True)
    notes = Column(Text, nullable=True)
    revenue = Column(Float, default=0.0)
    created_at = Column(DateTime, default=datetime.utcnow)
