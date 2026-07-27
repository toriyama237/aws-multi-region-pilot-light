from contextlib import asynccontextmanager
from uuid import UUID

from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field

from . import __version__
from .config import load_settings
from .db import Database


class NoteIn(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    body: str = Field(default="", max_length=10_000)


class NoteOut(NoteIn):
    id: UUID
    created_at: str
    updated_at: str


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = load_settings()
    db = Database(settings)
    db.open()
    app.state.settings = settings
    app.state.db = db
    yield
    db.close()


app = FastAPI(title="Notes API", version=__version__, lifespan=lifespan)


@app.middleware("http")
async def serving_region_header(request: Request, call_next):
    """Tag every response with the region that served it.

    During a failover drill this is the fastest way to prove, from the
    client side, that traffic moved from the primary to the secondary
    region without touching the URL.
    """
    response: Response = await call_next(request)
    response.headers["X-Serving-Region"] = request.app.state.settings.region
    return response


@app.get("/healthz")
async def liveness() -> dict:
    """Process-level liveness, never touches the database."""
    return {"status": "ok", "version": __version__}


@app.get("/health")
async def readiness(request: Request) -> dict:
    """Readiness probe wired to the ALB target group and, through the
    ALB, to the Route 53 health check.

    It fails when the database is unreachable, which is exactly the
    signal we want to propagate up to DNS failover: an instance that
    cannot reach its data layer should not receive traffic.
    """
    if not request.app.state.db.ping():
        raise HTTPException(status_code=503, detail="database unreachable")
    return {"status": "ok", "region": request.app.state.settings.region}


@app.post("/notes", response_model=NoteOut, status_code=201)
async def create_note(note: NoteIn, request: Request):
    with request.app.state.db.connection() as conn:
        row = conn.execute(
            "INSERT INTO notes (title, body) VALUES (%s, %s) "
            "RETURNING id, title, body, created_at::text, updated_at::text",
            (note.title, note.body),
        ).fetchone()
    return row


@app.get("/notes", response_model=list[NoteOut])
async def list_notes(request: Request, limit: int = 50, offset: int = 0):
    limit = max(1, min(limit, 200))
    with request.app.state.db.connection() as conn:
        rows = conn.execute(
            "SELECT id, title, body, created_at::text, updated_at::text "
            "FROM notes ORDER BY created_at DESC LIMIT %s OFFSET %s",
            (limit, max(0, offset)),
        ).fetchall()
    return rows


@app.get("/notes/{note_id}", response_model=NoteOut)
async def get_note(note_id: UUID, request: Request):
    with request.app.state.db.connection() as conn:
        row = conn.execute(
            "SELECT id, title, body, created_at::text, updated_at::text "
            "FROM notes WHERE id = %s",
            (note_id,),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="note not found")
    return row


@app.put("/notes/{note_id}", response_model=NoteOut)
async def update_note(note_id: UUID, note: NoteIn, request: Request):
    with request.app.state.db.connection() as conn:
        row = conn.execute(
            "UPDATE notes SET title = %s, body = %s, updated_at = now() "
            "WHERE id = %s "
            "RETURNING id, title, body, created_at::text, updated_at::text",
            (note.title, note.body, note_id),
        ).fetchone()
    if row is None:
        raise HTTPException(status_code=404, detail="note not found")
    return row


@app.delete("/notes/{note_id}", status_code=204)
async def delete_note(note_id: UUID, request: Request):
    with request.app.state.db.connection() as conn:
        deleted = conn.execute(
            "DELETE FROM notes WHERE id = %s RETURNING id", (note_id,)
        ).fetchone()
    if deleted is None:
        raise HTTPException(status_code=404, detail="note not found")
