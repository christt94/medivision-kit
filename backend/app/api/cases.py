import json
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import get_current_user
from app.db.database import get_db
from app.db.models import AuditEvent, CaseStudyLink, ClinicalCase, ImagingStudy, Rapport, ReviewSignoff, User
from app.schemas.cases import CaseCreate, ReviewSignoffCreate, StudyLinkCreate

router = APIRouter()
VALID_PRIORITIES = {"ROUTINE", "URGENT", "STAT"}
VALID_STUDY_TYPES = {"ECG", "EEG", "IMAGING"}
VALID_DECISIONS = {"APPROVED", "REJECTED", "CHANGES_REQUESTED"}


def _case_dict(case: ClinicalCase) -> dict:
    return {
        "id": case.id, "patient_id": case.patient_id, "title": case.title,
        "indication": case.indication or "", "priority": case.priority,
        "status": case.status, "created_by": case.created_by,
        "assigned_to": case.assigned_to,
        "created_at": case.created_at.isoformat() if case.created_at else "",
        "updated_at": case.updated_at.isoformat() if case.updated_at else "",
        "closed_at": case.closed_at.isoformat() if case.closed_at else None,
    }


async def _audit(db, actor, action, resource_type, resource_id, details=None):
    db.add(AuditEvent(
        actor_user_id=actor.id if actor else None, action=action,
        resource_type=resource_type, resource_id=resource_id,
        details_json=json.dumps(details or {}, ensure_ascii=False),
    ))


@router.post("")
async def create_case(data: CaseCreate, db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    priority = data.priority.strip().upper()
    if priority not in VALID_PRIORITIES:
        raise HTTPException(400, detail="Priorité non valide")
    case = ClinicalCase(
        patient_id=data.patient_id.strip(), title=data.title.strip(),
        indication=data.indication.strip(), priority=priority,
        created_by=user.id, assigned_to=data.assigned_to,
    )
    db.add(case)
    await db.flush()
    await _audit(db, user, "CASE_CREATED", "clinical_case", case.id, {"patient_id": case.patient_id})
    await db.commit()
    await db.refresh(case)
    return _case_dict(case)


@router.get("")
async def list_cases(status: str | None = None, patient_id: str | None = None,
                     db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    query = select(ClinicalCase).order_by(ClinicalCase.updated_at.desc())
    if status:
        query = query.where(ClinicalCase.status == status.strip().upper())
    if patient_id:
        query = query.where(ClinicalCase.patient_id == patient_id.strip())
    rows = (await db.execute(query)).scalars().all()
    return [_case_dict(case) for case in rows]


@router.get("/{case_id}")
async def get_case(case_id: str, db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    case = await db.get(ClinicalCase, case_id)
    if not case:
        raise HTTPException(404, detail="Dossier clinique introuvable")
    links = (await db.execute(select(CaseStudyLink).where(
        CaseStudyLink.case_id == case_id).order_by(CaseStudyLink.created_at))).scalars().all()
    signoffs = (await db.execute(select(ReviewSignoff).where(
        ReviewSignoff.case_id == case_id).order_by(ReviewSignoff.created_at))).scalars().all()
    return {
        **_case_dict(case),
        "studies": [{"id": x.id, "study_type": x.study_type, "study_id": x.study_id, "linked_by": x.linked_by} for x in links],
        "signoffs": [{"id": x.id, "study_type": x.study_type, "study_id": x.study_id,
                      "reviewer_id": x.reviewer_id, "decision": x.decision,
                      "notes": x.notes or "", "created_at": x.created_at.isoformat() if x.created_at else ""} for x in signoffs],
    }


@router.post("/{case_id}/studies")
async def link_study(case_id: str, data: StudyLinkCreate,
                     db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    if not await db.get(ClinicalCase, case_id):
        raise HTTPException(404, detail="Dossier clinique introuvable")
    study_type = data.study_type.strip().upper()
    study_id = data.study_id.strip()
    if study_type not in VALID_STUDY_TYPES:
        raise HTTPException(400, detail="Type d'examen non valide")
    existing = await db.execute(select(CaseStudyLink).where(
        CaseStudyLink.case_id == case_id, CaseStudyLink.study_type == study_type,
        CaseStudyLink.study_id == study_id))
    if existing.scalar_one_or_none():
        raise HTTPException(409, detail="Examen déjà lié à ce dossier")
    db.add(CaseStudyLink(case_id=case_id, study_type=study_type, study_id=study_id, linked_by=user.id))
    await _audit(db, user, "STUDY_LINKED", "clinical_case", case_id,
                 {"study_type": study_type, "study_id": study_id})
    await db.commit()
    return {"success": True, "study_type": study_type, "study_id": study_id}


@router.post("/{case_id}/signoff")
async def signoff_case(case_id: str, data: ReviewSignoffCreate,
                       db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    case = await db.get(ClinicalCase, case_id)
    if not case:
        raise HTTPException(404, detail="Dossier clinique introuvable")
    decision = data.decision.strip().upper()
    if decision not in VALID_DECISIONS:
        raise HTTPException(400, detail="Décision de revue non valide")
    if decision == "APPROVED":
        case.status = "APPROVED"
        case.closed_at = datetime.now(timezone.utc).replace(tzinfo=None)
    elif decision == "REJECTED":
        case.status = "REJECTED"
    else:
        case.status = "CHANGES_REQUESTED"
    signoff = ReviewSignoff(
        case_id=case_id,
        study_type=data.study_type.strip().upper() if data.study_type else None,
        study_id=data.study_id.strip() if data.study_id else None,
        reviewer_id=user.id, decision=decision, notes=data.notes.strip(),
    )
    db.add(signoff)
    await _audit(db, user, "CASE_SIGNED_OFF", "clinical_case", case_id,
                 {"decision": decision, "study_type": signoff.study_type, "study_id": signoff.study_id})
    await db.commit()
    await db.refresh(signoff)
    return {"success": True, "case_id": case_id, "status": case.status, "signoff_id": signoff.id}


@router.get("/{case_id}/report")
async def unified_case_report(
    case_id: str,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
):
    """Return a modality-neutral report envelope for clinician review."""
    case = await db.get(ClinicalCase, case_id)
    if not case:
        raise HTTPException(404, detail="Dossier clinique introuvable")

    links = (await db.execute(select(CaseStudyLink).where(
        CaseStudyLink.case_id == case_id).order_by(CaseStudyLink.created_at))).scalars().all()
    studies = []
    for link in links:
        item = {
            "study_type": link.study_type,
            "study_id": link.study_id,
            "available": False,
            "status": "MISSING",
            "findings": {},
        }
        if link.study_type in {"ECG", "EEG"}:
            row = await db.get(Rapport, link.study_id)
            if row:
                try:
                    findings = json.loads(row.raw_json or "{}")
                except json.JSONDecodeError:
                    findings = {}
                item.update({
                    "available": True,
                    "status": row.review_level or "PENDING_REVIEW",
                    "diagnostic": row.diagnostic or "",
                    "confidence": row.confidence,
                    "findings": findings,
                })
        elif link.study_type == "IMAGING":
            row = await db.get(ImagingStudy, link.study_id)
            if row:
                try:
                    findings = json.loads(row.result_json or "{}")
                except json.JSONDecodeError:
                    findings = {}
                item.update({
                    "available": True,
                    "status": row.status,
                    "modality": row.modality,
                    "diagnostic": findings.get("text", findings.get("message", "")),
                    "model_name": row.model_name,
                    "findings": findings,
                })
        studies.append(item)

    return {
        "case": _case_dict(case),
        "studies": studies,
        "requires_clinician_signoff": case.status != "APPROVED",
        "disclaimer": "Résultats préliminaires à vérifier par un clinicien.",
    }


@router.get("/{case_id}/audit")
async def case_audit(case_id: str, db: AsyncSession = Depends(get_db), user: User = Depends(get_current_user)):
    if not await db.get(ClinicalCase, case_id):
        raise HTTPException(404, detail="Dossier clinique introuvable")
    events = (await db.execute(select(AuditEvent).where(
        AuditEvent.resource_type == "clinical_case", AuditEvent.resource_id == case_id
    ).order_by(AuditEvent.created_at))).scalars().all()
    return [{"id": x.id, "actor_user_id": x.actor_user_id, "action": x.action,
             "details": json.loads(x.details_json or "{}"),
             "created_at": x.created_at.isoformat() if x.created_at else ""} for x in events]
