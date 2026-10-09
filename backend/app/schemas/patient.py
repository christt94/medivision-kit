from pydantic import BaseModel
from typing import Optional

class PatientCreate(BaseModel):
    nom:                  str
    prenom:               str
    sexe:                 Optional[str] = None
    date_naissance:       Optional[str] = None
    telephone:            Optional[str] = None
    email:                Optional[str] = None
    adresse:              Optional[str] = None
    groupe_sanguin:       Optional[str] = None
    antecedents:          Optional[str] = None
    comorbidites:         Optional[str] = None
    traitements_en_cours: Optional[str] = None
    allergies:            Optional[str] = None
    notes_generales:      Optional[str] = None

class PatientUpdate(BaseModel):
    nom:                  Optional[str] = None
    prenom:               Optional[str] = None
    sexe:                 Optional[str] = None
    date_naissance:       Optional[str] = None
    telephone:            Optional[str] = None
    email:                Optional[str] = None
    adresse:              Optional[str] = None
    groupe_sanguin:       Optional[str] = None
    antecedents:          Optional[str] = None
    comorbidites:         Optional[str] = None
    traitements_en_cours: Optional[str] = None
    allergies:            Optional[str] = None
    notes_generales:      Optional[str] = None
