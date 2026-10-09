#!/bin/bash
set -e
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log() { echo -e "${BLUE}[MediVision]${NC} $1"; }
ok()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn(){ echo -e "${YELLOW}[!]${NC} $1"; }

echo -e "\n${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  MediVision Kit — Module EEG (Module 2) ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}\n"

if [ ! -d "backend" ] || [ ! -d "frontend" ]; then
  echo -e "${RED}[✗] Lance ce script depuis la racine de medivision-kit/${NC}"; exit 1
fi
ok "Racine du projet détectée"

log "Activation du venv..."
source backend/.venv/bin/activate
ok "venv activé"

log "Installation des dépendances EEG..."
pip install --quiet mne pyedflib "scipy>=1.12" braindecode torch onnx "onnxruntime>=1.18"
ok "Dépendances installées"

log "Création de la structure EEG..."
mkdir -p backend/app/api backend/app/services backend/app/schemas
mkdir -p backend/data/models/signal backend/data/files/eeg backend/data/samples/eeg
mkdir -p backend/scripts
ok "Arborescence créée"

log "Création de eeg_labels.json..."
cat > backend/data/models/signal/eeg_labels.json << 'EOF'
{"0":{"label":"Normal","label_fr":"Activité EEG normale","cim11":"8A00.00","description":"Activité électrique cérébrale dans les limites normales"},"1":{"label":"Epilepsy","label_fr":"Activité épileptiforme","cim11":"8A61.0","description":"Décharges épileptiformes détectées"},"2":{"label":"Sleep_N1","label_fr":"Sommeil stade N1","cim11":"7A40.0","description":"Sommeil léger — activité thêta dominante"},"3":{"label":"Sleep_N2","label_fr":"Sommeil stade N2","cim11":"7A40.1","description":"Fuseaux de sommeil et complexes K"},"4":{"label":"Sleep_N3","label_fr":"Sommeil profond","cim11":"7A40.2","description":"Sommeil lent profond — activité delta dominante"},"5":{"label":"Sleep_REM","label_fr":"Sommeil paradoxal REM","cim11":"7A40.3","description":"Activité rapide de basse amplitude"},"6":{"label":"Artifact","label_fr":"Artefact signal","cim11":null,"description":"Signal contaminé par des artefacts"}}
EOF
ok "eeg_labels.json créé"

log "Création de schemas/eeg.py..."
cat > backend/app/schemas/eeg.py << 'EOF'
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
EOF
ok "schemas/eeg.py créé"

log "Création de services/eeg_pipeline.py..."
cat > backend/app/services/eeg_pipeline.py << 'EOF'
import os, json, uuid, logging
from datetime import datetime
from pathlib import Path
import numpy as np
import mne
import onnxruntime as rt
from scipy.signal import stft

logger = logging.getLogger(__name__)
BASE_DIR    = Path(__file__).resolve().parents[2]
MODEL_PATH  = BASE_DIR / "data" / "models" / "signal" / "eeg_classifier.onnx"
LABELS_PATH = BASE_DIR / "data" / "models" / "signal" / "eeg_labels.json"

class EEGPipeline:
    def __init__(self, model_path=str(MODEL_PATH), labels_path=str(LABELS_PATH)):
        with open(labels_path, "r") as f:
            self.labels = json.load(f)
        self.session = None
        if os.path.exists(model_path):
            opts = rt.SessionOptions()
            opts.inter_op_num_threads = 2
            self.session = rt.InferenceSession(model_path, sess_options=opts, providers=["CPUExecutionProvider"])
            logger.info(f"Modèle EEG ONNX chargé : {model_path}")
        else:
            logger.warning("Modèle ONNX non trouvé — mode démo actif")

    def load_signal(self, file_path):
        ext = Path(file_path).suffix.lower()
        if ext in [".edf", ".bdf"]:
            return mne.io.read_raw_edf(file_path, preload=True, verbose=False)
        elif ext == ".gdf":
            return mne.io.read_raw_gdf(file_path, preload=True, verbose=False)
        raise ValueError(f"Format non supporté : {ext}")

    def preprocess(self, raw):
        raw = raw.copy()
        raw.filter(1.0, 40.0, fir_design="firwin", verbose=False)
        raw.set_eeg_reference("average", projection=False, verbose=False)
        data = raw.get_data()
        return (data - data.mean(axis=1, keepdims=True)) / (data.std(axis=1, keepdims=True) + 1e-8)

    def extract_bands(self, data, sfreq):
        bands = {"delta":(1,4),"theta":(4,8),"alpha":(8,13),"beta":(13,30),"gamma":(30,40)}
        nperseg = min(256, data.shape[1])
        f, _, Zxx = stft(data, fs=sfreq, nperseg=nperseg, axis=-1)
        power = np.abs(Zxx) ** 2
        return {b: float(np.mean(power[:, (f>=lo)&(f<hi), :])) for b,(lo,hi) in bands.items()}

    def classify(self, data):
        if self.session is None:
            return {"class_idx": 0, "confidence": 0.95, "mode": "demo"}
        epoch_len = 256
        n_epochs = data.shape[1] // epoch_len
        if n_epochs == 0:
            raise ValueError(f"Signal trop court ({data.shape[1]} pts). Min requis : {epoch_len}")
        epochs = np.stack([data[:, i*epoch_len:(i+1)*epoch_len] for i in range(n_epochs)])
        inp_name = self.session.get_inputs()[0].name
        outputs  = self.session.run(None, {inp_name: epochs.astype(np.float32)})
        probs    = outputs[1].mean(axis=0)
        idx      = int(np.argmax(probs))
        return {"class_idx": idx, "confidence": float(probs[idx]), "mode": "onnx"}

    def analyze(self, file_path, patient_id, indication=""):
        raw    = self.load_signal(file_path)
        sfreq  = raw.info["sfreq"]
        n_ch   = raw.info["nchan"]
        dur    = raw.times[-1]
        data   = self.preprocess(raw)
        bandes = self.extract_bands(data, sfreq)
        clf    = self.classify(data)
        info   = self.labels.get(str(clf["class_idx"]), self.labels["0"])
        return {
            "rapport_id": str(uuid.uuid4()),
            "patient_id": patient_id,
            "indication": indication,
            "created_at": datetime.now().isoformat(),
            "diagnostic": {
                "label":      info["label"],
                "label_fr":   info["label_fr"],
                "cim11":      info.get("cim11"),
                "confiance":  round(clf["confidence"] * 100, 1),
                "description":info["description"],
            },
            "bandes": bandes,
            "meta": {"nb_canaux": n_ch, "sfreq": sfreq, "duree_s": round(dur, 2),
                     "fichier": Path(file_path).name, "mode": clf.get("mode")},
        }
EOF
ok "services/eeg_pipeline.py créé"

log "Création de api/eeg.py..."
cat > backend/app/api/eeg.py << 'EOF'
import shutil
from pathlib import Path
from fastapi import APIRouter, UploadFile, File, Form, HTTPException, Depends
from app.services.eeg_pipeline import EEGPipeline
from app.db.database import get_db
import sqlite3

router = APIRouter(prefix="/eeg", tags=["EEG"])

BASE_DIR   = Path(__file__).resolve().parents[2]
MODEL_PATH = BASE_DIR / "data" / "models" / "signal" / "eeg_classifier.onnx"
UPLOAD_DIR = BASE_DIR / "data" / "files" / "eeg"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

_pipeline = None

def get_pipeline():
    global _pipeline
    if _pipeline is None:
        _pipeline = EEGPipeline(model_path=str(MODEL_PATH))
    return _pipeline

@router.post("/analyze")
async def analyze_eeg(
    patient_id: str = Form(...),
    indication: str = Form(default="Bilan neurologique"),
    operateur_id: str = Form(default=""),
    file: UploadFile = File(...),
    pipeline: EEGPipeline = Depends(get_pipeline),
    db: sqlite3.Connection = Depends(get_db),
):
    allowed = {".edf", ".bdf", ".gdf"}
    ext = Path(file.filename).suffix.lower()
    if ext not in allowed:
        raise HTTPException(400, detail=f"Format non supporté : {ext}")

    save_path = UPLOAD_DIR / f"{patient_id}_{file.filename}"
    with open(save_path, "wb") as out:
        shutil.copyfileobj(file.file, out)

    try:
        result = pipeline.analyze(str(save_path), patient_id, indication)
    except Exception as e:
        raise HTTPException(500, detail=f"Erreur pipeline EEG : {e}")

    cur = db.cursor()
    cur.execute(
        "INSERT INTO examens (id, patient_id, modalite, indication, operateur_id, fichier_path, metadata) VALUES (?,?,?,?,?,?,?)",
        (result["rapport_id"], patient_id, "EEG", indication, operateur_id or None, str(save_path), str(result))
    )
    cur.execute(
        "INSERT INTO rapports (id, examen_id, statut, contenu_json, diagnostic_cim11) VALUES (?,?,?,?,?)",
        (result["rapport_id"], result["rapport_id"], "BROUILLON", str(result), result["diagnostic"].get("cim11"))
    )
    db.commit()
    return {"success": True, "result": result}

@router.get("/patient/{patient_id}")
async def get_patient_eegs(patient_id: str, db: sqlite3.Connection = Depends(get_db)):
    cur = db.cursor()
    cur.execute("""
        SELECT r.id, r.statut, r.diagnostic_cim11, r.created_at, e.indication
        FROM rapports r JOIN examens e ON r.examen_id = e.id
        WHERE e.patient_id = ? AND e.modalite = 'EEG'
        ORDER BY r.created_at DESC
    """, (patient_id,))
    return {"patient_id": patient_id, "eegs": [dict(r) for r in cur.fetchall()]}

@router.get("/{rapport_id}")
async def get_rapport(rapport_id: str, db: sqlite3.Connection = Depends(get_db)):
    cur = db.cursor()
    cur.execute("SELECT * FROM rapports WHERE id = ?", (rapport_id,))
    row = cur.fetchone()
    if not row:
        raise HTTPException(404, detail="Rapport EEG non trouvé")
    return {"rapport_id": rapport_id, "data": dict(row)}
EOF
ok "api/eeg.py créé"

log "Enregistrement du router EEG dans main.py..."
python3 - << 'PYEOF'
with open("backend/app/main.py", "r") as f:
    c = f.read()
if "from app.api import eeg" not in c:
    c = c.replace("from app.api import ecg", "from app.api import ecg\nfrom app.api import eeg", 1)
if "eeg.router" not in c:
    c = c.replace("app.include_router(ecg.router)", "app.include_router(ecg.router)\napp.include_router(eeg.router)", 1)
with open("backend/app/main.py", "w") as f:
    f.write(c)
print("main.py mis à jour")
PYEOF
ok "Router EEG enregistré dans main.py"

log "Création du script export ONNX EEGNet..."
cat > backend/scripts/export_eeg_onnx.py << 'EOF'
"""
MediVision Kit — Export EEGNet → ONNX
Usage : python backend/scripts/export_eeg_onnx.py
"""
import numpy as np
from pathlib import Path
import torch, torch.nn as nn, onnx

OUTPUT = Path(__file__).parent.parent / "data" / "models" / "signal" / "eeg_classifier.onnx"

class EEGNet(nn.Module):
    def __init__(self, n_ch=19, n_t=256, n_cls=7, F1=8, D=2, F2=16, drop=0.25):
        super().__init__()
        self.b1 = nn.Sequential(nn.Conv2d(1,F1,(1,64),padding=(0,32),bias=False), nn.BatchNorm2d(F1))
        self.b2 = nn.Sequential(nn.Conv2d(F1,F1*D,(n_ch,1),groups=F1,bias=False), nn.BatchNorm2d(F1*D), nn.ELU(), nn.AvgPool2d((1,4)), nn.Dropout(drop))
        self.b3 = nn.Sequential(nn.Conv2d(F1*D,F2,(1,16),padding=(0,8),bias=False), nn.BatchNorm2d(F2), nn.ELU(), nn.AvgPool2d((1,8)), nn.Dropout(drop))
        self.fc = nn.Linear(F2*((n_t//4)//8), n_cls)
        self.sm = nn.Softmax(dim=1)
    def forward(self, x):
        x = self.b1(x.unsqueeze(1)); x = self.b2(x); x = self.b3(x)
        logits = self.fc(x.flatten(1)); return logits, self.sm(logits)

print("[1/4] Construction du modèle EEGNet...")
model = EEGNet()
optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
criterion = nn.CrossEntropyLoss()
print("[2/4] Entraînement rapide (données synthétiques — 10 epochs)...")
X = torch.randn(200, 19, 256); y = torch.tensor(list(range(7))*28 + [0,0,0,0])[:200]
model.train()
for ep in range(10):
    optimizer.zero_grad(); loss = criterion(model(X)[0], y); loss.backward(); optimizer.step()
    print(f"  Epoch {ep+1}/10 — loss: {loss.item():.4f}")
print("[3/4] Export ONNX...")
model.eval()
torch.onnx.export(model, torch.randn(1,19,256), str(OUTPUT),
    export_params=True, opset_version=17, input_names=["input"],
    output_names=["logits","probabilities"],
    dynamic_axes={"input":{0:"batch"},"logits":{0:"batch"},"probabilities":{0:"batch"}})
onnx.checker.check_model(onnx.load(str(OUTPUT)))
print(f"[4/4] ✓ Modèle exporté → {OUTPUT} ({OUTPUT.stat().st_size/1e6:.2f} Mo)")
print("⚠ Données synthétiques. Réentraîner sur PhysioNet Sleep-EDF pour la prod.")
EOF
ok "scripts/export_eeg_onnx.py créé"

log "Export du modèle EEGNet ONNX..."
cd backend && python scripts/export_eeg_onnx.py && cd ..
ok "Modèle ONNX exporté"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Module EEG prêt !                             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Fichiers créés :${NC}"
echo "  backend/app/api/eeg.py"
echo "  backend/app/services/eeg_pipeline.py"
echo "  backend/app/schemas/eeg.py"
echo "  backend/data/models/signal/eeg_classifier.onnx"
echo "  backend/data/models/signal/eeg_labels.json"
echo "  backend/scripts/export_eeg_onnx.py"
echo ""
echo -e "${BLUE}Étape suivante :${NC}"
echo "  bash start.sh   (redémarrer le backend)"
echo ""
