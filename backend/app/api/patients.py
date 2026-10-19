from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.database import get_db
from app.services.patient_service import (
    create_patient, update_patient, get_patients, get_patient)
from app.schemas.patient import PatientCreate, PatientUpdate

router = APIRouter()

_FIELDS = [
    'id', 'nom', 'prenom', 'date_naissance', 'sexe',
    'telephone', 'email', 'adresse', 'groupe_sanguin',
    'antecedents', 'comorbidites', 'traitements_en_cours',
    'allergies', 'notes_generales',
]

def _fmt(p) -> dict:
    return {f: getattr(p, f, None) for f in _FIELDS}

@router.get("/")
async def list_patients(db: AsyncSession = Depends(get_db)):
    return [_fmt(p) for p in await get_patients(db)]

@router.post("/")
async def add_patient(data: PatientCreate, db: AsyncSession = Depends(get_db)):
    return _fmt(await create_patient(db, data.model_dump()))

@router.get("/{patient_id}")
async def get_one(patient_id: str, db: AsyncSession = Depends(get_db)):
    p = await get_patient(db, patient_id)
    if not p:
        raise HTTPException(404, "Patient non trouvé")
    return _fmt(p)

@router.patch("/{patient_id}")
async def patch_patient(patient_id: str, data: dict,
                        db: AsyncSession = Depends(get_db)):
    validated = PatientUpdate.model_validate(data)
    p = await update_patient(db, patient_id, validated.model_dump(exclude_unset=True))
    if not p:
        raise HTTPException(404, "Patient non trouvé")
    return _fmt(p)
