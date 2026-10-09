import json
from datetime import date

from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.database import get_db
from app.db.models import Patient, Rapport

router = APIRouter()


def _is_eeg(raw_json: str | None) -> bool:
    raw = (raw_json or "").lower()
    return '"modalite": "eeg"' in raw or '"nb_canaux"' in raw


def _is_ecg(raw_json: str | None) -> bool:
    return not _is_eeg(raw_json)


@router.get("/")
async def get_stats(db: AsyncSession = Depends(get_db)):
    total_patients = (await db.execute(
        select(func.count()).select_from(Patient)
    )).scalar()

    all_reports = (await db.execute(
        select(Rapport)
    )).scalars().all()

    today = date.today().isoformat()

    ecg_reports = [r for r in all_reports if _is_ecg(r.raw_json)]
    eeg_reports = [r for r in all_reports if _is_eeg(r.raw_json)]

    total_ecgs = len(ecg_reports)
    total_eegs = len(eeg_reports)

    ecgs_today = sum(
        1 for r in ecg_reports
        if r.created_at and r.created_at.date().isoformat() == today
    )
    eegs_today = sum(
        1 for r in eeg_reports
        if r.created_at and r.created_at.date().isoformat() == today
    )

    review_queue = sum(
        1 for r in all_reports
        if (r.review_level or '').upper() != 'AUTO'
    )

    confidences = [float(r.confidence) for r in all_reports if r.confidence is not None]
    avg_conf = sum(confidences) / len(confidences) if confidences else 0.0

    def build_daily(reports):
        counts = {}
        for r in reports:
            if not r.created_at:
                continue
            day = r.created_at.date().isoformat()
            counts[day] = counts.get(day, 0) + 1
        days = [{"day": k, "count": v} for k, v in sorted(counts.items(), reverse=True)[:7]]
        days.reverse()
        return days

    def build_dist(reports):
        counts = {}
        for r in reports:
            label = (r.diagnostic or "N/A").strip() or "N/A"
            counts[label] = counts.get(label, 0) + 1
        items = [{"label": k, "count": v} for k, v in sorted(counts.items(), key=lambda x: x[1], reverse=True)]
        return items

    daily_ecgs = build_daily(ecg_reports)
    daily_eegs = build_daily(eeg_reports)

    ecg_class_distribution = build_dist(ecg_reports)
    eeg_class_distribution = build_dist(eeg_reports)

    return {
        "total_patients": total_patients or 0,
        "total_ecgs": total_ecgs,
        "ecgs_today": ecgs_today,
        "review_queue": review_queue,
        "avg_confidence": round(float(avg_conf or 0), 3),
        "daily_ecgs": daily_ecgs,
        "ecg_class_distribution": ecg_class_distribution,
        "class_distribution": ecg_class_distribution,
        "total_eegs": total_eegs,
        "eegs_today": eegs_today,
        "daily_eegs": daily_eegs,
        "eeg_class_distribution": eeg_class_distribution,
    }


@router.get("/ecgs")
async def list_all_ecgs(db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(
        select(Rapport).order_by(Rapport.created_at.desc())
    )).scalars().all()
    rows = [r for r in rows if _is_ecg(r.raw_json)]
    return [_rapport_summary(r) for r in rows]


@router.get("/ecgs/today")
async def list_ecgs_today(db: AsyncSession = Depends(get_db)):
    today = date.today().isoformat()
    rows = (await db.execute(
        select(Rapport).order_by(Rapport.created_at.desc())
    )).scalars().all()
    rows = [
        r for r in rows
        if _is_ecg(r.raw_json) and r.created_at and r.created_at.date().isoformat() == today
    ]
    return [_rapport_summary(r) for r in rows]


@router.get("/ecgs/revision")
async def list_revision_queue(db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(
        select(Rapport).order_by(Rapport.created_at.desc())
    )).scalars().all()
    rows = [
        r for r in rows
        if _is_ecg(r.raw_json) and (r.review_level or '').upper() != 'AUTO'
    ]
    return [_rapport_summary(r) for r in rows]


@router.get("/eegs")
async def list_all_eegs(db: AsyncSession = Depends(get_db)):
    rows = (await db.execute(
        select(Rapport).order_by(Rapport.created_at.desc())
    )).scalars().all()
    rows = [r for r in rows if _is_eeg(r.raw_json)]
    return [_rapport_summary(r) for r in rows]


@router.get("/eegs/today")
async def list_eegs_today(db: AsyncSession = Depends(get_db)):
    today = date.today().isoformat()
    rows = (await db.execute(
        select(Rapport).order_by(Rapport.created_at.desc())
    )).scalars().all()
    rows = [
        r for r in rows
        if _is_eeg(r.raw_json) and r.created_at and r.created_at.date().isoformat() == today
    ]
    return [_rapport_summary(r) for r in rows]


def _rapport_summary(r: Rapport) -> dict:
    try:
        raw = json.loads(r.raw_json or '{}')
    except Exception:
        raw = {}

    ctx = raw.get('patient_context', {})
    return {
        "report_id": r.id,
        "patient_id": r.patient_id,
        "patient_name": raw.get('patient_name', r.patient_name or r.patient_id),
        "diagnostic": r.diagnostic,
        "cim11_code": r.cim11_code,
        "confidence": r.confidence,
        "review_level": r.review_level,
        "created_at": r.created_at.isoformat() if r.created_at else '',
        "age": ctx.get('age', raw.get('age', '—')),
        "sexe": ctx.get('sexe', raw.get('sexe', '—')),
        "raw_json": raw,
    }
