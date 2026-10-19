import os, json, uuid, logging
from datetime import datetime
from pathlib import Path
import numpy as np
import mne
import onnxruntime as rt
from scipy.signal import stft
from app.core.config import settings
from app.core.paths import runtime_path

logger = logging.getLogger(__name__)
MODEL_PATH  = runtime_path(settings.MODELS_DIR) / "signal" / "eeg_classifier.onnx"
LABELS_PATH = runtime_path(settings.MODELS_DIR) / "signal" / "eeg_labels.json"

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
        import json as _j, numpy as _np
        meta_path = MODEL_PATH.parent / "eeg_model_meta.json"
        epoch_len = int(_j.loads(meta_path.read_text()).get("n_t", 200)) if meta_path.exists() else 200
        n_epochs = max(1, data.shape[1] // epoch_len)
        epochs = [data[:, i*epoch_len:(i+1)*epoch_len]
                  for i in range(n_epochs)
                  if data[:, i*epoch_len:(i+1)*epoch_len].shape[1] == epoch_len]
        if not epochs:
            return {"class_idx": 0, "confidence": 0.80, "mode": "fallback"}
        epochs_arr = _np.stack(epochs).astype(_np.float32)
        inp_name = self.session.get_inputs()[0].name
        outputs = self.session.run(None, {inp_name: epochs_arr})
        probs = outputs[1].mean(axis=0)
        idx = int(_np.argmax(probs))
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
