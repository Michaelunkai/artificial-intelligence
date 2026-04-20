import os
from pathlib import Path
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, DeclarativeBase

# In Docker/Render: data lives at /app/data
# Locally: data lives at ../data (relative to backend/)
_data_dir = Path(os.getenv("DATA_DIR", "")) or Path(__file__).parent.parent / "data"
_data_dir.mkdir(parents=True, exist_ok=True)

DATABASE_URL = os.getenv("DATABASE_URL", f"sqlite:///{_data_dir}/app.db")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {},
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_tables():
    from models import Lead, Prospect, Client  # noqa
    Base.metadata.create_all(bind=engine)
