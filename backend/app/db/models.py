from sqlalchemy import Column, String, Integer, DateTime, Float, Text, Boolean, Index
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


class ImagingStudy(Base):
    __tablename__ = "imaging_studies"
    id                = Column(String, primary_key=True, default=new_uuid)
    patient_id        = Column(String, nullable=False, index=True)
    modality          = Column(String, nullable=False, default="XRAY")
    indication        = Column(Text, default="")
    original_filename = Column(String, nullable=False)
    stored_filename   = Column(String, nullable=False, unique=True)
    content_type      = Column(String, default="application/octet-stream")
    size_bytes        = Column(Integer, nullable=False, default=0)
    metadata_json     = Column(Text, default="{}")
    status            = Column(String, nullable=False, default="PENDING_REVIEW")
    model_name        = Column(String, default="not_configured")
    result_json       = Column(Text, default="{}")
    created_at        = Column(DateTime, server_default=func.now())


class User(Base):
    """Local clinical user account used by the case-review workflow."""

    __tablename__ = "users"
    id            = Column(String, primary_key=True, default=new_uuid)
    username      = Column(String, nullable=False, unique=True, index=True)
    full_name     = Column(String, nullable=False)
    password_hash = Column(String, nullable=False)
    role          = Column(String, nullable=False, default="CLINICIAN")
    is_active     = Column(Boolean, nullable=False, default=True)
    created_at    = Column(DateTime, server_default=func.now())


class ClinicalCase(Base):
    """Shared case envelope for ECG, EEG, imaging, and follow-up."""

    __tablename__ = "clinical_cases"
    id           = Column(String, primary_key=True, default=new_uuid)
    patient_id   = Column(String, nullable=False, index=True)
    title        = Column(String, nullable=False, default="Clinical case")
    indication   = Column(Text, default="")
    priority     = Column(String, nullable=False, default="ROUTINE")
    status       = Column(String, nullable=False, default="OPEN", index=True)
    created_by   = Column(String, nullable=False)
    assigned_to  = Column(String, nullable=True)
    created_at   = Column(DateTime, server_default=func.now())
    updated_at   = Column(DateTime, server_default=func.now(), onupdate=func.now())
    closed_at    = Column(DateTime, nullable=True)


class CaseStudyLink(Base):
    """Polymorphic link to an existing ECG, EEG, or imaging record."""

    __tablename__ = "case_study_links"
    id         = Column(String, primary_key=True, default=new_uuid)
    case_id    = Column(String, nullable=False, index=True)
    study_type = Column(String, nullable=False)
    study_id   = Column(String, nullable=False)
    linked_by  = Column(String, nullable=False)
    created_at = Column(DateTime, server_default=func.now())
    __table_args__ = (
        Index("ix_case_study_unique", "case_id", "study_type", "study_id", unique=True),
    )


class ReviewSignoff(Base):
    """Immutable clinician decision for a case or linked study."""

    __tablename__ = "review_signoffs"
    id          = Column(String, primary_key=True, default=new_uuid)
    case_id     = Column(String, nullable=False, index=True)
    study_type  = Column(String, nullable=True)
    study_id    = Column(String, nullable=True)
    reviewer_id = Column(String, nullable=False)
    decision    = Column(String, nullable=False)
    notes       = Column(Text, default="")
    created_at  = Column(DateTime, server_default=func.now())


class AuditEvent(Base):
    """Append-only audit record for clinically meaningful actions."""

    __tablename__ = "audit_events"
    id            = Column(String, primary_key=True, default=new_uuid)
    actor_user_id = Column(String, nullable=True)
    action        = Column(String, nullable=False)
    resource_type = Column(String, nullable=False)
    resource_id   = Column(String, nullable=False, index=True)
    details_json  = Column(Text, default="{}")
    created_at    = Column(DateTime, server_default=func.now(), index=True)

