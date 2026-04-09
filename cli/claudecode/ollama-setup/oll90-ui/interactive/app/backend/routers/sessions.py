"""REST endpoints for session management"""
from fastapi import APIRouter, HTTPException

from db import db
from models import SessionCreate

router = APIRouter()


@router.get("/sessions")
async def list_sessions():
    return await db.list_sessions()


@router.post("/sessions")
async def create_session(body: SessionCreate = None):
    if body is None:
        body = SessionCreate()
    return await db.create_session(body.name, body.system_prompt)


@router.get("/sessions/{session_id}")
async def get_session(session_id: str):
    session = await db.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return session


@router.get("/sessions/{session_id}/messages")
async def get_messages(session_id: str):
    session = await db.get_session(session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
    return await db.get_messages(session_id)


@router.delete("/sessions/{session_id}")
async def delete_session(session_id: str):
    await db.delete_session(session_id)
    return {"status": "deleted"}


@router.patch("/sessions/{session_id}")
async def rename_session(session_id: str, body: dict):
    name = body.get("name")
    if not name:
        raise HTTPException(status_code=400, detail="name required")
    await db.rename_session(session_id, name)
    return {"status": "renamed"}
