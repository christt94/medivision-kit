from sqlalchemy import Column, String, Integer, DateTime, Float, Text
from sqlalchemy.sql import func
from app.db.database import Base
import uuid

def new_uuid():
    return str(uuid.uuid4())

class Patient(Base):
    __tablename__ = "patients"
    id         = Column(String, primary_key=True, default=new_uuid)
    nom        = Column(String, nullable=False)
    prenom     = Column(String, nullable=False)
    date_naissance = Column(String)
    sexe       = Column(String)
    telephone       = Column(String)
    email           = Column(String)
    adresse         = Column(String)
    groupe_sanguin  = Column(String)
    antecedents     = Column(Text, default='')
    comorbidites    = Column(Text, default='')
    traitements_en_cours = Column(Text, default='')
    allergies       = Column(Text, default='')
    notes_generales = Column(Text, default='')
    created_at      = Column(DateTime, server_default=func.now())

class Rapport(Base):
    __tablename__ = "rapports"
    id              = Column(String, primary_key=True, default=new_uuid)
    patient_id      = Column(String, nullable=False)
    patient_name    = Column(String, default="")
    age             = Column(String, default="")
    diagnostic      = Column(String)
    cim11_code      = Column(String)
    confidence      = Column(Float)
    review_level    = Column(String)
    conduite        = Column(Text)
    raw_json        = Column(Text)
    created_at      = Column(DateTime, server_default=func.now())

class EegRapport(Base):
    __tablename__ = "eeg_rapports"
    id              = Column(String, primary_key=True, default=new_uuid)
    patient_id      = Column(String, nullable=False)
    patient_name    = Column(String, default="")
    age             = Column(String, default="")
    diagnostic      = Column(String)
    cim11_code      = Column(String)
    confidence      = Column(Float)
    review_level    = Column(String)
    conduite        = Column(Text)
    raw_json        = Column(Text)
    created_at      = Column(DateTime, server_default=func.now())

