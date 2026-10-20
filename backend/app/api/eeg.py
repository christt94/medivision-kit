import json
import shutil
import uuid
from pathlib import Path
from typing import Optional
from datetime import datetime

from fastapi import APIRouter, UploadFile, File, Form, Body, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text

from app.db.database import get_db
from app.db.models import Rapport
from app.services.eeg_pipeline import EEGPipeline
from app.core.config import settings
from app.core.paths import runtime_path
from app.services.case_service import ensure_case_and_link

router = APIRouter()

MODEL_PATH = runtime_path(settings.MODELS_DIR) / "signal" / "eeg_classifier.onnx"
UPLOAD_DIR = runtime_path(settings.FILES_DIR) / "eeg"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

_pipeline = None

def get_pipeline():
    global _pipeline
    if _pipeline is None:
        _pipeline = EEGPipeline(model_path=str(MODEL_PATH))
    return _pipeline


# ── Analyze ───────────────────────────────────────────────────────────────────
@router.post("/analyze")
async def analyze_eeg(
    patient_id:   str          = Form(...),
    indication:   str          = Form(default="Bilan neurologique"),
    operateur_id: str          = Form(default=""),
    file:         UploadFile   = File(...),
    db:           AsyncSession = Depends(get_db),
):
    allowed = {".edf", ".bdf", ".gdf"}
    ext = Path(file.filename or "signal.edf").suffix.lower()
    if ext not in allowed:
        raise HTTPException(400, detail=f"Format non supporté : {ext}")

    # Never use the client-provided filename as a storage path. It can contain
    # path separators and is not a safe filesystem identifier.
    save_path = UPLOAD_DIR / f"{uuid.uuid4().hex}{ext}"
    size = 0
    with open(save_path, "wb") as out:
        while chunk := file.file.read(1024 * 1024):
            size += len(chunk)
            if size > settings.MAX_UPLOAD_BYTES:
                save_path.unlink(missing_ok=True)
                raise HTTPException(413, detail="Fichier trop volumineux")
            out.write(chunk)

    try:
        pipeline = get_pipeline()
        result   = pipeline.analyze(str(save_path), patient_id, indication)
    except Exception as e:
        save_path.unlink(missing_ok=True)
        raise HTTPException(500, detail=f"Erreur pipeline EEG : {e}")

    diag = result["diagnostic"]

    rapport = Rapport(
        id           = result["rapport_id"],
        patient_id   = patient_id,
        patient_name = patient_id,
        age          = "",
        diagnostic   = diag.get("label_fr", diag.get("label", "")),
        cim11_code   = diag.get("cim11"),
        confidence   = diag.get("confiance", 0) / 100,
        review_level = "AUTO",
        conduite     = diag.get("description", ""),
        raw_json     = json.dumps(result),
    )
    db.add(rapport)
    await db.commit()
    await db.refresh(rapport)

    case = await ensure_case_and_link(
        db,
        patient_id=patient_id,
        study_type="EEG",
        study_id=rapport.id,
        indication=indication,
    )
    result["case_id"] = case.id
    rapport.raw_json = json.dumps(result)
    await db.commit()

    return {"success": True, "result": result}


# ── List rapports ─────────────────────────────────────────────────────────────
@router.get("/rapports")
async def list_rapports(db: AsyncSession = Depends(get_db)):
    rows = await db.execute(text("""
        SELECT id, patient_id, patient_name, diagnostic, cim11_code,
               confidence, review_level, created_at
        FROM rapports
        WHERE raw_json LIKE '%"modalite": "EEG"%'
           OR raw_json LIKE '%"nb_canaux"%'
        ORDER BY created_at DESC
    """))
    return {"rapports": [dict(r._mapping) for r in rows.fetchall()]}


# ── Rapports by patient ───────────────────────────────────────────────────────
@router.get("/rapports/patient/{patient_id}")
async def get_rapports_by_patient(
    patient_id: str,
    db: AsyncSession = Depends(get_db),
):
    rows = await db.execute(text("""
        SELECT id, patient_id, diagnostic, cim11_code, confidence, created_at
        FROM rapports
        WHERE patient_id = :pid
          AND (raw_json LIKE '%"nb_canaux"%')
        ORDER BY created_at DESC
    """), {"pid": patient_id})
    return {"patient_id": patient_id, "rapports": [dict(r._mapping) for r in rows.fetchall()]}


# ── Get rapport ───────────────────────────────────────────────────────────────
@router.get("/rapports/{rapport_id}")
async def get_rapport(
    rapport_id: str,
    db: AsyncSession = Depends(get_db),
):
    row = await db.execute(
        text("SELECT * FROM rapports WHERE id = :rid"),
        {"rid": rapport_id}
    )
    data = row.fetchone()
    if not data:
        raise HTTPException(404, detail="Rapport EEG non trouvé")
    return {"rapport_id": rapport_id, "data": dict(data._mapping)}


# ── Update rapport ────────────────────────────────────────────────────────────
@router.patch("/rapports/{rapport_id}")
async def update_rapport(
    rapport_id:   str,
    review_level: Optional[str] = Body(default=None),
    conduite:     Optional[str] = Body(default=None),
    db:           AsyncSession  = Depends(get_db),
):
    row = await db.execute(
        text("SELECT id FROM rapports WHERE id = :rid"), {"rid": rapport_id}
    )
    if not row.fetchone():
        raise HTTPException(404, detail="Rapport EEG non trouvé")

    if review_level:
        await db.execute(
            text("UPDATE rapports SET review_level = :v WHERE id = :rid"),
            {"v": review_level, "rid": rapport_id}
        )
    if conduite:
        await db.execute(
            text("UPDATE rapports SET conduite = :v WHERE id = :rid"),
            {"v": conduite, "rid": rapport_id}
        )
    await db.commit()
    return {"success": True, "rapport_id": rapport_id}


# ── Export PDF ────────────────────────────────────────────────────────────────
@router.post("/export-pdf")
async def export_pdf(
    rapport_id: str            = Form(...),
    db:         AsyncSession   = Depends(get_db),
):
    row = await db.execute(
        text("SELECT * FROM rapports WHERE id = :rid"), {"rid": rapport_id}
    )
    data = row.fetchone()
    if not data:
        raise HTTPException(404, detail="Rapport EEG non trouvé")

    d       = dict(data._mapping)
    content = json.loads(d.get("raw_json") or "{}")
    pdf_path = UPLOAD_DIR / f"rapport_eeg_{rapport_id[:8]}.pdf"

    # Cherche le fichier EDF original
    edf_path = None
    try:
        edf_name = Path(content.get("meta", {}).get("fichier", "")).name
        candidate = (UPLOAD_DIR / edf_name).resolve()
        if candidate.parent == UPLOAD_DIR.resolve() and candidate.exists():
            edf_path = str(candidate)
    except Exception:
        pass

    if edf_path:
        # Rapport complet 4 pages avec tracé EEG
        from app.services.rapport_eeg_service import generate_rapport_eeg_pdf
        patient_info = {
            "patient_id": d.get("patient_id", "—"),
            "name":       d.get("patient_name", d.get("patient_id", "—")),
            "age":        "—",
            "sexe":       "—",
            "review_level": d.get("review_level", "AUTO"),
            "conduite":     d.get("conduite", ""),
        }
        generate_rapport_eeg_pdf(
            rapport_id=rapport_id,
            content=content,
            patient_info=patient_info,
            edf_path=edf_path,
            output_path=str(pdf_path),
        )
    else:
        # Fallback — rapport simple sans tracé
        diag   = content.get("diagnostic", {})
        bandes = content.get("bandes", {})
        meta   = content.get("meta", {})

        from reportlab.lib.pagesizes import A4
        from reportlab.lib import colors
        from reportlab.lib.units import cm
        from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer,
                                         Table, TableStyle, HRFlowable)
        from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

        styles = getSampleStyleSheet()
        teal   = colors.HexColor("#01696f")
        doc    = SimpleDocTemplate(str(pdf_path), pagesize=A4,
                                    leftMargin=2*cm, rightMargin=2*cm,
                                    topMargin=2*cm, bottomMargin=2*cm)
        story  = []
        story.append(Paragraph("MediVision Kit — Rapport EEG", ParagraphStyle(
            "t", parent=styles["Title"], textColor=teal)))
        story.append(Paragraph(f"Rapport : {rapport_id[:8].upper()}", styles["Normal"]))
        conf = diag.get("confiance", 0)
        story.append(Spacer(1, 12))
        story.append(Paragraph(
            f"<b>Diagnostic :</b> {diag.get('label_fr','—')} | "
            f"CIM-11 : {diag.get('cim11','—')} | Confiance : {conf}%",
            styles["Normal"]
        ))
        doc.build(story)

    return FileResponse(
        path=str(pdf_path),
        media_type="application/pdf",
        filename=f"rapport_eeg_{rapport_id[:8]}.pdf"
    )
