from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.db.models import Patient
import uuid

_FIELDS = [
    'nom', 'prenom', 'date_naissance', 'sexe',
    'telephone', 'email', 'adresse', 'groupe_sanguin',
    'antecedents', 'comorbidites', 'traitements_en_cours',
    'allergies', 'notes_generales',
]

def _serialize(p: Patient) -> dict:
    return {f: getattr(p, f, None) for f in ['id'] + _FIELDS + ['created_at']}

async def create_patient(db: AsyncSession, data: dict) -> Patient:
    p = Patient(id=str(uuid.uuid4()),
                **{f: data.get(f) for f in _FIELDS})
    db.add(p)
    await db.commit()
    await db.refresh(p)
    return p

async def update_patient(db: AsyncSession,
                         patient_id: str, data: dict) -> Patient | None:
    result = await db.execute(
        select(Patient).where(Patient.id == patient_id))
    p = result.scalar_one_or_none()
    if not p:
        return None
    for f in _FIELDS:
        if f in data and data[f] is not None:
            setattr(p, f, data[f])
    await db.commit()
    await db.refresh(p)
    return p

async def get_patients(db: AsyncSession):
    result = await db.execute(
        select(Patient).order_by(Patient.created_at.desc()))
    return result.scalars().all()

async def get_patient(db: AsyncSession, patient_id: str):
    result = await db.execute(
        select(Patient).where(Patient.id == patient_id))
    return result.scalar_one_or_none()
