from pydantic import BaseModel
from typing import Optional, Dict, Any
from datetime import datetime

class EEGAnalysisRequest(BaseModel):
    patient_id: str
    indication: Optional[str] = "Bilan neurologique"
    operateur_id: Optional[str] = None

class BandesSpectrales(BaseModel):
    delta: float
    theta: float
    alpha: float
    beta: float
    gamma: float

class EEGDiagnostic(BaseModel):
    label: str
    label_fr: str
    cim11: Optional[str]
    confiance: float
    description: str

class EEGAnalysisResult(BaseModel):
    patient_id: str
    rapport_id: str
    diagnostic: EEGDiagnostic
    bandes: BandesSpectrales
    duree_secondes: float
    nb_canaux: int
    frequence_echantillonnage: float
    created_at: datetime
    pdf_path: Optional[str] = None
