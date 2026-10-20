import json
import uuid
from pathlib import Path
from typing import Optional
from xml.sax.saxutils import escape

from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.database import get_db
from app.db.models import ImagingStudy
from app.core.paths import runtime_path
from app.services.case_service import ensure_case_and_link

router = APIRouter()

UPLOAD_DIR = runtime_path(settings.FILES_DIR) / "imaging"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

ALLOWED_EXTENSIONS = {".dcm", ".dicom", ".png", ".jpg", ".jpeg"}
IMAGING_MODALITIES = {"XRAY", "CT", "MRI", "ULTRASOUND", "FUNDUS", "DERMATOSCOPY"}


def _serialize(study: ImagingStudy) -> dict:
    try:
        metadata = json.loads(study.metadata_json or "{}")
    except json.JSONDecodeError:
        metadata = {}
    try:
        result = json.loads(study.result_json or "{}")
    except json.JSONDecodeError:
        result = {}
    return {
        "id": study.id,
        "patient_id": study.patient_id,
        "modality": study.modality,
        "indication": study.indication or "",
        "original_filename": study.original_filename,
        "content_type": study.content_type,
        "size_bytes": study.size_bytes,
        "metadata": metadata,
        "status": study.status,
        "model_name": study.model_name,
        "result": result,
        "clinician_review": result.get("clinician_review", {}),
        "created_at": study.created_at.isoformat() if study.created_at else "",
    }


def _safe_filename(filename: str | None) -> str:
    name = Path(filename or "study").name
    return name[:255] or "study"


def _validate_image(path: Path, extension: str) -> dict:
    if extension in {".dcm", ".dicom"}:
        try:
            import pydicom

            dataset = pydicom.dcmread(str(path), stop_before_pixels=True, force=True)
            return {
                "format": "DICOM",
                "study_instance_uid": str(getattr(dataset, "StudyInstanceUID", "")),
                "series_instance_uid": str(getattr(dataset, "SeriesInstanceUID", "")),
                "sop_class_uid": str(getattr(dataset, "SOPClassUID", "")),
                "rows": int(getattr(dataset, "Rows", 0) or 0),
                "columns": int(getattr(dataset, "Columns", 0) or 0),
            }
        except Exception as exc:
            raise HTTPException(400, detail=f"DICOM invalide : {exc}") from exc

    try:
        from PIL import Image

        with Image.open(path) as image:
            image.verify()
            return {
                "format": image.format or extension.lstrip(".").upper(),
                "width": image.width,
                "height": image.height,
            }
    except Exception as exc:
        raise HTTPException(400, detail=f"Image invalide : {exc}") from exc


def _run_optional_model(path: Path, modality: str, indication: str) -> tuple[str, str, dict]:
    if settings.IMAGING_MODEL.lower() != "medgemma":
        return (
            "PENDING_REVIEW",
            "not_configured",
            {
                "requires_clinician_review": True,
                "message": "Image reçue. Aucun modèle d'imagerie validé n'est configuré.",
            },
        )
    try:
        from app.services.medgemma_imaging import analyze_with_medgemma

        result = analyze_with_medgemma(path, modality, indication)
        return "MODEL_COMPLETE", result.get("model", "medgemma"), result
    except Exception:
        return (
            "MODEL_UNAVAILABLE",
            "medgemma",
            {
                "requires_clinician_review": True,
                "message": "Le modèle MedGemma n'est pas disponible ou n'a pas pu analyser cette image.",
            },
        )


@router.post("/studies")
async def create_imaging_study(
    patient_id: str = Form(...),
    modality: str = Form(default="XRAY"),
    indication: str = Form(default=""),
    case_id: Optional[str] = Form(default=None),
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
):
    patient_id = patient_id.strip()
    modality = modality.strip().upper()
    if not patient_id:
        raise HTTPException(400, detail="patient_id est obligatoire")
    if modality not in IMAGING_MODALITIES:
        raise HTTPException(400, detail=f"Modalité non supportée : {modality}")

    original_filename = _safe_filename(file.filename)
    extension = Path(original_filename).suffix.lower()
    if extension not in ALLOWED_EXTENSIONS:
        raise HTTPException(400, detail=f"Format non supporté : {extension}")

    study_id = str(uuid.uuid4())
    stored_filename = f"{study_id}{extension}"
    save_path = UPLOAD_DIR / stored_filename
    size = 0
    try:
        with save_path.open("wb") as output:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > settings.MAX_UPLOAD_BYTES:
                    raise HTTPException(413, detail="Fichier trop volumineux")
                output.write(chunk)
        metadata = _validate_image(save_path, extension)
    except HTTPException:
        save_path.unlink(missing_ok=True)
        raise
    except Exception as exc:
        save_path.unlink(missing_ok=True)
        raise HTTPException(400, detail=f"Impossible de lire l'image : {exc}") from exc

    status, model_name, result = _run_optional_model(
        save_path, modality, indication.strip()
    )
    study = ImagingStudy(
        id=study_id,
        patient_id=patient_id,
        modality=modality,
        indication=indication.strip(),
        original_filename=original_filename,
        stored_filename=stored_filename,
        content_type=file.content_type or "application/octet-stream",
        size_bytes=size,
        metadata_json=json.dumps(metadata, ensure_ascii=False),
        status=status,
        model_name=model_name,
        result_json=json.dumps(result, ensure_ascii=False),
    )
    db.add(study)
    case = await ensure_case_and_link(
        db,
        patient_id=patient_id,
        study_type="IMAGING",
        study_id=study.id,
        case_id=case_id,
        indication=indication.strip(),
    )
    await db.commit()
    await db.refresh(study)
    return {"success": True, "case_id": case.id, "study": _serialize(study)}


@router.get("/studies")
async def list_imaging_studies(
    patient_id: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
):
    query = select(ImagingStudy).order_by(ImagingStudy.created_at.desc())
    if patient_id:
        query = query.where(ImagingStudy.patient_id == patient_id.strip())
    rows = (await db.execute(query)).scalars().all()
    return [_serialize(study) for study in rows]


@router.get("/studies/{study_id}")
async def get_imaging_study(study_id: str, db: AsyncSession = Depends(get_db)):
    study = await db.get(ImagingStudy, study_id)
    if not study:
        raise HTTPException(404, detail="Étude d'imagerie introuvable")
    return _serialize(study)


@router.get("/studies/{study_id}/file")
async def download_imaging_file(study_id: str, db: AsyncSession = Depends(get_db)):
    study = await db.get(ImagingStudy, study_id)
    if not study:
        raise HTTPException(404, detail="Étude d'imagerie introuvable")
    file_path = (UPLOAD_DIR / study.stored_filename).resolve()
    if file_path.parent != UPLOAD_DIR.resolve() or not file_path.exists():
        raise HTTPException(404, detail="Fichier d'imagerie introuvable")
    return FileResponse(
        path=str(file_path),
        media_type=study.content_type or "application/octet-stream",
        filename=study.original_filename,
    )


@router.patch("/studies/{study_id}")
async def review_imaging_study(
    study_id: str,
    updates: dict = Body(...),
    db: AsyncSession = Depends(get_db),
):
    study = await db.get(ImagingStudy, study_id)
    if not study:
        raise HTTPException(404, detail="Étude d'imagerie introuvable")

    status = updates.get("status")
    if status not in {None, "PENDING_REVIEW", "REVIEWED", "MODEL_COMPLETE"}:
        raise HTTPException(400, detail="Statut de revue non valide")

    try:
        result = json.loads(study.result_json or "{}")
    except json.JSONDecodeError:
        result = {}
    review = result.setdefault("clinician_review", {})
    if "notes" in updates:
        review["notes"] = str(updates.get("notes") or "").strip()
    if "reviewed_by" in updates:
        review["reviewed_by"] = str(updates.get("reviewed_by") or "").strip()
    if status:
        study.status = status
    result["clinician_review"] = review
    study.result_json = json.dumps(result, ensure_ascii=False)
    await db.commit()
    await db.refresh(study)
    return {"success": True, "study": _serialize(study)}


@router.post("/export-pdf")
async def export_imaging_pdf(
    study_id: str = Form(...),
    db: AsyncSession = Depends(get_db),
):
    study = await db.get(ImagingStudy, study_id)
    if not study:
        raise HTTPException(404, detail="Étude d'imagerie introuvable")

    data = _serialize(study)
    result = data.get("result", {})
    review = data.get("clinician_review", {})
    output_path = UPLOAD_DIR / f"rapport_imagerie_{study.id[:8]}.pdf"

    from reportlab.lib.pagesizes import A4
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
    from reportlab.lib import colors
    from reportlab.lib.units import cm
    from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle

    styles = getSampleStyleSheet()
    body = ParagraphStyle("body", parent=styles["BodyText"], leading=14)
    title = ParagraphStyle("title", parent=styles["Title"], textColor=colors.HexColor("#01696f"))
    document = SimpleDocTemplate(
        str(output_path), pagesize=A4,
        leftMargin=2 * cm, rightMargin=2 * cm,
        topMargin=2 * cm, bottomMargin=2 * cm,
    )
    story = [
        Paragraph("MediVision Kit — Rapport d'imagerie", title),
        Spacer(1, 12),
        Paragraph(f"<b>Étude :</b> {escape(study.id)}", body),
        Paragraph(f"<b>Patient :</b> {escape(study.patient_id)}", body),
        Paragraph(f"<b>Modalité :</b> {escape(study.modality)}", body),
        Paragraph(f"<b>Fichier :</b> {escape(study.original_filename)}", body),
        Paragraph(f"<b>Indication :</b> {escape(study.indication or '—')}", body),
        Paragraph(f"<b>Statut :</b> {escape(study.status)}", body),
        Spacer(1, 14),
    ]
    generated_text = result.get("text") or result.get("message") or "Aucun résultat textuel disponible."
    story.append(Paragraph("<b>Résultat préliminaire</b>", body))
    story.append(Spacer(1, 6))
    story.append(Paragraph(escape(str(generated_text)).replace("\n", "<br/>"), body))
    story.append(Spacer(1, 14))
    review_rows = [
        ["Revu par", escape(str(review.get("reviewed_by", "—")))],
        ["Notes clinicien", escape(str(review.get("notes", "—"))).replace("\n", "<br/>")],
    ]
    table = Table(review_rows, colWidths=[4 * cm, 12 * cm])
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#E6F4F1")),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#BBBBBB")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("FONTNAME", (0, 0), (0, -1), "Helvetica-Bold"),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("PADDING", (0, 0), (-1, -1), 6),
    ]))
    story.append(table)
    story.append(Spacer(1, 18))
    story.append(Paragraph(
        "Document généré automatiquement. Ce résultat est préliminaire et ne remplace pas l'interprétation d'un professionnel qualifié.",
        ParagraphStyle("notice", parent=body, textColor=colors.HexColor("#8A4B08")),
    ))
    document.build(story)
    return FileResponse(
        path=str(output_path),
        media_type="application/pdf",
        filename=f"rapport_imagerie_{study.id[:8]}.pdf",
    )
