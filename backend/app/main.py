from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.api import patients, ecg, stats, eeg, imaging, auth, cases
from app.core.config import settings
from app.db.migrations import run_migrations

app = FastAPI(title="MediVision Kit API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[origin.strip() for origin in settings.CORS_ORIGINS.split(",") if origin.strip()],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup():
    if not settings.DEBUG and not settings.SECRET_KEY:
        raise RuntimeError("SECRET_KEY must be set when DEBUG=false")
    await run_migrations()

@app.get("/health")
async def health():
    return {"status": "ok", "version": "0.1.0", "country": "CM"}

app.include_router(patients.router, prefix="/api/patients", tags=["patients"])
app.include_router(ecg.router,      prefix="/api/ecg",      tags=["ecg"])
app.include_router(stats.router,    prefix="/api/stats",    tags=["stats"])
app.include_router(eeg.router,       prefix="/api/eeg",       tags=["eeg"])
app.include_router(imaging.router,   prefix="/api/imaging",   tags=["imaging"])
app.include_router(auth.router,       prefix="/api/auth",      tags=["auth"])
app.include_router(cases.router,      prefix="/api/cases",     tags=["cases"])
