import io
import json
import base64
import csv as csv_mod
import os
import tempfile
from datetime import datetime

import numpy as np
from fastapi import APIRouter, UploadFile, File, Form, Body, Depends, HTTPException
from fastapi.responses import StreamingResponse
from reportlab.lib.pagesizes import A4, landscape
from reportlab.pdfgen import canvas as rl_canvas
from reportlab.lib import colors
from reportlab.platypus import Table, TableStyle
from sqlalchemy.ext.asyncio import AsyncSession

from app.services.ecg_pipeline import ECGPipeline
from app.services.rapport_service import save_rapport, get_rapports_by_patient
from app.db.database import get_db
from app.services.case_service import ensure_case_and_link

router   = APIRouter()
pipeline = ECGPipeline()

LEAD_NAMES  = ['I','II','III','aVR','aVL','aVF','V1','V2','V3','V4','V5','V6']
LEAD_COLORS = [
    '#E53935','#8E24AA','#1E88E5','#00ACC1',
    '#43A047','#FB8C00','#E53935','#8E24AA',
    '#1E88E5','#00ACC1','#43A047','#FB8C00',
]
DIAG_COLORS = {
    'NORM': '#43A047', 'MI': '#E53935', 'STTC': '#FB8C00',
    'CD':   '#FB8C00', 'HYP': '#8E24AA', 'OTHER': '#1E88E5',
}
REVIEW_COLORS = {
    'AUTO': '#43A047', 'REVIEW_REQUIRED': '#FB8C00',
    'EXPERT_ESCALATION': '#E53935',
}


# ── Analyze ───────────────────────────────────────────────────────────────────
@router.post("/analyze")
async def analyze_ecg(
    file:         UploadFile    = File(...),
    patient_id:   str           = Form(default=""),
    patient_name: str           = Form(default=""),
    age:          str           = Form(default=""),
    sexe:         str           = Form(default="M"),
    indication:   str           = Form(default=""),
    db:           AsyncSession  = Depends(get_db),
):
    print(f"[DEBUG] patient_id='{patient_id}' patient_name='{patient_name}' age='{age}'")
    contents = await file.read()
    suffix = os.path.splitext(file.filename or "ecg.csv")[1] or ".csv"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
        tmp.write(contents); tmp_path = tmp.name
    try:
        patient_context = {
            "patient_id":   patient_id.strip(),
            "patient_name": patient_name.strip() or patient_id.strip() or "Inconnu",
            "age":          age or "—",
            "sexe":         sexe or "M",
            "indication":   indication or "—",
        }
        result = pipeline.run(tmp_path, patient_context)
    finally:
        os.unlink(tmp_path)

    result["raw_csv"]         = base64.b64encode(contents).decode()
    result["patient_name"]    = patient_name.strip() or patient_id or "Inconnu"
    result["record_date"]     = datetime.now().strftime("%Y-%m-%d")
    result["patient_context"] = patient_context

    # ── Persist to DB ─────────────────────────────────────────────────
    result['patient_id'] = patient_id.strip()  # guarantee top-level UUID
    saved_rapport = None
    try:
        saved_rapport = await save_rapport(db, result)
    except Exception as e:
        print(f"[DB] Failed to save rapport: {e}")

    if patient_id.strip() and saved_rapport is not None:
        case = await ensure_case_and_link(
            db,
            patient_id=patient_id,
            study_type="ECG",
            study_id=saved_rapport.id,
            indication=indication,
        )
        await db.commit()
        result["case_id"] = case.id

    return result


# ── List all rapports ─────────────────────────────────────────────────────────
@router.get("/rapports")
async def list_rapports(db: AsyncSession = Depends(get_db)):
    from sqlalchemy import select
    from app.db.models import Rapport
    rows = await db.execute(select(Rapport).order_by(Rapport.created_at.desc()))
    return [json.loads(r.raw_json) for r in rows.scalars().all()]


# ── Rapports by patient (from DB) ─────────────────────────────────────────────
@router.get("/rapports/patient/{patient_id}")
async def get_rapports_by_patient_route(
    patient_id: str, db: AsyncSession = Depends(get_db)
):
    rows = await get_rapports_by_patient(db, patient_id)
    return [json.loads(r.raw_json) for r in rows]


# ── Get single rapport ────────────────────────────────────────────────────────
@router.get("/rapports/{rapport_id}")
async def get_rapport(rapport_id: str, db: AsyncSession = Depends(get_db)):
    from sqlalchemy import select
    from app.db.models import Rapport
    row = await db.execute(
        select(Rapport).where(Rapport.id == rapport_id))
    r = row.scalar_one_or_none()
    if not r:
        raise HTTPException(status_code=404, detail="Rapport introuvable")
    return json.loads(r.raw_json)


# ── Update rapport (revision) ─────────────────────────────────────────────────
@router.patch("/rapports/{rapport_id}")
async def update_rapport(
    rapport_id: str,
    updates: dict = Body(...),
    db: AsyncSession = Depends(get_db),
):
    from sqlalchemy import select
    from app.db.models import Rapport
    row = await db.execute(select(Rapport).where(Rapport.id == rapport_id))
    r = row.scalar_one_or_none()
    if not r:
        raise HTTPException(status_code=404, detail="Rapport introuvable")

    data = json.loads(r.raw_json)

    # Apply editable fields
    if "diagnostic_libelle" in updates:
        data.setdefault("diagnostic_principal", {})["libelle"] = updates["diagnostic_libelle"]
        r.diagnostic = updates["diagnostic_libelle"]
    if "conduite_a_tenir" in updates:
        data["conduite_a_tenir"] = updates["conduite_a_tenir"]
        r.conduite = updates["conduite_a_tenir"]
    if "notes_clinicien" in updates:
        data["notes_clinicien"] = updates["notes_clinicien"]
    if "valide_par" in updates:
        data["valide_par"] = updates["valide_par"]
    if "date_validation" in updates:
        data["date_validation"] = updates["date_validation"]
    if "statut" in updates:
        data["statut"] = updates["statut"]
        r.review_level = updates["statut"]

    r.raw_json = json.dumps(data, ensure_ascii=False)
    await db.commit()
    return data


# ── PDF helpers ───────────────────────────────────────────────────────────────
def _parse_csv_b64(b64_str: str) -> list:
    try:
        text   = base64.b64decode(b64_str).decode('utf-8')
        reader = list(csv_mod.reader(io.StringIO(text)))
        if not reader: return []
        start = 0
        try:    float(reader[0][0])
        except: start = 1
        rows = []
        for r in reader[start:]:
            if r:
                try:    rows.append([float(v) for v in r])
                except: continue
        if not rows: return []
        arr     = np.array(rows)
        n_leads = min(arr.shape[1], 12)
        return [arr[:, i].tolist() for i in range(n_leads)]
    except:
        return []


def _draw_grid(c, x, y, w, h):
    c.setLineWidth(0.2)
    c.setStrokeColor(colors.HexColor('#FFCDD2'))
    dx = 0.0
    while dx <= w: c.line(x+dx, y, x+dx, y+h); dx += 5
    dy = 0.0
    while dy <= h: c.line(x, y+dy, x+w, y+dy); dy += 5
    c.setLineWidth(0.5)
    c.setStrokeColor(colors.HexColor('#EF9A9A'))
    dx = 0.0
    while dx <= w: c.line(x+dx, y, x+dx, y+h); dx += 25
    dy = 0.0
    while dy <= h: c.line(x, y+dy, x+w, y+dy); dy += 25


def _draw_signal(c, samples, hex_color, x, y, w, h):
    if len(samples) < 2: return
    step = max(1, len(samples) // 300)
    pts  = samples[::step]
    mn, mx = min(pts), max(pts)
    if abs(mx - mn) < 0.001: mn -= 0.5; mx += 0.5
    rng = mx - mn; pad = rng * 0.2; tot = rng + 2*pad
    c.setStrokeColor(colors.HexColor(hex_color))
    c.setLineWidth(0.8)
    path = c.beginPath()
    for i, v in enumerate(pts):
        px = x + (i / (len(pts)-1)) * w
        py = y + ((v - mn + pad) / tot) * h
        if i == 0: path.moveTo(px, py)
        else:      path.lineTo(px, py)
    c.drawPath(path, stroke=1, fill=0)


def _badge(c, x, y, text, bg_hex, w=80, h=14):
    c.setFillColor(colors.HexColor(bg_hex))
    c.roundRect(x, y, w, h, 4, stroke=0, fill=1)
    c.setFillColor(colors.white)
    c.setFont('Helvetica-Bold', 7)
    c.drawCentredString(x + w/2, y + 4, text)
    c.setFillColor(colors.black)


# ── PDF export ────────────────────────────────────────────────────────────────
@router.post("/export-pdf")
async def export_pdf(payload: dict = Body(...)):
    leads    = _parse_csv_b64(payload.get('csv_b64', ''))
    result   = payload.get('result', {})
    patient  = payload.get('patient_name', result.get('patient_name', 'Inconnu'))
    rec_date = payload.get('record_date',  result.get('record_date', ''))

    findings   = result.get('findings', result)
    diag_obj   = result.get('diagnostic_principal', {})
    diag       = diag_obj.get('libelle', findings.get('rhythm', 'N/A'))
    cim11      = diag_obj.get('cim11_code', findings.get('cim11_code', ''))
    conf       = float(findings.get('confidence', result.get('confidence', 0)))
    hr         = findings.get('heart_rate_bpm', 'N/A')
    pr         = findings.get('pr_interval_ms', 160)
    qrs        = findings.get('qrs_duration_ms', 90)
    qt         = findings.get('qt_interval_ms', 380)
    review     = result.get('review_level', 'AUTO')
    pred_cls   = findings.get('predicted_class', 'N/A')
    model      = findings.get('model_used', result.get('model_used', 'N/A'))
    ctx        = result.get('patient_context', {})
    age        = ctx.get('age', 'N/A')
    sexe       = ctx.get('sexe', 'N/A')
    indication = ctx.get('indication', '—')
    diff_dx    = result.get('diagnostics_differentiels', [])
    examens    = result.get('examens_complementaires', [])
    conduite   = result.get('conduite_a_tenir', '')
    gen_at     = result.get('generated_at', '')
    notes      = result.get('notes_clinicien', '')
    valide_par = result.get('valide_par', '')
    date_val   = result.get('date_validation', '')

    buf            = io.BytesIO()
    page_w, page_h = landscape(A4)
    c              = rl_canvas.Canvas(buf, pagesize=(page_w, page_h))
    margin         = 24.0
    usable_w       = page_w - 2*margin

    # ── Header ────────────────────────────────────────────────────────
    c.setFillColor(colors.HexColor('#0D47A1'))
    c.rect(0, page_h-48, page_w, 48, stroke=0, fill=1)
    c.setFillColor(colors.white)
    c.setFont('Helvetica-Bold', 14)
    c.drawString(margin, page_h-30, 'MediVision Kit — Rapport ECG Complet')
    c.setFont('Helvetica', 9)
    c.drawString(margin, page_h-44,
        f'Patient : {patient}   |   Age : {age} ans   |   Sexe : {sexe}'
        f'   |   Date : {rec_date}   |   Indication : {indication}')
    c.setFont('Helvetica', 8)
    c.drawRightString(page_w-margin, page_h-30, '25 mm/s • 10 mm/mV • 40 Hz')
    c.drawRightString(page_w-margin, page_h-44,
        f'Genere : {gen_at[:19] if gen_at else rec_date}')
    c.setFillColor(colors.black)

    RIGHT_W = 168.0
    ECG_W   = usable_w - RIGHT_W - 8

    rx     = margin + ECG_W + 8
    ry_top = page_h - 56

    # ── Diagnostic principal ──────────────────────────────────────────
    diag_color = DIAG_COLORS.get(pred_cls, '#1E88E5')
    c.setFillColor(colors.HexColor(diag_color + '22'))
    c.roundRect(rx, ry_top-54, RIGHT_W, 52, 6, stroke=0, fill=1)
    c.setStrokeColor(colors.HexColor(diag_color))
    c.setLineWidth(1)
    c.roundRect(rx, ry_top-54, RIGHT_W, 52, 6, stroke=1, fill=0)
    c.setFillColor(colors.HexColor(diag_color))
    c.setFont('Helvetica-Bold', 7.5)
    c.drawString(rx+6, ry_top-13, 'DIAGNOSTIC PRINCIPAL')
    c.setFont('Helvetica-Bold', 9.5); c.setFillColor(colors.black)
    words = diag.split(); line1 = ''; line2 = ''
    for w in words:
        if len(line1)+len(w) < 24: line1 += w+' '
        else: line2 += w+' '
    c.drawString(rx+6, ry_top-25, line1.strip())
    if line2: c.drawString(rx+6, ry_top-35, line2.strip())
    c.setFont('Helvetica', 6.5); c.setFillColor(colors.grey)
    c.drawString(rx+6, ry_top-47, f'CIM-11 : {cim11}')
    c.setFillColor(colors.black)

    # ── Measurements ─────────────────────────────────────────────────
    my = ry_top - 62
    metrics = [
        ('Confiance', f'{conf*100:.1f}%'),
        ('FC',        f'{hr} bpm'),
        ('PR',        f'{pr} ms'),
        ('QRS',       f'{qrs} ms'),
        ('QT',        f'{qt} ms'),
        ('Classe IA', str(pred_cls)),
        ('Modele',    str(model).split('_')[0] if '_' in str(model) else str(model)),
    ]
    c.setFillColor(colors.HexColor('#F5F5F5'))
    c.roundRect(rx, my-len(metrics)*15-4, RIGHT_W, len(metrics)*15+8, 4, stroke=0, fill=1)
    for lbl, val in metrics:
        c.setFont('Helvetica', 6.5); c.setFillColor(colors.grey)
        c.drawString(rx+6, my-2, lbl)
        c.setFont('Helvetica-Bold', 7.5); c.setFillColor(colors.black)
        c.drawRightString(rx+RIGHT_W-6, my-2, val)
        my -= 15

    rev_color  = REVIEW_COLORS.get(review, '#1E88E5')
    rev_labels = {
        'AUTO': 'VALIDATION AUTO',
        'REVIEW_REQUIRED': 'REVISION REQUISE',
        'EXPERT_ESCALATION': 'ESCALADE EXPERT',
    }
    _badge(c, rx, my-16, rev_labels.get(review, review), rev_color, RIGHT_W, 14)
    my -= 28

    # ── Diagnostics différentiels ─────────────────────────────────────
    if diff_dx:
        c.setFont('Helvetica-Bold', 7); c.setFillColor(colors.HexColor('#0D47A1'))
        c.drawString(rx, my, 'DIAGNOSTICS DIFFERENTIELS')
        my -= 11
        for d in diff_dx[:3]:
            c.setFillColor(colors.HexColor('#F3F4FF'))
            c.roundRect(rx, my-20, RIGHT_W, 19, 3, stroke=0, fill=1)
            c.setFont('Helvetica-Bold', 6.5); c.setFillColor(colors.black)
            c.drawString(rx+4, my-8, d.get('libelle', '')[:30])
            c.setFont('Helvetica', 6); c.setFillColor(colors.HexColor('#0D47A1'))
            c.drawString(rx+4, my-16,
                f'CIM-11: {d.get("cim11_code","")}   {d.get("condition","")[:22]}')
            c.setFillColor(colors.black)
            my -= 22
    my -= 2

    # ── Examens complémentaires ───────────────────────────────────────
    if examens:
        c.setFont('Helvetica-Bold', 7); c.setFillColor(colors.HexColor('#0D47A1'))
        c.drawString(rx, my, 'EXAMENS COMPLEMENTAIRES')
        my -= 11
        for e in examens[:3]:
            c.setFillColor(colors.HexColor('#F0FFF4'))
            c.roundRect(rx, my-20, RIGHT_W, 19, 3, stroke=0, fill=1)
            c.setFont('Helvetica-Bold', 6.5); c.setFillColor(colors.black)
            c.drawString(rx+4, my-8, e.get('libelle', '')[:30])
            c.setFont('Helvetica', 6); c.setFillColor(colors.HexColor('#1B5E20'))
            c.drawString(rx+4, my-16,
                f'LOINC: {e.get("loinc_code","")}   {e.get("indication","")[:22]}')
            c.setFillColor(colors.black)
            my -= 22
    my -= 2

    # ── Conduite à tenir ──────────────────────────────────────────────
    if conduite:
        c.setFillColor(colors.HexColor('#FFF3E0'))
        c.roundRect(rx, my-18, RIGHT_W, 16, 3, stroke=0, fill=1)
        c.setFont('Helvetica-Bold', 6.5); c.setFillColor(colors.HexColor('#E65100'))
        c.drawString(rx+4, my-13, conduite[:46])
        c.setFillColor(colors.black)
        my -= 22

    # ── Notes clinicien ───────────────────────────────────────────────
    if notes:
        c.setFont('Helvetica-Bold', 7); c.setFillColor(colors.HexColor('#0D47A1'))
        c.drawString(rx, my, 'NOTES CLINICIEN')
        my -= 10
        c.setFont('Helvetica', 6.5); c.setFillColor(colors.black)
        # wrap notes into 2 lines
        words = notes.split(); ln = ''
        for w in words:
            if len(ln)+len(w) < 32: ln += w+' '
            else:
                c.drawString(rx+4, my, ln.strip()); my -= 9; ln = w+' '
        if ln: c.drawString(rx+4, my, ln.strip()); my -= 9
        my -= 4

    # ── Validation block ──────────────────────────────────────────────
    val_h = 62
    val_y = margin + 12
    c.setFillColor(colors.HexColor('#F8F9FA'))
    c.roundRect(rx, val_y, RIGHT_W, val_h, 5, stroke=0, fill=1)
    c.setStrokeColor(colors.HexColor('#BBBBBB'))
    c.setLineWidth(0.5)
    c.roundRect(rx, val_y, RIGHT_W, val_h, 5, stroke=1, fill=0)
    c.setFont('Helvetica-Bold', 7); c.setFillColor(colors.HexColor('#0D47A1'))
    c.drawString(rx+6, val_y+val_h-10, 'VALIDATION CLINICIEN')
    c.setFillColor(colors.black)

    # Validé par
    c.setFont('Helvetica', 6.5); c.setFillColor(colors.grey)
    c.drawString(rx+6, val_y+val_h-22, 'Valide par :')
    if valide_par:
        c.setFillColor(colors.black); c.setFont('Helvetica-Bold', 7)
        c.drawString(rx+58, val_y+val_h-22, valide_par[:24])
    else:
        c.setStrokeColor(colors.HexColor('#AAAAAA')); c.setLineWidth(0.4)
        c.line(rx+58, val_y+val_h-20, rx+RIGHT_W-6, val_y+val_h-20)
    c.setFillColor(colors.black)

    # Date de validation
    c.setFont('Helvetica', 6.5); c.setFillColor(colors.grey)
    c.drawString(rx+6, val_y+val_h-34, 'Date validation :')
    if date_val:
        c.setFillColor(colors.black); c.setFont('Helvetica-Bold', 7)
        c.drawString(rx+70, val_y+val_h-34, date_val[:20])
    else:
        c.setStrokeColor(colors.HexColor('#AAAAAA')); c.setLineWidth(0.4)
        c.line(rx+70, val_y+val_h-32, rx+RIGHT_W-6, val_y+val_h-32)
    c.setFillColor(colors.black)

    # Signature & Cachet
    c.setFont('Helvetica', 6); c.setFillColor(colors.grey)
    c.drawString(rx+6, val_y+val_h-46, 'Signature & Cachet :')
    c.setFillColor(colors.HexColor('#EEEEEE'))
    c.rect(rx+6, val_y+2, RIGHT_W-12, 14, stroke=0, fill=1)
    c.setStrokeColor(colors.HexColor('#CCCCCC')); c.setLineWidth(0.4)
    c.rect(rx+6, val_y+2, RIGHT_W-12, 14, stroke=1, fill=0)
    c.setFillColor(colors.black)

    # ── ECG grid ──────────────────────────────────────────────────────
    tile_gap  = 3.0
    tile_w    = (ECG_W - 2*tile_gap) / 3
    grid_top  = page_h - 56
    rhythm_h  = 40.0
    available = grid_top - margin - rhythm_h - 3*tile_gap - 16
    tile_h    = available / 4

    for i in range(min(len(leads), 12)):
        col = i % 3; row = i // 3
        tx  = margin + col*(tile_w+tile_gap)
        ty  = grid_top - (row+1)*tile_h - row*tile_gap
        c.setFillColor(colors.HexColor('#FFF8F8'))
        c.rect(tx, ty, tile_w, tile_h, stroke=0, fill=1)
        _draw_grid(c, tx, ty, tile_w, tile_h)
        _draw_signal(c, leads[i], LEAD_COLORS[i], tx, ty, tile_w, tile_h)
        c.setStrokeColor(colors.HexColor('#CCCCCC'))
        c.setLineWidth(0.4)
        c.rect(tx, ty, tile_w, tile_h, stroke=1, fill=0)
        c.setFont('Helvetica-Bold', 7)
        c.setFillColor(colors.HexColor(LEAD_COLORS[i]))
        c.drawString(tx+3, ty+3, LEAD_NAMES[i] if i < len(LEAD_NAMES) else f'L{i+1}')
        c.setFillColor(colors.black)

    ry2 = grid_top - 4*(tile_h+tile_gap) - tile_gap - rhythm_h
    c.setFont('Helvetica-Bold', 7); c.setFillColor(colors.black)
    c.drawString(margin, ry2+rhythm_h+3, 'Derivation II — Bande Rythme')
    c.setFillColor(colors.HexColor('#FFF8F8'))
    c.rect(margin, ry2, ECG_W, rhythm_h, stroke=0, fill=1)
    _draw_grid(c, margin, ry2, ECG_W, rhythm_h)
    if len(leads) > 1:
        _draw_signal(c, leads[1], '#8E24AA', margin, ry2, ECG_W, rhythm_h)
    c.setStrokeColor(colors.HexColor('#CCCCCC')); c.setLineWidth(0.4)
    c.rect(margin, ry2, ECG_W, rhythm_h, stroke=1, fill=0)

    # ── Footer ────────────────────────────────────────────────────────
    c.setFont('Helvetica', 6.5); c.setFillColor(colors.grey)
    c.drawString(margin, margin-10,
        "Rapport genere automatiquement par MediVision Kit. "
        "Ne remplace pas l'avis d'un cardiologue qualifie.")



    def _draw_signature(canvas_obj, page_w2, margin2, sig_w2,
                        valide_par2, date_val2):
        """Draw prescriber signature block at bottom of current page."""
        sig_y2 = margin2 + 2
        canvas_obj.setStrokeColor(colors.HexColor('#AAAAAA'))
        canvas_obj.setLineWidth(0.5)
        for i, (lbl, val) in enumerate([
            ('Prescripteur / Médecin validant',
             valide_par2 or '________________________________'),
            ('Date et cachet',
             date_val2   or '________________________________'),
        ]):
            sx = margin2 + i * (sig_w2 + 20)
            canvas_obj.setFont('Helvetica-Bold', 7)
            canvas_obj.setFillColor(colors.HexColor('#0D47A1'))
            canvas_obj.drawString(sx, sig_y2 + 14, lbl)
            canvas_obj.setFont('Helvetica', 8)
            canvas_obj.setFillColor(colors.black)
            canvas_obj.drawString(sx, sig_y2 + 2, val)
            canvas_obj.line(sx, sig_y2, sx + sig_w2, sig_y2)
        canvas_obj.setFillColor(colors.black)

    _sig_w = (page_w - 2*margin - 20) / 2

    # ══════════════════════════════════════════════════════════════════
    # PAGE 2 — PRESCRIPTION MÉDICALE (Référentiel OMS LME 23e éd.)
    # ══════════════════════════════════════════════════════════════════
    rx_list = result.get('prescription_medicale', [])
    if rx_list:
        c.showPage()
        page_w2, page_h2 = landscape(A4)

        # Header page 2
        c.setFillColor(colors.HexColor('#1B5E20'))
        c.rect(0, page_h2-44, page_w2, 44, stroke=0, fill=1)
        c.setFillColor(colors.white)
        c.setFont('Helvetica-Bold', 13)
        c.drawString(margin, page_h2-26, 'PRESCRIPTION MÉDICALE — Compte rendu ECG')
        c.setFont('Helvetica', 8)
        c.drawString(margin, page_h2-39,
            f'Patient : {patient}   |   {rec_date}   |   Réf : OMS Liste Médicaments Essentiels 23e éd.')
        c.setFont('Helvetica-Bold', 8)
        c.setFillColor(colors.HexColor('#FFD54F'))
        c.drawRightString(page_w2-margin, page_h2-26,
            'Ordonnance a valider et signer par un medecin habilite')
        c.setFillColor(colors.black)

        col_w   = (page_w2 - 2*margin - 16) / 3
        col_gap = 8
        card_h  = 148
        y_start = page_h2 - 56

        rank_colors = ['#1B5E20', '#0D47A1', '#4A148C']
        rank_labels = ['1re intention', '2e intention', '3e intention']

        for i, med in enumerate(rx_list[:3]):
            cx = margin + i * (col_w + col_gap)
            cy = y_start - card_h

            # Card background
            bg = '#F9FFF9' if i == 0 else '#F0F4FF' if i == 1 else '#FAF0FF'
            c.setFillColor(colors.HexColor(bg))
            c.roundRect(cx, cy, col_w, card_h, 8, stroke=0, fill=1)
            c.setStrokeColor(colors.HexColor(rank_colors[i]))
            c.setLineWidth(1.5)
            c.roundRect(cx, cy, col_w, card_h, 8, stroke=1, fill=0)

            # Rank badge
            c.setFillColor(colors.HexColor(rank_colors[i]))
            c.roundRect(cx+6, cy+card_h-22, col_w-12, 18, 4, stroke=0, fill=1)
            c.setFillColor(colors.white)
            c.setFont('Helvetica-Bold', 8)
            c.drawCentredString(cx+col_w/2, cy+card_h-14, rank_labels[i])

            # ATC code badge
            c.setFillColor(colors.HexColor('#E3F2FD'))
            c.roundRect(cx+col_w-52, cy+card_h-38, 48, 12, 3, stroke=0, fill=1)
            c.setFillColor(colors.HexColor('#0D47A1'))
            c.setFont('Helvetica-Bold', 6)
            c.drawCentredString(cx+col_w-28, cy+card_h-29, med.get('atc_code', ''))

            # DCI name
            c.setFillColor(colors.black)
            c.setFont('Helvetica-Bold', 10)
            dci = med.get('dci', '')
            if len(dci) > 28:
                parts = dci.split()
                half  = len(parts)//2
                c.drawString(cx+6, cy+card_h-38, ' '.join(parts[:half]))
                c.setFont('Helvetica-Bold', 9)
                c.drawString(cx+6, cy+card_h-48, ' '.join(parts[half:]))
                name_y = cy+card_h-56
            else:
                c.drawString(cx+6, cy+card_h-38, dci)
                name_y = cy+card_h-50

            c.setFont('Helvetica', 7)
            c.setFillColor(colors.HexColor('#555555'))
            c.drawString(cx+6, name_y, med.get('nom_commercial_exemple', '')[:32])
            c.setFont('Helvetica-Oblique', 6.5)
            c.drawString(cx+6, name_y-10, med.get('classe', '')[:38])

            # Separator
            c.setStrokeColor(colors.HexColor('#DDDDDD'))
            c.setLineWidth(0.5)
            c.line(cx+6, name_y-14, cx+col_w-6, name_y-14)

            # Fields
            fields = [
                ('Posologie',   med.get('posologie', '—')),
                ('Duree',       med.get('duree', '—')),
                ('Indication',  med.get('indication_specifique', '—')),
                ('Contre-ind.', ', '.join(med.get('contre_indications', []))),
                ('Surveillance',med.get('surveillance', '—')),
            ]
            fy = name_y - 18
            for lbl, val in fields:
                if fy < cy + 6: break
                c.setFont('Helvetica-Bold', 6)
                c.setFillColor(colors.HexColor(rank_colors[i]))
                c.drawString(cx+6, fy, lbl + ' :')
                c.setFont('Helvetica', 6)
                c.setFillColor(colors.black)
                max_chars = int(col_w / 3.8)
                c.drawString(cx+54, fy, val[:max_chars])
                if len(val) > max_chars and fy-8 > cy+6:
                    fy -= 8
                    c.drawString(cx+54, fy, val[max_chars:max_chars*2])
                fy -= 9

        # OMS footer
        footer_y = y_start - card_h - 18
        c.setFillColor(colors.HexColor('#E8F5E9'))
        c.roundRect(margin, footer_y-16, page_w2-2*margin, 14, 4, stroke=0, fill=1)
        c.setFont('Helvetica', 7)
        c.setFillColor(colors.HexColor('#1B5E20'))
        c.drawCentredString(page_w2/2, footer_y-10,
            'Referentiel : OMS Liste des Medicaments Essentiels 23e ed. (2023)  |  '
            'Codes ATC : WHO Collaborating Centre  |  Usage reserve aux professionnels de sante')
        c.setFillColor(colors.black)

        # Signature block — page 2
        _draw_signature(c, page_w2, margin,
                        _sig_w, valide_par, date_val)


    # ══════════════════════════════════════════════════════════════════
    # PAGE 3 — BILAN BIOLOGIQUE
    # ══════════════════════════════════════════════════════════════════
    bilan_list = result.get('examens_complementaires', [])
    if bilan_list:
        c.showPage()
        c.setFillColor(colors.HexColor('#00695C'))
        c.rect(0, page_h-44, page_w, 44, stroke=0, fill=1)
        c.setFillColor(colors.white)
        c.setFont('Helvetica-Bold', 13)
        c.drawString(margin, page_h-26, 'BILAN BIOLOGIQUE — Compte rendu ECG')
        c.setFont('Helvetica', 8)
        c.drawString(margin, page_h-39,
            f'Patient : {patient}   |   {rec_date}   |   Réf : SFBC / OMS / LOINC')
        c.setFillColor(colors.black)

        urg_groups = [
            ('STAT — Immédiat', 'STAT',    '#B71C1C', '#FFEBEE'),
            ('URGENT — < 4h',  'URGENT',  '#E65100', '#FFF3E0'),
            ('ROUTINE',        'ROUTINE', '#00695C', '#E0F2F1'),
        ]
        col_count = 3
        col_w2   = (page_w - 2*margin - (col_count-1)*8) / col_count
        by_urg   = {'STAT': [], 'URGENT': [], 'ROUTINE': []}
        for e in bilan_list:
            key = e.get('urgence', 'ROUTINE')
            by_urg.setdefault(key, []).append(e)

        gx = margin
        for grp_label, grp_key, grp_color, grp_bg in urg_groups:
            items = by_urg.get(grp_key, [])
            if not items:
                continue
            gy = page_h - 56
            # Group header
            c.setFillColor(colors.HexColor(grp_color))
            c.roundRect(gx, gy-18, col_w2, 16, 4, stroke=0, fill=1)
            c.setFillColor(colors.white)
            c.setFont('Helvetica-Bold', 8)
            c.drawCentredString(gx + col_w2/2, gy-11, grp_label)
            gy -= 24

            for e in items:
                item_h = 52
                if gy - item_h < margin + 10:
                    break
                c.setFillColor(colors.HexColor(grp_bg))
                c.roundRect(gx, gy-item_h, col_w2, item_h, 5, stroke=0, fill=1)
                c.setStrokeColor(colors.HexColor(grp_color))
                c.setLineWidth(0.8)
                c.roundRect(gx, gy-item_h, col_w2, item_h, 5, stroke=1, fill=0)

                # Libelle
                c.setFont('Helvetica-Bold', 8)
                c.setFillColor(colors.black)
                lib = e.get('libelle', '')
                c.drawString(gx+6, gy-10, lib[:32])

                # LOINC badge
                c.setFillColor(colors.HexColor('#E3F2FD'))
                c.roundRect(gx+col_w2-52, gy-22, 48, 11, 3, stroke=0, fill=1)
                c.setFillColor(colors.HexColor('#0D47A1'))
                c.setFont('Helvetica', 6)
                c.drawCentredString(gx+col_w2-28, gy-14,
                    f'LOINC {e.get("loinc_code","")}')

                # Indication
                c.setFont('Helvetica', 7)
                c.setFillColor(colors.HexColor('#555555'))
                ind = e.get('indication', '')
                c.drawString(gx+6, gy-22, ind[:38])
                if len(ind) > 38:
                    c.drawString(gx+6, gy-30, ind[38:76])

                # Valeur normale
                if e.get('valeur_normale'):
                    c.setFont('Helvetica-Oblique', 6.5)
                    c.setFillColor(colors.HexColor('#00695C'))
                    c.drawString(gx+6, gy-40,
                        f'Norme : {e["valeur_normale"][:40]}')

                # Jeûne badge
                if e.get('jeune'):
                    c.setFillColor(colors.HexColor('#FF6F00'))
                    c.roundRect(gx+6, gy-item_h+3, 28, 10, 3, stroke=0, fill=1)
                    c.setFillColor(colors.white)
                    c.setFont('Helvetica-Bold', 5.5)
                    c.drawCentredString(gx+20, gy-item_h+10, 'À JEUN')

                c.setFillColor(colors.black)
                gy -= item_h + 6

            gx += col_w2 + 8

        # Signature block — page 3
        _draw_signature(c, page_w, margin, _sig_w, valide_par, date_val)

    # ══════════════════════════════════════════════════════════════════
    # PAGE 4 — INTERACTIONS MÉDICAMENTEUSES
    # ══════════════════════════════════════════════════════════════════
    ix_list = result.get('interactions_medicamenteuses', [])
    if ix_list:
        c.showPage()
        c.setFillColor(colors.HexColor('#B71C1C'))
        c.rect(0, page_h-44, page_w, 44, stroke=0, fill=1)
        c.setFillColor(colors.white)
        c.setFont('Helvetica-Bold', 13)
        c.drawString(margin, page_h-26,
            'INTERACTIONS MÉDICAMENTEUSES — Analyse automatique')
        c.setFont('Helvetica', 8)
        c.drawString(margin, page_h-39,
            f'Patient : {patient}   |   {rec_date}   |   '
            f'Réf : ANSM / OMS / Base Claude Interactions')
        c.setFillColor(colors.black)

        sev_colors = {
            'MAJEURE':  '#B71C1C',
            'MODEREE':  '#E65100',
            'MINEURE':  '#1565C0',
        }
        sev_bg = {
            'MAJEURE':  '#FFEBEE',
            'MODEREE':  '#FFF3E0',
            'MINEURE':  '#E3F2FD',
        }
        sev_icons_text = {
            'MAJEURE':  '⛔',
            'MODEREE':  '⚠',
            'MINEURE':  'ℹ',
        }

        iy = page_h - 60
        for ix in ix_list:
            sev      = ix.get('severite', 'MINEURE')
            sc       = sev_colors.get(sev, '#1565C0')
            sb       = sev_bg.get(sev, '#E3F2FD')
            card_h2  = 62
            if iy - card_h2 < margin + 10:
                break

            c.setFillColor(colors.HexColor(sb))
            c.roundRect(margin, iy-card_h2, usable_w, card_h2,
                        6, stroke=0, fill=1)
            c.setStrokeColor(colors.HexColor(sc))
            c.setLineWidth(1.5)
            c.roundRect(margin, iy-card_h2, usable_w, card_h2,
                        6, stroke=1, fill=0)

            # Severity badge
            c.setFillColor(colors.HexColor(sc))
            c.roundRect(margin+6, iy-20, 60, 16, 4, stroke=0, fill=1)
            c.setFillColor(colors.white)
            c.setFont('Helvetica-Bold', 7)
            c.drawCentredString(margin+36, iy-11, sev)

            # Libelle
            c.setFillColor(colors.black)
            c.setFont('Helvetica-Bold', 9)
            c.drawString(margin+74, iy-11, ix.get('libelle', '')[:55])

            # Effet
            c.setFont('Helvetica', 8)
            c.setFillColor(colors.HexColor('#333333'))
            c.drawString(margin+10, iy-28, ix.get('effet', '')[:90])

            # Conduite
            c.setFont('Helvetica-Bold', 8)
            c.setFillColor(colors.HexColor(sc))
            c.drawString(margin+10, iy-42,
                f'→  {ix.get("conduite", "")[:85]}')

            # Notes clinicien (éditable)
            notes_ix = ix.get('notes_clinicien', '')
            if notes_ix:
                c.setFont('Helvetica-Oblique', 7)
                c.setFillColor(colors.HexColor('#555555'))
                c.drawString(margin+10, iy-54, f'Note : {notes_ix[:80]}')

            c.setFillColor(colors.black)
            iy -= card_h2 + 10

        # Footer ANSM
        c.setFillColor(colors.HexColor('#FFEBEE'))
        c.roundRect(margin, margin+2, usable_w, 14, 4, stroke=0, fill=1)
        c.setFont('Helvetica', 7)
        c.setFillColor(colors.HexColor('#B71C1C'))
        c.drawCentredString(page_w/2, margin+9,
            'Analyse automatique — Validation obligatoire par le pharmacien '
            'et le médecin prescripteur avant toute dispensation')
        c.setFillColor(colors.black)


        _draw_signature(c, page_w, margin, _sig_w, valide_par, date_val)
    c.save()
    buf.seek(0)
    return StreamingResponse(buf, media_type='application/pdf',
        headers={'Content-Disposition': 'inline; filename="ecg_report.pdf"'})
