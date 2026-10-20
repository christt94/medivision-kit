"""Shared case helpers used by modality upload workflows."""

import json

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.models import AuditEvent, CaseStudyLink, ClinicalCase


async def ensure_case_and_link(
    db: AsyncSession,
    *,
    patient_id: str,
    study_type: str,
    study_id: str,
    case_id: str | None = None,
    indication: str = "",
    actor_user_id: str = "system",
) -> ClinicalCase:
    """Create/reuse an open case and link a newly persisted study to it."""

    patient_id = patient_id.strip()
    study_type = study_type.strip().upper()
    study_id = study_id.strip()
    if not patient_id or not study_id:
        raise HTTPException(400, detail="patient_id et study_id sont obligatoires")

    if case_id:
        case = await db.get(ClinicalCase, case_id.strip())
        if not case:
            raise HTTPException(404, detail="Dossier clinique introuvable")
        if case.patient_id != patient_id:
            raise HTTPException(400, detail="Le dossier et l'examen concernent des patients différents")
    else:
        result = await db.execute(
            select(ClinicalCase)
            .where(
                ClinicalCase.patient_id == patient_id,
                ClinicalCase.status.in_(["OPEN", "CHANGES_REQUESTED"]),
            )
            .order_by(ClinicalCase.updated_at.desc())
            .limit(1)
        )
        case = result.scalar_one_or_none()
        if not case:
            case = ClinicalCase(
                patient_id=patient_id,
                title="Automated clinical case",
                indication=indication.strip(),
                priority="ROUTINE",
                status="OPEN",
                created_by=actor_user_id,
            )
            db.add(case)
            await db.flush()
            db.add(AuditEvent(
                actor_user_id=actor_user_id,
                action="CASE_AUTO_CREATED",
                resource_type="clinical_case",
                resource_id=case.id,
                details_json=json.dumps({"patient_id": patient_id}, ensure_ascii=False),
            ))

    existing = await db.execute(select(CaseStudyLink).where(
        CaseStudyLink.case_id == case.id,
        CaseStudyLink.study_type == study_type,
        CaseStudyLink.study_id == study_id,
    ))
    if not existing.scalar_one_or_none():
        db.add(CaseStudyLink(
            case_id=case.id,
            study_type=study_type,
            study_id=study_id,
            linked_by=actor_user_id,
        ))
        db.add(AuditEvent(
            actor_user_id=actor_user_id,
            action="STUDY_AUTO_LINKED",
            resource_type="clinical_case",
            resource_id=case.id,
            details_json=json.dumps({"study_type": study_type, "study_id": study_id}, ensure_ascii=False),
        ))
    return case
