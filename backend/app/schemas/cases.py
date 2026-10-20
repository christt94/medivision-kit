from typing import Optional

from pydantic import BaseModel, Field


class CaseCreate(BaseModel):
    patient_id: str = Field(min_length=1, max_length=100)
    title: str = Field(default="Clinical case", min_length=1, max_length=200)
    indication: str = Field(default="", max_length=4000)
    priority: str = "ROUTINE"
    assigned_to: Optional[str] = None


class StudyLinkCreate(BaseModel):
    study_type: str
    study_id: str = Field(min_length=1, max_length=100)


class ReviewSignoffCreate(BaseModel):
    decision: str
    notes: str = Field(default="", max_length=10000)
    study_type: Optional[str] = None
    study_id: Optional[str] = None
