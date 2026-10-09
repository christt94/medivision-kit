import json, uuid
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.models import Rapport

async def save_rapport(db: AsyncSession, report: dict) -> Rapport:
    ctx = report.get("patient_context", {})

    patient_id = (
        report.get("patient_id", "")
        or ctx.get("patient_id", "")
        or ""
    ).strip()

    patient_name = (
        report.get("patient_name", "")
        or ctx.get("patient_name", "")
        or ""
    ).strip()

    age = (
        ctx.get("age", "")
        or report.get("age", "")
        or ""
    ).strip()

    r = Rapport(
        id           = report.get("report_id", str(uuid.uuid4())),
        patient_id   = patient_id,
        patient_name = patient_name,
        age          = age,
        diagnostic   = report.get("diagnostic_principal", {}).get("libelle", ""),
        cim11_code   = report.get("diagnostic_principal", {}).get("cim11_code", ""),
        confidence   = report.get("confidence_score",
                         report.get("findings", {}).get("confidence", 0.0)),
        review_level = report.get("review_level", "UNKNOWN"),
        conduite     = report.get("conduite_a_tenir", ""),
        raw_json     = json.dumps(report, ensure_ascii=False),
    )
    db.add(r)
    await db.commit()
    await db.refresh(r)
    return r

async def get_rapports_by_patient(db: AsyncSession, patient_id: str):
    result = await db.execute(
        select(Rapport)
        .where(Rapport.patient_id == patient_id)
        .order_by(Rapport.created_at.desc())
    )
    return result.scalars().all()
