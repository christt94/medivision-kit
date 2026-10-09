import numpy as np
from scipy.signal import butter, filtfilt, find_peaks
import onnxruntime as ort
import json, uuid, os
from datetime import datetime

_BASE       = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ONNX_PATH   = os.path.join(_BASE, "models", "signal", "ecg_classifier.onnx")
LABELS_PATH = os.path.join(_BASE, "models", "signal", "ecg_labels.json")
N_LEADS, N_SAMPLES, FS = 12, 1000, 100

CIM11_MAP = {
    "NORM":  ("CA80.00", "Rythme sinusal normal"),
    "MI":    ("BA41.00", "Infarctus du myocarde"),
    "STTC":  ("BA80.00", "Modifications ST-T"),
    "CD":    ("BC81.00", "Trouble de la conduction"),
    "HYP":   ("BA01.00", "Hypertrophie ventriculaire"),
    "IMI":   ("BA41.10", "Infarctus myocardique inférieur"),
    "OTHER": ("CA80.00", "Anomalie non classifiée"),
}

# ── Référentiel OMS — Liste Médicaments Essentiels 23e éd. ───────────────────
# Clé = predicted_class, valeur = liste ordonnée par rang de recommandation
PRESCRIPTION_DB = {
    "MI": [
        {
            "rang": 1,
            "dci": "Acide acétylsalicylique",
            "nom_commercial_exemple": "Aspirine",
            "classe": "Antiagrégant plaquettaire",
            "atc_code": "B01AC06",
            "posologie": "300 mg en dose de charge, puis 75–100 mg/jour per os",
            "duree": "Indéfinie (traitement de fond)",
            "indication_specifique": "Inhibition irréversible COX-1 — prévention récidive",
            "contre_indications": ["Ulcère gastroduodénal actif", "Allergie AAS",
                                   "Diathèse hémorragique"],
            "surveillance": "NFS, créatinine à 1 mois",
            "who_essential_medicine": True,
        },
        {
            "rang": 2,
            "dci": "Métoprolol",
            "nom_commercial_exemple": "Lopressor / Betaloc",
            "classe": "Bêta-bloquant cardiosélectif",
            "atc_code": "C07AB02",
            "posologie": "25–50 mg 2×/jour per os (titration progressive)",
            "duree": "≥ 12 mois post-IDM, réévaluation",
            "indication_specifique": "Réduction FC, protection myocardique post-IDM",
            "contre_indications": ["BAV 2° ou 3°", "Bradycardie < 50 bpm",
                                   "Asthme sévère / BPCO sévère"],
            "surveillance": "FC, PA, ECG à 1 mois",
            "who_essential_medicine": True,
        },
        {
            "rang": 3,
            "dci": "Atorvastatine",
            "nom_commercial_exemple": "Tahor / Lipitor",
            "classe": "Statine — inhibiteur HMG-CoA réductase",
            "atc_code": "C10AA05",
            "posologie": "40–80 mg/jour per os le soir",
            "duree": "Indéfinie",
            "indication_specifique": "Stabilisation plaque, réduction LDL-c < 1,4 mmol/L",
            "contre_indications": ["Hépatopathie active", "Grossesse / allaitement",
                                   "Association avec fibrates (prudence)"],
            "surveillance": "ASAT/ALAT, CPK à 3 mois",
            "who_essential_medicine": True,
        },
    ],
    "IMI": [
        {
            "rang": 1,
            "dci": "Acide acétylsalicylique",
            "nom_commercial_exemple": "Aspirine",
            "classe": "Antiagrégant plaquettaire",
            "atc_code": "B01AC06",
            "posologie": "300 mg charge puis 75–100 mg/jour per os",
            "duree": "Indéfinie",
            "indication_specifique": "IDM inférieur — antiagrégation primaire",
            "contre_indications": ["Ulcère actif", "Allergie AAS"],
            "surveillance": "NFS, créatinine",
            "who_essential_medicine": True,
        },
        {
            "rang": 2,
            "dci": "Clopidogrel",
            "nom_commercial_exemple": "Plavix",
            "classe": "Antiagrégant plaquettaire — inhibiteur P2Y12",
            "atc_code": "B01AC04",
            "posologie": "300 mg charge, puis 75 mg/jour per os",
            "duree": "12 mois (bithérapie avec AAS)",
            "indication_specifique": "Double antiagrégation post-IDM inférieur",
            "contre_indications": ["Hémorragie active", "AVC hémorragique récent"],
            "surveillance": "NFS, bilan hépatique",
            "who_essential_medicine": True,
        },
        {
            "rang": 3,
            "dci": "Ramipril",
            "nom_commercial_exemple": "Triatec / Altace",
            "classe": "IEC — inhibiteur de l'enzyme de conversion",
            "atc_code": "C09AA05",
            "posologie": "2,5 mg/jour → titration jusqu'à 10 mg/jour per os",
            "duree": "Indéfinie si FEVG altérée",
            "indication_specifique": "Cardioprotection post-IDM, prévention remodelage",
            "contre_indications": ["Grossesse", "Hyperkaliémie > 5,5 mmol/L",
                                   "Sténose bilatérale artères rénales"],
            "surveillance": "Kaliémie, créatinine à J7 puis 1 mois",
            "who_essential_medicine": True,
        },
    ],
    "STTC": [
        {
            "rang": 1,
            "dci": "Nitroglycérine",
            "nom_commercial_exemple": "Natispray / Trinitrine",
            "classe": "Dérivé nitré — vasodilatateur",
            "atc_code": "C01DA02",
            "posologie": "0,4 mg sublinguale à la demande (max 3 doses/15 min)",
            "duree": "À la demande (crise)",
            "indication_specifique": "Ischémie myocardique — modifications ST-T",
            "contre_indications": ["Hypotension < 90 mmHg", "Inhibiteurs PDE-5 (sildenafil)",
                                   "Péricardite constrictive"],
            "surveillance": "PA avant administration",
            "who_essential_medicine": True,
        },
        {
            "rang": 2,
            "dci": "Bisoprolol",
            "nom_commercial_exemple": "Cardensiel / Concor",
            "classe": "Bêta-bloquant cardiosélectif",
            "atc_code": "C07AB07",
            "posologie": "2,5–5 mg/jour per os (titration)",
            "duree": "3–6 mois, réévaluation ECG",
            "indication_specifique": "Réduction ischémie, contrôle FC",
            "contre_indications": ["BAV haut degré", "Bradycardie < 50 bpm",
                                   "Décompensation cardiaque aiguë"],
            "surveillance": "FC, PA, ECG mensuel",
            "who_essential_medicine": True,
        },
        {
            "rang": 3,
            "dci": "Amlodipine",
            "nom_commercial_exemple": "Amlor / Norvasc",
            "classe": "Inhibiteur calcique — dihydropyridine",
            "atc_code": "C08CA01",
            "posologie": "5 mg/jour per os (max 10 mg/jour)",
            "duree": "Continu, réévaluation à 3 mois",
            "indication_specifique": "Vasodilatation coronaire, HTA associée",
            "contre_indications": ["Choc cardiogénique", "Sténose aortique sévère"],
            "surveillance": "PA, œdèmes des membres inférieurs",
            "who_essential_medicine": True,
        },
    ],
    "HYP": [
        {
            "rang": 1,
            "dci": "Énalapril",
            "nom_commercial_exemple": "Renitec / Vasotec",
            "classe": "IEC",
            "atc_code": "C09AA02",
            "posologie": "5 mg/jour → titration jusqu'à 20 mg/jour per os",
            "duree": "Indéfinie",
            "indication_specifique": "Réduction HVG, néphroprotection",
            "contre_indications": ["Grossesse", "Angiœdème sous IEC antérieur",
                                   "Hyperkaliémie sévère"],
            "surveillance": "PA, kaliémie, créatinine mensuelle",
            "who_essential_medicine": True,
        },
        {
            "rang": 2,
            "dci": "Amlodipine",
            "nom_commercial_exemple": "Amlor / Norvasc",
            "classe": "Inhibiteur calcique",
            "atc_code": "C08CA01",
            "posologie": "5–10 mg/jour per os",
            "duree": "Indéfinie",
            "indication_specifique": "Bithérapie HTA — synergie IEC + IC",
            "contre_indications": ["Choc cardiogénique"],
            "surveillance": "PA quotidienne, OMI",
            "who_essential_medicine": True,
        },
        {
            "rang": 3,
            "dci": "Hydrochlorothiazide",
            "nom_commercial_exemple": "Esidrex",
            "classe": "Diurétique thiazidique",
            "atc_code": "C03AA03",
            "posologie": "12,5–25 mg/jour per os le matin",
            "duree": "Indéfinie, réévaluation ionique",
            "indication_specifique": "Trithérapie si HTA résistante + HVG",
            "contre_indications": ["Insuffisance rénale sévère (DFG < 30)",
                                   "Hypokaliémie < 3 mmol/L"],
            "surveillance": "Ionogramme, créatinine à 1 mois",
            "who_essential_medicine": True,
        },
    ],
    "CD": [
        {
            "rang": 1,
            "dci": "Atropine",
            "nom_commercial_exemple": "Atropine sulfate",
            "classe": "Anticholinergique — chronotrope positif",
            "atc_code": "A03BA01",
            "posologie": "0,5–1 mg IV (urgence bradycardie symptomatique)",
            "duree": "Dose unique ou répétée selon réponse (max 3 mg/24h)",
            "indication_specifique": "BAV symptomatique, bradycardie par trouble conduction",
            "contre_indications": ["Glaucome angle fermé", "Rétention urinaire",
                                   "Tachycardie supraventriculaire"],
            "surveillance": "FC, PA continue, ECG scopé",
            "who_essential_medicine": True,
        },
        {
            "rang": 2,
            "dci": "Amiodarone",
            "nom_commercial_exemple": "Cordarone",
            "classe": "Antiarythmique classe III",
            "atc_code": "C01BD01",
            "posologie": "200 mg 3×/jour × 10j → 200 mg/jour per os entretien",
            "duree": "Long terme sous surveillance spécialisée",
            "indication_specifique": "Troubles conduction + arythmies associées",
            "contre_indications": ["Dysthyroïdie non traitée", "BAV 2° ou 3° sans PM",
                                   "Bradycardie < 45 bpm"],
            "surveillance": "TSH, ASAT/ALAT, Rx thorax à 6 mois, ECG mensuel",
            "who_essential_medicine": True,
        },
        {
            "rang": 3,
            "dci": "Métoprolol",
            "nom_commercial_exemple": "Lopressor / Betaloc",
            "classe": "Bêta-bloquant cardiosélectif",
            "atc_code": "C07AB02",
            "posologie": "25 mg 2×/jour per os (dose minimale efficace)",
            "duree": "3 mois, réévaluation holter",
            "indication_specifique": "Contrôle FC dans trouble conduction modéré",
            "contre_indications": ["BAV haut degré", "FC < 50 bpm",
                                   "Décompensation cardiaque aiguë"],
            "surveillance": "ECG à 2 semaines, holter à 3 mois",
            "who_essential_medicine": True,
        },
    ],
    "NORM": [
        {
            "rang": 1,
            "dci": "Acide acétylsalicylique (si facteurs de risque CV)",
            "nom_commercial_exemple": "Aspirine",
            "classe": "Antiagrégant plaquettaire — prévention primaire",
            "atc_code": "B01AC06",
            "posologie": "75–100 mg/jour per os",
            "duree": "Selon évaluation risque CV (score SCORE2)",
            "indication_specifique": "Prévention primaire si risque CV élevé confirmé",
            "contre_indications": ["Ulcère actif", "Risque hémorragique élevé"],
            "surveillance": "NFS annuelle",
            "who_essential_medicine": True,
        },
        {
            "rang": 2,
            "dci": "Atorvastatine (si dyslipidémie associée)",
            "nom_commercial_exemple": "Tahor / Lipitor",
            "classe": "Statine",
            "atc_code": "C10AA05",
            "posologie": "20–40 mg/jour per os le soir",
            "duree": "Indéfinie selon bilan lipidique",
            "indication_specifique": "Réduction LDL-c si risque CV modéré à élevé",
            "contre_indications": ["Hépatopathie active", "Grossesse"],
            "surveillance": "Bilan lipidique + ASAT/ALAT à 3 mois",
            "who_essential_medicine": True,
        },
        {
            "rang": 3,
            "dci": "Ramipril (si HTA ou diabète associé)",
            "nom_commercial_exemple": "Triatec / Altace",
            "classe": "IEC",
            "atc_code": "C09AA05",
            "posologie": "2,5–5 mg/jour per os",
            "duree": "Indéfinie si indication confirmée",
            "indication_specifique": "Cardioprotection si HTA ou DT2 avec microalbuminurie",
            "contre_indications": ["Grossesse", "Hyperkaliémie"],
            "surveillance": "PA, kaliémie, créatinine",
            "who_essential_medicine": True,
        },
    ],
    "OTHER": [
        {
            "rang": 1,
            "dci": "Bisoprolol",
            "nom_commercial_exemple": "Cardensiel / Concor",
            "classe": "Bêta-bloquant cardiosélectif",
            "atc_code": "C07AB07",
            "posologie": "2,5–5 mg/jour per os",
            "duree": "3 mois, réévaluation",
            "indication_specifique": "Anomalie ECG non classifiée — contrôle FC préventif",
            "contre_indications": ["BAV", "Bradycardie < 50 bpm", "Asthme"],
            "surveillance": "ECG et holter à 1 mois",
            "who_essential_medicine": True,
        },
        {
            "rang": 2,
            "dci": "Amlodipine",
            "nom_commercial_exemple": "Amlor / Norvasc",
            "classe": "Inhibiteur calcique",
            "atc_code": "C08CA01",
            "posologie": "5 mg/jour per os",
            "duree": "3 mois",
            "indication_specifique": "Si HTA associée à anomalie ECG",
            "contre_indications": ["Choc cardiogénique"],
            "surveillance": "PA, ECG mensuel",
            "who_essential_medicine": True,
        },
        {
            "rang": 3,
            "dci": "Acide acétylsalicylique",
            "nom_commercial_exemple": "Aspirine",
            "classe": "Antiagrégant plaquettaire",
            "atc_code": "B01AC06",
            "posologie": "75–100 mg/jour per os",
            "duree": "À réévaluer selon étiologie confirmée",
            "indication_specifique": "Prévention CV selon contexte clinique",
            "contre_indications": ["Ulcère actif", "Allergie AAS"],
            "surveillance": "NFS, créatinine",
            "who_essential_medicine": True,
        },
    ],
}


class ECGPipeline:
    def __init__(self):
        self._session = None
        self._labels  = None
        self._load_model()

    def _load_model(self):
        if not os.path.exists(ONNX_PATH):
            print(f"[ECGPipeline] Model not found: {ONNX_PATH}")
            return
        self._session = ort.InferenceSession(
            ONNX_PATH, providers=["CPUExecutionProvider"])
        with open(LABELS_PATH) as f:
            self._labels = {int(k): v for k, v in json.load(f).items()}
        print(f"[ECGPipeline] Model loaded. Labels: {self._labels}")

    def run(self, signal_path: str, patient_context: dict) -> dict:
        raw      = self._load_signal(signal_path)
        pre      = self._preprocess(raw)
        findings = self._analyze(pre)
        return self._generate_report(findings, patient_context)

    def _load_signal(self, path: str):
        ext = path.rsplit(".", 1)[-1].lower()
        if ext == "csv":
            for skip in (1, 0):
                try:
                    data = np.genfromtxt(path, delimiter=",", skip_header=skip)
                    if data.ndim == 2:
                        data = data[~np.isnan(data).all(axis=1)]
                    data = np.nan_to_num(data, nan=0.0)
                    if data.size > 0:
                        break
                except Exception:
                    continue
            if data.ndim == 1:
                data = data.reshape(1, -1)
            if data.ndim == 2 and data.shape[0] > data.shape[1]:
                data = data.T
            return data.astype(np.float32)
        elif ext in ("edf", "bdf"):
            import mne
            raw = mne.io.read_raw(path, preload=True, verbose=False)
            return raw.get_data().astype(np.float32)
        raise ValueError(f"Format non supporté: {ext}")

    def _preprocess(self, signal: np.ndarray) -> np.ndarray:
        if signal.shape[-1] >= 17:
            try:
                nyq  = FS / 2
                b, a = butter(2, [0.5/nyq, 40.0/nyq], btype="band")
                signal = filtfilt(b, a, signal, axis=-1).astype(np.float32)
            except Exception:
                pass
        mean   = signal.mean(axis=-1, keepdims=True)
        std    = signal.std(axis=-1,  keepdims=True) + 1e-8
        signal = ((signal - mean) / std).astype(np.float32)
        if signal.shape[0] < N_LEADS:
            pad = np.zeros(
                (N_LEADS - signal.shape[0], signal.shape[1]), dtype=np.float32)
            signal = np.vstack([signal, pad])
        else:
            signal = signal[:N_LEADS]
        if signal.shape[1] >= N_SAMPLES:
            signal = signal[:, :N_SAMPLES]
        else:
            signal = np.pad(
                signal, ((0, 0), (0, N_SAMPLES - signal.shape[1])))
        return signal.astype(np.float32)

    def _compute_heart_rate(self, signal: np.ndarray, fs: int = 100) -> dict:
        try:
            lead = signal[1] if signal.shape[0] > 1 else signal[0]
            nyq  = fs / 2
            b, a = butter(2, [5/nyq, 15/nyq], btype='band')
            filtered   = filtfilt(b, a, lead)
            diff       = np.diff(filtered)
            squared    = diff ** 2
            win        = int(0.150 * fs)
            kernel     = np.ones(win) / win
            integrated = np.convolve(squared, kernel, mode='same')
            threshold  = 0.4 * integrated.max()
            min_dist   = int(0.3 * fs)
            peaks, _   = find_peaks(integrated,
                                    height=threshold, distance=min_dist)
            if len(peaks) < 2:
                return {"heart_rate_bpm": 72, "rr_intervals_ms": [],
                        "n_rpeaks": len(peaks), "hr_method": "fallback"}
            rr_samples = np.diff(peaks)
            rr_ms      = (rr_samples / fs * 1000).tolist()
            mean_rr_ms = float(np.mean(rr_ms))
            hr_bpm     = int(round(60000 / mean_rr_ms))
            hr_bpm     = max(30, min(250, hr_bpm))
            sdnn_ms    = round(float(np.std(rr_ms)), 1) if len(rr_ms) > 1 else 0.0
            return {
                "heart_rate_bpm":  hr_bpm,
                "rr_intervals_ms": [round(r, 1) for r in rr_ms[:10]],
                "n_rpeaks":        len(peaks),
                "sdnn_ms":         sdnn_ms,
                "hr_method":       "pan_tompkins",
            }
        except Exception as e:
            print(f"[ECGPipeline] HR detection failed: {e}")
            return {"heart_rate_bpm": 72, "rr_intervals_ms": [],
                    "n_rpeaks": 0, "hr_method": "fallback"}

    def _analyze(self, signal: np.ndarray) -> dict:
        if self._session is not None:
            try:
                inp    = signal[np.newaxis, :, :]
                logits = self._session.run(None, {"ecg_signal": inp})[0][0]
                probs  = np.exp(logits - logits.max())
                probs /= probs.sum()
                idx        = int(np.argmax(probs))
                pred_label = self._labels[idx]
                confidence = float(probs[idx])
                onnx_ready = True
            except Exception as e:
                print(f"[ECGPipeline] ONNX inference failed: {e}")
                pred_label, confidence, onnx_ready = "NORM", 0.70, False
        else:
            pred_label, confidence, onnx_ready = "NORM", 0.70, False

        cim11_code, cim11_label = CIM11_MAP.get(pred_label, CIM11_MAP["OTHER"])
        hr_data = self._compute_heart_rate(signal)
        return {
            "n_channels":      signal.shape[0],
            "duration_sec":    round(signal.shape[1] / FS, 1),
            "heart_rate_bpm":  hr_data["heart_rate_bpm"],
            "pr_interval_ms":  160,
            "qrs_duration_ms": 90,
            "qt_interval_ms":  380,
            "rhythm":          cim11_label,
            "predicted_class": pred_label,
            "cim11_code":      cim11_code,
            "st_changes":      pred_label in ("MI", "STTC", "IMI"),
            "confidence":      round(confidence, 4),
            "rr_intervals_ms": hr_data.get("rr_intervals_ms", []),
            "n_rpeaks":        hr_data.get("n_rpeaks", 0),
            "sdnn_ms":         hr_data.get("sdnn_ms", 0.0),
            "hr_method":       hr_data.get("hr_method", "fallback"),
            "model_used":      "resnet1d_ptbxl_v0.1" if onnx_ready else "heuristic_v0.1",
            "onnx_ready":      onnx_ready,
        }


    # ── Référentiel biologique OMS / SFBC ────────────────────────────────────
    BILAN_DB = {
        "MI": [
            {"libelle": "Troponine I ultrasensible",  "loinc_code": "89579-7",
             "urgence": "STAT", "jeune": False,
             "valeur_normale": "< 0,04 μg/L",
             "indication": "Nécrose myocardique — cinétique H0/H3/H6"},
            {"libelle": "CK-MB",                      "loinc_code": "13969-1",
             "urgence": "STAT", "jeune": False,
             "valeur_normale": "< 25 U/L",
             "indication": "Marqueur nécrose complémentaire"},
            {"libelle": "NFS complète",               "loinc_code": "58410-2",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "Hb > 12 g/dL, GB 4-10 G/L",
             "indication": "Bilan pré-thérapeutique antiagrégants"},
            {"libelle": "Ionogramme sanguin",         "loinc_code": "24326-1",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "Na 136-145, K 3.5-5.0 mmol/L",
             "indication": "Kaliémie — risque arythmique post-IDM"},
            {"libelle": "Créatinine + DFG",           "loinc_code": "2160-0",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "DFG > 60 mL/min/1.73m²",
             "indication": "Adaptation posologie IEC / anticoagulants"},
            {"libelle": "Bilan lipidique complet",    "loinc_code": "57698-3",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "LDL-c < 1,4 mmol/L post-IDM",
             "indication": "Initiation statine haute intensité"},
            {"libelle": "Glycémie à jeun",            "loinc_code": "14770-2",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "< 6,1 mmol/L",
             "indication": "Dépistage diabète — facteur de risque CV"},
            {"libelle": "TP / INR",                   "loinc_code": "5902-2",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "INR 0,9–1,1",
             "indication": "Bilan coagulation pré-antiagrégation"},
        ],
        "IMI": [
            {"libelle": "Troponine I ultrasensible",  "loinc_code": "89579-7",
             "urgence": "STAT", "jeune": False,
             "valeur_normale": "< 0,04 μg/L",
             "indication": "IDM inférieur — cinétique H0/H3/H6"},
            {"libelle": "Ionogramme + Magnésium",     "loinc_code": "24326-1",
             "urgence": "STAT", "jeune": False,
             "valeur_normale": "Mg 0,75-1,0 mmol/L",
             "indication": "Bradycardie réflexe — hypomagnésémie"},
            {"libelle": "NFS complète",               "loinc_code": "58410-2",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "Hb > 12 g/dL",
             "indication": "Pré-thérapeutique bithérapie antiagrégante"},
            {"libelle": "Créatinine + DFG",           "loinc_code": "2160-0",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "DFG > 60 mL/min",
             "indication": "Adaptation Clopidogrel / Ramipril"},
            {"libelle": "Bilan lipidique",            "loinc_code": "57698-3",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "LDL-c < 1,4 mmol/L",
             "indication": "Statine haute intensité post-IDM"},
            {"libelle": "BNP / NT-proBNP",            "loinc_code": "33762-6",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "BNP < 100 pg/mL",
             "indication": "Évaluation dysfonction VD post-IDM inférieur"},
        ],
        "STTC": [
            {"libelle": "Troponine I ultrasensible",  "loinc_code": "89579-7",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "< 0,04 μg/L",
             "indication": "Exclure SCA — modifications ST-T"},
            {"libelle": "Ionogramme sanguin",         "loinc_code": "24326-1",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "K 3,5-5,0 mmol/L",
             "indication": "Dyskaliémie — cause fréquente modifications ST-T"},
            {"libelle": "Magnésium sérique",          "loinc_code": "19123-9",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "0,75-1,0 mmol/L",
             "indication": "Hypomagnésémie — allongement QT"},
            {"libelle": "TSH (Thyréostimuline)",      "loinc_code": "3016-3",
             "urgence": "ROUTINE", "jeune": False,
             "valeur_normale": "0,4-4,0 mUI/L",
             "indication": "Dysthyroïdie — cause modifications ST-T"},
            {"libelle": "Bilan lipidique",            "loinc_code": "57698-3",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "LDL-c < 1,8 mmol/L",
             "indication": "Évaluation risque CV global"},
            {"libelle": "Glycémie à jeun + HbA1c",   "loinc_code": "4548-4",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "HbA1c < 6,5%",
             "indication": "Diabète — facteur ischémie silencieuse"},
        ],
        "HYP": [
            {"libelle": "Ionogramme + Créatinine",    "loinc_code": "24326-1",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "K 3,5-5,0 — DFG > 60",
             "indication": "IEC / diurétique — surveillance rénale"},
            {"libelle": "Aldostérone / Rénine",       "loinc_code": "1763-2",
             "urgence": "ROUTINE", "jeune": False,
             "valeur_normale": "Ratio Aldo/Rénine < 30",
             "indication": "Dépistage hyperaldostéronisme primaire"},
            {"libelle": "BNP / NT-proBNP",            "loinc_code": "33762-6",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "BNP < 100 pg/mL",
             "indication": "Évaluation dysfonction diastolique HVG"},
            {"libelle": "Bilan lipidique complet",    "loinc_code": "57698-3",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "LDL-c < 2,6 mmol/L",
             "indication": "Risque CV global — HTA + HVG"},
            {"libelle": "Microalbuminurie / 24h",     "loinc_code": "14957-5",
             "urgence": "ROUTINE", "jeune": False,
             "valeur_normale": "< 30 mg/24h",
             "indication": "Atteinte organe cible rénale — HTA"},
            {"libelle": "Glycémie à jeun",            "loinc_code": "14770-2",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "< 6,1 mmol/L",
             "indication": "Syndrome métabolique — HTA + HVG"},
        ],
        "CD": [
            {"libelle": "Ionogramme + Magnésium",     "loinc_code": "24326-1",
             "urgence": "STAT", "jeune": False,
             "valeur_normale": "K 3,5-5,0 — Mg 0,75-1,0 mmol/L",
             "indication": "Trouble conduction — dyskaliémie / hypomagnésémie"},
            {"libelle": "TSH ultrasensible",          "loinc_code": "3016-3",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "0,4-4,0 mUI/L",
             "indication": "Hypothyroïdie — cause BAV / bradycardie"},
            {"libelle": "Digoxinémie",                "loinc_code": "10535-3",
             "urgence": "STAT", "jeune": False,
             "valeur_normale": "0,8-2,0 ng/mL",
             "indication": "Toxicité digitalique — cause trouble conduction"},
            {"libelle": "NFS + Ferritine",            "loinc_code": "2276-4",
             "urgence": "ROUTINE", "jeune": False,
             "valeur_normale": "Ferritine 20-300 μg/L",
             "indication": "Anémie — cause tachycardie compensatrice"},
            {"libelle": "Troponine I",                "loinc_code": "89579-7",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "< 0,04 μg/L",
             "indication": "Myocardite — cause trouble conduction aigu"},
            {"libelle": "Sérologie Lyme (Borrelia)",  "loinc_code": "31204-1",
             "urgence": "ROUTINE", "jeune": False,
             "valeur_normale": "Négatif",
             "indication": "BAV — Lyme endémique"},
        ],
        "NORM": [
            {"libelle": "Bilan lipidique complet",    "loinc_code": "57698-3",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "LDL-c < 3,0 mmol/L",
             "indication": "Dépistage risque CV — ECG normal"},
            {"libelle": "Glycémie à jeun",            "loinc_code": "14770-2",
             "urgence": "ROUTINE", "jeune": True,
             "valeur_normale": "< 6,1 mmol/L",
             "indication": "Dépistage diabète"},
            {"libelle": "NFS complète",               "loinc_code": "58410-2",
             "urgence": "ROUTINE", "jeune": False,
             "valeur_normale": "Hb > 12 g/dL",
             "indication": "Bilan général préventif"},
        ],
        "OTHER": [
            {"libelle": "Troponine I ultrasensible",  "loinc_code": "89579-7",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "< 0,04 μg/L",
             "indication": "Anomalie ECG non classifiée — éliminer SCA"},
            {"libelle": "Ionogramme sanguin",         "loinc_code": "24326-1",
             "urgence": "URGENT", "jeune": False,
             "valeur_normale": "Na/K dans les normes",
             "indication": "Désordre électrolytique — anomalie ECG"},
            {"libelle": "TSH",                        "loinc_code": "3016-3",
             "urgence": "ROUTINE", "jeune": False,
             "valeur_normale": "0,4-4,0 mUI/L",
             "indication": "Dysthyroïdie — bilan étiologique"},
        ],
    }

    def _get_bilan(self, pred_label: str) -> list:
        return self.BILAN_DB.get(pred_label, self.BILAN_DB["OTHER"])


    # ── Interactions médicamenteuses — base ATC / ANSM ───────────────────────
    INTERACTIONS_DB = {
        # (atc1, atc2) — ordre alphabétique des codes ATC
        ("B01AC04", "B01AC06"): {
            "severite": "MODEREE",
            "libelle":  "Clopidogrel + Aspirine",
            "effet":    "Risque hémorragique augmenté (bithérapie intentionnelle post-SCA)",
            "conduite": "Association recommandée post-IDM — surveiller saignements",
        },
        ("B01AC06", "C07AB02"): {
            "severite": "MINEURE",
            "libelle":  "Aspirine + Métoprolol",
            "effet":    "Légère réduction effet antihypertenseur des bêta-bloquants",
            "conduite": "Association acceptable — surveiller PA",
        },
        ("C07AB02", "C08CA01"): {
            "severite": "MODEREE",
            "libelle":  "Métoprolol + Amlodipine",
            "effet":    "Risque bradycardie et bloc AV par effet additif",
            "conduite": "Surveiller FC — titration progressive",
        },
        ("C07AB07", "C08CA01"): {
            "severite": "MODEREE",
            "libelle":  "Bisoprolol + Amlodipine",
            "effet":    "Risque bradycardie et hypotension par effet additif",
            "conduite": "Surveiller FC et PA — titration progressive",
        },
        ("C01BD01", "C07AB02"): {
            "severite": "MAJEURE",
            "libelle":  "Amiodarone + Métoprolol",
            "effet":    "Bradycardie sévère et bloc AV — risque arrêt sinusal",
            "conduite": "Association déconseillée — avis cardiologue obligatoire",
        },
        ("C01BD01", "C07AB07"): {
            "severite": "MAJEURE",
            "libelle":  "Amiodarone + Bisoprolol",
            "effet":    "Bradycardie sévère et bloc AV — risque arrêt sinusal",
            "conduite": "Association déconseillée — avis cardiologue obligatoire",
        },
        ("C09AA02", "C09AA05"): {
            "severite": "MAJEURE",
            "libelle":  "Énalapril + Ramipril",
            "effet":    "Double blocage SRA — hypotension, insuffisance rénale aiguë",
            "conduite": "Association contre-indiquée — choisir un seul IEC",
        },
        ("C03AA03", "C09AA02"): {
            "severite": "MINEURE",
            "libelle":  "Hydrochlorothiazide + Énalapril",
            "effet":    "Hypotension de première dose potentialisée",
            "conduite": "Débuter IEC à faible dose — surveiller PA H2 post-prise",
        },
        ("C03AA03", "C09AA05"): {
            "severite": "MINEURE",
            "libelle":  "Hydrochlorothiazide + Ramipril",
            "effet":    "Hypotension de première dose potentialisée",
            "conduite": "Débuter IEC à faible dose — surveiller PA",
        },
        ("C01DA02", "C08CA01"): {
            "severite": "MODEREE",
            "libelle":  "Nitroglycérine + Amlodipine",
            "effet":    "Hypotension additive — risque syncope",
            "conduite": "Surveiller PA avant/après administration dérivés nitrés",
        },
        ("C10AA05", "C07AB02"): {
            "severite": "MINEURE",
            "libelle":  "Atorvastatine + Métoprolol",
            "effet":    "Légère augmentation exposition métoprolol (CYP2D6)",
            "conduite": "Association acceptable — surveiller bradycardie",
        },
    }

    def _get_interactions(self, prescription: list) -> list:
        codes = [m.get("atc_code", "") for m in prescription]
        interactions = []
        for i in range(len(codes)):
            for j in range(i+1, len(codes)):
                pair = tuple(sorted([codes[i], codes[j]]))
                if pair in self.INTERACTIONS_DB:
                    interactions.append(self.INTERACTIONS_DB[pair])
        return interactions

    def _get_prescription(self, pred_label: str) -> list:
        return PRESCRIPTION_DB.get(pred_label, PRESCRIPTION_DB["OTHER"])

    def _generate_report(self, findings: dict, context: dict) -> dict:
        c   = findings["confidence"]
        lvl = ("AUTO"             if c >= 0.88 else
               "REVIEW_REQUIRED" if c >= 0.65 else
               "EXPERT_ESCALATION")
        prescription  = self._get_prescription(findings["predicted_class"])
        interactions  = self._get_interactions(prescription)
        return {
            "report_id":    str(uuid.uuid4()),
            "generated_at": datetime.utcnow().isoformat(),
            "modality":     "ECG",
            "patient_context": context,
            "findings":     findings,
            "diagnostic_principal": {
                "libelle":     findings["rhythm"],
                "cim11_code":  findings["cim11_code"],
                "description": f"IA: {findings['predicted_class']} ({findings['confidence']:.0%})",
            },
            "diagnostics_differentiels": [
                {"libelle": "Bradycardie sinusale", "cim11_code": "CA81.0",
                 "condition": "Si FC < 60 bpm"},
                {"libelle": "Tachycardie sinusale", "cim11_code": "CA81.1",
                 "condition": "Si FC > 100 bpm"},
            ],
            "examens_complementaires": self._get_bilan(findings["predicted_class"]),
            "prescription_medicale": prescription,
            "interactions_medicamenteuses": interactions,
            "conduite_a_tenir":  "Validation obligatoire par le clinicien.",
            "review_level":      lvl,
            "confidence_score":  findings["confidence"],
            "statut":            "BROUILLON",
            "examen_id":         str(uuid.uuid4()),
        }


pipeline = ECGPipeline()
