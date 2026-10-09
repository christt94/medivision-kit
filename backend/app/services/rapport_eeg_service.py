"""
MediVision Kit — Rapport EEG PDF
Calqué sur rapport_service.py ECG — 4 pages cliniques
"""
import io

import numpy as np
import mne
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib import colors
from reportlab.lib.units import cm
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    HRFlowable,
    Image,
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_CENTER, TA_RIGHT


TEAL       = colors.HexColor("#01696f")
TEAL_LIGHT = colors.HexColor("#f0f7f7")
RED        = colors.HexColor("#c0392b")
ORANGE     = colors.HexColor("#e67e22")
PURPLE     = colors.HexColor("#8e24aa")
GREEN      = colors.HexColor("#43a047")
BLUE       = colors.HexColor("#1e88e5")
GREY       = colors.HexColor("#757575")
GREY_LIGHT = colors.HexColor("#f5f5f5")
WHITE      = colors.white

CH_COLORS = ["#E53935", "#8E24AA", "#1E88E5", "#00ACC1", "#43A047", "#FB8C00", "#5E35B1"]

DIAG_COLORS = {
    "Normal": GREEN,
    "Epilepsy": RED,
    "Sleep_N1": BLUE,
    "Sleep_N2": BLUE,
    "Sleep_N3": PURPLE,
    "Sleep_REM": ORANGE,
    "Artifact": GREY,
}

PRESCRIPTIONS_EEG = {
    "Epilepsy": [
        {
            "intention": "1re intention",
            "atc": "N03AF01",
            "dci": "Carbamazépine",
            "marque": "Tégrétol",
            "classe": "Antiépileptique — bloqueur canaux Na⁺",
            "posologie": "200 mg 2×/jour → 400–800 mg/jour per os",
            "duree": "Long terme — réévaluation annuelle",
            "indication": "Épilepsie focale — crises partielles",
            "contre_ind": "BAV, Porphyrie, Hypersensibilité carbamazépine",
            "surveillance": "NFS, bilan hépatique, natrémie à 1 mois",
            "color": "#01696f",
        },
        {
            "intention": "2e intention",
            "atc": "N03AX09",
            "dci": "Lamotrigine",
            "marque": "Lamictal",
            "classe": "Antiépileptique — bloqueur Na⁺/Ca²⁺",
            "posologie": "25 mg/jour × 2 semaines → 100–200 mg/jour",
            "duree": "Long terme — titration lente obligatoire",
            "indication": "Épilepsie focale + généralisée, Lennox-Gastaut",
            "contre_ind": "Hypersensibilité lamotrigine, Introduire lentement",
            "surveillance": "Éruption cutanée (SJS), bilan hépatique",
            "color": "#1565c0",
        },
        {
            "intention": "3e intention",
            "atc": "N03AX14",
            "dci": "Lévétiracétam",
            "marque": "Keppra",
            "classe": "Antiépileptique — modulateur SV2A",
            "posologie": "500 mg 2×/jour → 1000–3000 mg/jour",
            "duree": "Long terme, bonne tolérance",
            "indication": "Épilepsie focale + généralisée, status epilepticus IV",
            "contre_ind": "Insuffisance rénale sévère (adapter dose)",
            "surveillance": "Comportement (irritabilité), NFS, créatinine",
            "color": "#6a1b9a",
        },
    ],
    "Normal": [],
    "Artifact": [],
    "Sleep_N1": [],
    "Sleep_N2": [],
    "Sleep_N3": [],
    "Sleep_REM": [],
}

BILANS_EEG = {
    "Epilepsy": {
        "STAT": [
            {
                "nom": "Glycémie capillaire",
                "loinc": "2345-7",
                "indication": "Hypoglycémie — cause crise épileptique",
                "norme": "0,7–1,1 g/L",
            },
            {
                "nom": "Ionogramme sanguin",
                "loinc": "24326-1",
                "indication": "Hyponatrémie / dyskaliémie — seuil épileptogène",
                "norme": "Na 135–145 — K 3,5–5,0 mmol/L",
            },
        ],
        "URGENT": [
            {
                "nom": "IRM cérébrale + séquence FLAIR",
                "loinc": "36643-5",
                "indication": "Lésion structurelle — épilepsie focale symptomatique",
                "norme": "Absence de lésion",
            },
            {
                "nom": "EEG de sommeil prolongé",
                "loinc": "18107-6",
                "indication": "Confirmation activité épileptiforme intercritique",
                "norme": "Absence de décharges",
            },
        ],
        "ROUTINE": [
            {
                "nom": "Dosage antiépileptiques",
                "loinc": "3432-2",
                "indication": "Contrôle taux thérapeutique",
                "norme": "Selon molécule",
            },
            {
                "nom": "NFS + bilan hépatique",
                "loinc": "2276-4",
                "indication": "Tolérance traitement antiépileptique",
                "norme": "Valeurs normales laboratoire",
            },
        ],
    },
    "Normal": {
        "STAT": [],
        "URGENT": [],
        "ROUTINE": [
            {
                "nom": "EEG de contrôle à 3 mois",
                "loinc": "18107-6",
                "indication": "Surveillance évolutive",
                "norme": "Normal",
            },
        ],
    },
}

INTERACTIONS_EEG = {
    "Epilepsy": [
        {
            "niveau": "MAJEURE",
            "paire": "Carbamazépine + Lamotrigine",
            "effet": "Induction enzymatique — réduction taux lamotrigine de 40–50%",
            "conduite": "Adapter posologie lamotrigine — dosage plasmatique obligatoire",
            "color": RED,
        },
        {
            "niveau": "MODÉRÉE",
            "paire": "Lévétiracétam + Carbamazépine",
            "effet": "Potentialisation effets indésirables SNC (somnolence, vertiges)",
            "conduite": "Surveillance neurologique — réduire dose si intolérance",
            "color": ORANGE,
        },
    ],
}


def _generate_eeg_plot(edf_path: str, n_seconds: float = 10.0) -> io.BytesIO:
    raw = mne.io.read_raw_edf(edf_path, preload=True, verbose=False)
    raw.filter(1.0, 40.0, fir_design="firwin", verbose=False)

    sfreq = raw.info["sfreq"]
    n_pts = min(int(n_seconds * sfreq), raw.n_times)
    data = raw.get_data()[:, :n_pts] * 1e6
    times = raw.times[:n_pts]
    n_ch = min(data.shape[0], 7)
    ch_names = raw.ch_names[:n_ch]

    scale = 100.0
    offsets = np.arange(n_ch) * scale * 2.5

    fig, ax = plt.subplots(figsize=(14, n_ch * 0.9 + 1), facecolor="#fff8f0")
    ax.set_facecolor("#fff8f0")

    for y in np.arange(0, offsets[-1] + scale * 3, scale * 0.5):
        ax.axhline(y, color="#e8c9a0", lw=0.3, zorder=0)
    for x in np.arange(0, times[-1], 0.2):
        ax.axvline(x, color="#e8c9a0", lw=0.3, zorder=0)
    for y in np.arange(0, offsets[-1] + scale * 3, scale):
        ax.axhline(y, color="#d4a97a", lw=0.5, zorder=0)
    for x in np.arange(0, times[-1], 1.0):
        ax.axvline(x, color="#d4a97a", lw=0.5, zorder=0)

    for i in range(n_ch):
        sig = data[i] - data[i].mean()
        sig = np.clip(sig, -scale * 1.2, scale * 1.2)
        ax.plot(
            times,
            sig + offsets[i],
            color=CH_COLORS[i % len(CH_COLORS)],
            lw=0.8,
            alpha=0.9,
            zorder=2,
        )
        ax.text(
            -0.15,
            offsets[i],
            ch_names[i],
            ha="right",
            va="center",
            fontsize=8,
            fontweight="bold",
            color=CH_COLORS[i % len(CH_COLORS)],
        )

    ax.set_xlim(0, times[-1])
    ax.set_ylim(-scale * 1.5, offsets[-1] + scale * 1.5)
    ax.set_xlabel("Temps (s)", fontsize=8)
    ax.set_yticks([])
    ax.spines[["top", "right", "left"]].set_visible(False)

    ax.annotate(
        "",
        xy=(times[-1] - 0.5, -scale),
        xytext=(times[-1], -scale),
        arrowprops=dict(arrowstyle="<->", color="black", lw=1),
    )
    ax.text(times[-1] - 0.25, -scale * 1.3, "0.5s", ha="center", fontsize=7)

    plt.tight_layout(pad=0.5)
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=150, bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    return buf


def _generate_band_bar(bandes: dict) -> io.BytesIO:
    labels = ["δ Delta\n1-4Hz", "θ Theta\n4-8Hz", "α Alpha\n8-13Hz", "β Beta\n13-30Hz", "γ Gamma\n30-40Hz"]
    keys = ["delta", "theta", "alpha", "beta", "gamma"]
    vals = [bandes.get(k, 0) for k in keys]
    bar_colors = ["#1e88e5", "#8e24aa", "#43a047", "#fb8c00", "#e53935"]

    max_v = max(vals) if max(vals) > 0 else 1
    vals_norm = [v / max_v * 100 for v in vals]

    fig, ax = plt.subplots(figsize=(6, 2.5), facecolor="white")
    bars = ax.bar(labels, vals_norm, color=bar_colors, alpha=0.85, edgecolor="white", linewidth=0.5)
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 1, f"{v:.1e}", ha="center", va="bottom", fontsize=6.5)
    ax.set_ylabel("Puissance relative (%)", fontsize=8)
    ax.set_ylim(0, 115)
    ax.spines[["top", "right"]].set_visible(False)
    ax.tick_params(labelsize=7)
    plt.tight_layout(pad=0.3)

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=120, bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    return buf


def _styles():
    s = getSampleStyleSheet()
    return {
        "title": ParagraphStyle("title", parent=s["Title"], textColor=TEAL, fontSize=16, spaceAfter=2),
        "sub": ParagraphStyle("sub", parent=s["Normal"], textColor=GREY, fontSize=8, spaceAfter=8),
        "h2": ParagraphStyle("h2", parent=s["Heading2"], textColor=TEAL, fontSize=10, spaceBefore=8, spaceAfter=4),
        "normal": s["Normal"],
        "small": ParagraphStyle("small", parent=s["Normal"], fontSize=7.5),
        "footer": ParagraphStyle("footer", parent=s["Normal"], textColor=GREY, fontSize=6.5),
        "bold": ParagraphStyle("bold", parent=s["Normal"], fontName="Helvetica-Bold"),
    }


def _add_validation_section(story, patient_info: dict, styles):
    review_level = patient_info.get("review_level", "AUTO")
    conduite = patient_info.get("conduite", "")

    badges = {
        "AUTO": ("VALIDATION AUTO", colors.yellow),
        "REVIEW": ("À REVOIR", colors.orange),
        "VALIDATED": ("✓ VALIDÉ", GREEN),
    }

    badge_text, _ = badges.get(review_level, ("VALIDATION AUTO", colors.yellow))

    story.append(Spacer(1, 8))
    story.append(Paragraph(
        f"<b>Statut de validation :</b> {badge_text} | "
        f"<i>Conduite clinique :</i> {conduite or '—'}",
        styles["normal"]
    ))
    story.append(HRFlowable(color=TEAL_LIGHT, thickness=0.5, spaceAfter=12))


def generate_rapport_eeg_pdf(
    rapport_id: str,
    content: dict,
    patient_info: dict,
    edf_path: str,
    output_path: str,
) -> str:
    diag = content.get("diagnostic", {})
    bandes = content.get("bandes", {})
    meta = content.get("meta", {})
    label = diag.get("label", "Normal")
    st = _styles()

    doc = SimpleDocTemplate(
        output_path,
        pagesize=landscape(A4),
        leftMargin=1.5 * cm,
        rightMargin=1.5 * cm,
        topMargin=1.5 * cm,
        bottomMargin=1 * cm,
    )

    def _header_info():
        patient_name = patient_info.get("name", patient_info.get("patient_id", "—"))
        age = patient_info.get("age", "—")
        sexe = patient_info.get("sexe", "—")
        date = content.get("created_at", "")[:10]
        indication = content.get("indication", "—")
        return (
            f"Patient : {patient_name} | Âge : {age} | Sexe : {sexe} | "
            f"Date : {date} | Indication : {indication}"
        )

    story = []

    story.append(Paragraph("MediVision Kit — Rapport EEG Complet", st["title"]))
    story.append(Paragraph(_header_info(), st["sub"]))
    story.append(Paragraph(
        f"25 mm/s • 10 µV/mm • 40 Hz &nbsp;&nbsp;|&nbsp;&nbsp; Généré : {content.get('created_at', '')[:19]}",
        ParagraphStyle("calib", parent=st["sub"], fontSize=7, textColor=GREY)
    ))
    story.append(HRFlowable(width="100%", thickness=1, color=TEAL, spaceAfter=6))

    eeg_buf = _generate_eeg_plot(edf_path, n_seconds=10.0)
    eeg_img = Image(eeg_buf, width=19 * cm, height=meta.get("nb_canaux", 7) * 0.9 * cm + 1.5 * cm)
    band_buf = _generate_band_bar(bandes)
    band_img = Image(band_buf, width=8 * cm, height=3.2 * cm)

    diag_color = DIAG_COLORS.get(label, TEAL)
    conf = diag.get("confiance", 0)
    conf_color = "#3fb950" if conf >= 88 else "#d29922" if conf >= 65 else "#f85149"

    review_level = patient_info.get("review_level", "AUTO")
    validation_bg = GREEN if review_level == "VALIDATED" else ORANGE if review_level == "REVIEW" else TEAL
    validation_text = "✓ VALIDÉ" if review_level == "VALIDATED" else "À REVOIR" if review_level == "REVIEW" else "VALIDATION AUTO"

    diag_data = [
        [Paragraph("<b>DIAGNOSTIC PRINCIPAL</b>", ParagraphStyle("dp", parent=st["small"], textColor=WHITE, backColor=diag_color))],
        [Paragraph(f"<b>{diag.get('label_fr', '—')}</b>", ParagraphStyle("dv", parent=st["normal"], fontSize=11, textColor=diag_color))],
        [Paragraph(f"CIM-11 : {diag.get('cim11', '—')}", ParagraphStyle("cim", parent=st["small"], textColor=GREY))],
        [Paragraph(f"Confiance &nbsp;<font color='{conf_color}'><b>{conf}%</b></font>", st["small"])],
        [Paragraph(f"Canaux &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>{meta.get('nb_canaux', '—')}</b>", st["small"])],
        [Paragraph(f"Fréquence &nbsp;<b>{meta.get('sfreq', '—')} Hz</b>", st["small"])],
        [Paragraph(f"Durée &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>{meta.get('duree_s', '—')} s</b>", st["small"])],
        [Paragraph(f"Mode &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>{meta.get('mode', '—')}</b>", st["small"])],
        [Paragraph(f"<b>{validation_text}</b>", ParagraphStyle("va", parent=st["small"], textColor=WHITE, backColor=validation_bg))],
        [Paragraph("<b>Bandes spectrales</b>", st["small"])],
        [band_img],
    ]

    diag_table = Table(diag_data, colWidths=[9 * cm])
    diag_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), diag_color),
        ("BACKGROUND", (0, 8), (-1, 8), validation_bg),
        ("BOX", (0, 0), (-1, -1), 0.5, TEAL),
        ("PADDING", (0, 0), (-1, -1), 5),
        ("ROWBACKGROUNDS", (0, 1), (-1, 7), [TEAL_LIGHT, WHITE]),
    ]))

    story.append(Table(
        [[eeg_img, diag_table]],
        colWidths=[19 * cm, 9.5 * cm],
        style=TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (1, 0), (1, 0), 8),
        ]),
    ))

    story.append(Paragraph("Diagnostics différentiels", st["h2"]))
    diff_diags = {
        "Epilepsy": [("Épilepsie focale", "8A61.0", "Décharges focales unilatérales"), ("État de mal épileptique", "8A62", "Crises > 5 min")],
        "Normal": [("Artefact de mouvement", "—", "Vérifier électrodes"), ("Somnolence physiologique", "—", "EEG de veille recommandé")],
        "Sleep_N1": [("Somnolence pathologique", "7A40", "Bilan hypersomnie")],
        "Sleep_REM": [("Trouble comportemental REM", "7B01", "PSG complète recommandée")],
    }
    diffs = diff_diags.get(label, diff_diags["Normal"])
    for name, cim, note in diffs:
        story.append(Paragraph(f"<b>{name}</b> &nbsp; CIM-11: {cim} &nbsp; {note}", st["small"]))

    story.append(Spacer(1, 4))
    story.append(Paragraph(
        "Rapport généré automatiquement par MediVision Kit. "
        "Ne remplace pas l'avis d'un neurologue qualifié.",
        st["footer"]
    ))

    from reportlab.platypus import PageBreak

    story.append(PageBreak())
    story.append(Paragraph("PRESCRIPTION MÉDICALE — Compte rendu EEG", ParagraphStyle("pt", parent=st["title"], fontSize=14, textColor=TEAL)))
    story.append(Paragraph(f"{_header_info()} | Réf : OMS Liste Médicaments Essentiels 23e éd.", st["sub"]))
    story.append(Paragraph(
        "Ordonnance à valider et signer par un médecin habilité",
        ParagraphStyle("warn", parent=st["small"], textColor=ORANGE, alignment=TA_RIGHT)
    ))
    story.append(HRFlowable(width="100%", thickness=1, color=TEAL, spaceAfter=10))

    prescriptions = PRESCRIPTIONS_EEG.get(label, [])
    if prescriptions:
        presc_cols = []
        for p in prescriptions:
            col_color = colors.HexColor(p["color"])
            cell_data = [
                [
                    Paragraph(f"<b>{p['intention']}</b>", ParagraphStyle("pi", parent=st["small"], textColor=WHITE, alignment=TA_CENTER)),
                    Paragraph(p["atc"], ParagraphStyle("pa", parent=st["small"], textColor=WHITE, alignment=TA_RIGHT)),
                ],
                [Paragraph(f"<b>{p['dci']}</b>", ParagraphStyle("pd", parent=st["normal"], fontSize=12))],
                [Paragraph(p["marque"], ParagraphStyle("pm", parent=st["small"], textColor=GREY))],
                [Paragraph(f"<i>{p['classe']}</i>", ParagraphStyle("pc", parent=st["small"], textColor=GREY))],
                [Paragraph(f"<b>Posologie :</b> {p['posologie']}", st["small"])],
                [Paragraph(f"<b>Durée :</b> {p['duree']}", st["small"])],
                [Paragraph(f"<b>Indication :</b> {p['indication']}", st["small"])],
                [Paragraph(f"<b>Contre-ind. :</b> {p['contre_ind']}", st["small"])],
                [Paragraph(f"<b>Surveillance :</b> {p['surveillance']}", st["small"])],
            ]
            t = Table(cell_data, colWidths=[8.5 * cm, 8.5 * cm] if len(cell_data[0]) == 2 else [17 * cm])
            t.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), col_color),
                ("TEXTCOLOR", (0, 0), (-1, 0), WHITE),
                ("BOX", (0, 0), (-1, -1), 0.5, col_color),
                ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.HexColor("#f9f9f9"), WHITE]),
                ("PADDING", (0, 0), (-1, -1), 5),
                ("SPAN", (0, 1), (-1, 1)),
                ("SPAN", (0, 2), (-1, 2)),
                ("SPAN", (0, 3), (-1, 3)),
                ("SPAN", (0, 4), (-1, 4)),
                ("SPAN", (0, 5), (-1, 5)),
                ("SPAN", (0, 6), (-1, 6)),
                ("SPAN", (0, 7), (-1, 7)),
                ("SPAN", (0, 8), (-1, 8)),
            ]))
            presc_cols.append(t)

        while len(presc_cols) < 3:
            presc_cols.append(Paragraph("", st["normal"]))

        story.append(Table(
            [presc_cols],
            colWidths=[9.2 * cm, 9.2 * cm, 9.2 * cm],
            style=TableStyle([
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
                ("LEFTPADDING", (0, 0), (-1, -1), 3),
            ]),
        ))
    else:
        story.append(Paragraph(
            "Aucune prescription médicamenteuse indiquée pour ce diagnostic.",
            ParagraphStyle("np", parent=st["normal"], textColor=GREY)
        ))

    story.append(Spacer(1, 20))
    story.append(Table(
        [[
            Paragraph("<b>Prescripteur / Médecin validant</b>", ParagraphStyle("pv", parent=st["small"], textColor=TEAL)),
            Paragraph("<b>Date et cachet</b>", ParagraphStyle("dc", parent=st["small"], textColor=TEAL)),
        ]],
        colWidths=[14 * cm, 14 * cm],
        style=TableStyle([
            ("LINEBELOW", (0, 0), (0, 0), 0.5, GREY),
            ("LINEBELOW", (1, 0), (1, 0), 0.5, GREY),
        ]),
    ))
    story.append(Paragraph(
        "Référentiel : OMS Liste des Médicaments Essentiels 23e éd. (2023) | "
        "Codes ATC : WHO Collaborating Centre | Usage réservé aux professionnels de santé",
        ParagraphStyle("ref", parent=st["footer"], alignment=TA_CENTER)
    ))

    story.append(PageBreak())
    story.append(Paragraph("BILAN BIOLOGIQUE — Compte rendu EEG", ParagraphStyle("bt", parent=st["title"], fontSize=14, textColor=TEAL)))
    story.append(Paragraph(f"{_header_info()} | Réf : SFBC / OMS / LOINC", st["sub"]))
    story.append(HRFlowable(width="100%", thickness=1, color=TEAL, spaceAfter=10))

    bilans = BILANS_EEG.get(label, BILANS_EEG["Normal"])
    bilan_headers = [
        ("STAT — Immédiat", bilans.get("STAT", []), RED),
        ("URGENT — < 4h", bilans.get("URGENT", []), ORANGE),
        ("ROUTINE", bilans.get("ROUTINE", []), TEAL),
    ]

    bilan_cols = []
    for header, items, hcol in bilan_headers:
        rows = [[Paragraph(f"<b>{header}</b>", ParagraphStyle("bh", parent=st["small"], textColor=WHITE, alignment=TA_CENTER))]]
        for item in items:
            rows.append([Table([
                [
                    Paragraph(f"<b>{item['nom']}</b>", st["small"]),
                    Paragraph(f"LOINC {item['loinc']}", ParagraphStyle("loinc", parent=st["small"], textColor=TEAL, alignment=TA_RIGHT)),
                ],
                [Paragraph(item["indication"], ParagraphStyle("ind", parent=st["small"], textColor=GREY))],
                [Paragraph(f"<i>Norme : {item['norme']}</i>", ParagraphStyle("nrm", parent=st["small"], textColor=colors.HexColor("#00695c")))],
            ], colWidths=[7 * cm, 2.5 * cm], style=TableStyle([
                ("BOX", (0, 0), (-1, -1), 0.3, colors.HexColor("#ccdddd")),
                ("PADDING", (0, 0), (-1, -1), 4),
                ("SPAN", (0, 1), (-1, 1)),
                ("SPAN", (0, 2), (-1, 2)),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f5fafa")),
            ]))])

        t = Table(rows, colWidths=[9.2 * cm])
        t.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), hcol),
            ("BOX", (0, 0), (-1, -1), 0.3, hcol),
            ("PADDING", (0, 0), (-1, -1), 3),
        ]))
        bilan_cols.append(t)

    story.append(Table(
        [bilan_cols],
        colWidths=[9.2 * cm, 9.2 * cm, 9.2 * cm],
        style=TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 3),
        ]),
    ))
    story.append(Spacer(1, 20))
    story.append(Table(
        [[
            Paragraph("<b>Prescripteur / Médecin validant</b>", ParagraphStyle("pv2", parent=st["small"], textColor=TEAL)),
            Paragraph("<b>Date et cachet</b>", ParagraphStyle("dc2", parent=st["small"], textColor=TEAL)),
        ]],
        colWidths=[14 * cm, 14 * cm],
        style=TableStyle([
            ("LINEBELOW", (0, 0), (0, 0), 0.5, GREY),
            ("LINEBELOW", (1, 0), (1, 0), 0.5, GREY),
        ]),
    ))

    story.append(PageBreak())
    story.append(Paragraph("INTERACTIONS MÉDICAMENTEUSES — Analyse automatique", ParagraphStyle("it", parent=st["title"], fontSize=14, textColor=RED)))
    story.append(Paragraph(f"{_header_info()} | Réf : ANSM / OMS / Base interactions neurologie", st["sub"]))
    story.append(HRFlowable(width="100%", thickness=1, color=RED, spaceAfter=10))

    interactions = INTERACTIONS_EEG.get(label, [])
    if interactions:
        for inter in interactions:
            niveau_color = inter["color"]
            story.append(Table(
                [[
                    Paragraph(f"<b>{inter['niveau']}</b>", ParagraphStyle("ni", parent=st["small"], textColor=WHITE, backColor=niveau_color)),
                    Paragraph(f"<b>{inter['paire']}</b>", st["normal"]),
                ],
                [Paragraph(inter["effet"], st["small"]), ""],
                [Paragraph(f"→ <b>{inter['conduite']}</b>", ParagraphStyle("nc", parent=st["small"], textColor=niveau_color)), ""]],
                colWidths=[3.5 * cm, 24 * cm],
                style=TableStyle([
                    ("BOX", (0, 0), (-1, -1), 0.5, niveau_color),
                    ("BACKGROUND", (0, 0), (0, 0), niveau_color),
                    ("SPAN", (0, 1), (1, 1)),
                    ("SPAN", (0, 2), (1, 2)),
                    ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.HexColor("#fff5f5"), WHITE]),
                    ("PADDING", (0, 0), (-1, -1), 6),
                ]),
            ))
            story.append(Spacer(1, 8))
    else:
        story.append(Paragraph(
            "Aucune interaction médicamenteuse détectée pour ce diagnostic.",
            ParagraphStyle("ni2", parent=st["normal"], textColor=GREY)
        ))

    story.append(Spacer(1, 20))
    story.append(Table(
        [[
            Paragraph("<b>Prescripteur / Médecin validant</b>", ParagraphStyle("pv3", parent=st["small"], textColor=TEAL)),
            Paragraph("<b>Date et cachet</b>", ParagraphStyle("dc3", parent=st["small"], textColor=TEAL)),
        ]],
        colWidths=[14 * cm, 14 * cm],
        style=TableStyle([
            ("LINEBELOW", (0, 0), (0, 0), 0.5, GREY),
            ("LINEBELOW", (1, 0), (1, 0), 0.5, GREY),
        ]),
    ))
    story.append(Paragraph(
        "Analyse automatique — Validation obligatoire par le pharmacien et le médecin "
        "prescripteur avant toute dispensation",
        ParagraphStyle("af", parent=st["footer"], alignment=TA_CENTER, textColor=RED)
    ))

    _add_validation_section(story, patient_info, st)
    doc.build(story)
    return output_path
