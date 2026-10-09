from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api import patients, ecg, stats, eeg
from app.db.database import engine, Base
from app.db import models  # noqa: F401

app = FastAPI(title="MediVision Kit API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    # Create all tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

@app.get("/health")
async def health():
    return {"status": "ok", "version": "0.1.0", "country": "CM"}

app.include_router(patients.router, prefix="/api/patients", tags=["patients"])
app.include_router(ecg.router,      prefix="/api/ecg",      tags=["ecg"])
app.include_router(stats.router,    prefix="/api/stats",    tags=["stats"])
app.include_router(eeg.router,       prefix="/api/eeg",       tags=["eeg"])
