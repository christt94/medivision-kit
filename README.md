# Medivision Kit

An on-device medical AI toolkit for ECG and EEG analysis.  
Backend: FastAPI + Python. Frontend: Flutter (desktop & mobile).

## Requirements

- Python 3.10+
- Flutter SDK 3.x
- ~2 GB free disk space (for models and sample data)

## Backend Setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
./start.sh
```

The backend stores its SQLite database at `backend/data/medivision.db` by
default. You can override settings with environment variables or a
`backend/.env` file. In production, set `DEBUG=false`, provide a strong
`SECRET_KEY`, and set `CORS_ORIGINS` to the exact frontend origins.

For an offline/local run, copy `backend/.env.example` to `backend/.env` and
leave `IMAGING_MODEL=none`. The imaging workflow will validate and store files,
display them for review, and export reports without requiring Hugging Face.

## Clinical cases, authentication, and sign-off

The backend includes a unified clinical-case layer for linking ECG, EEG, and
imaging studies to one patient workflow. It also provides local user
authentication, clinician sign-off decisions, and append-only audit events.

Register a local clinician account after starting the backend:

```bash
curl -X POST http://127.0.0.1:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"clinician","full_name":"Local Clinician","password":"change-this-password"}'
```

Use the returned token with `/api/cases`. Create a case, link existing ECG,
EEG, or imaging records through `/api/cases/{case_id}/studies`, then record the
clinician decision through `/api/cases/{case_id}/signoff`. Existing modality
endpoints remain compatible; the migration registry creates the new tables
without deleting existing data.

When an ECG, EEG, or imaging study is uploaded with a `patient_id`, the backend
automatically creates or reuses that patient's open case and links the study.
The unified report is available at `/api/cases/{case_id}/report` and always
requires clinician sign-off before the case can be approved.

For any deployment beyond local development, set a strong `SECRET_KEY`, use
HTTPS or a trusted local-only binding, define a retention policy, and validate
the complete workflow with de-identified data before clinical use.

## Frontend Setup

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port 3000 \
  --dart-define=API_BASE_URL=http://localhost:8000/api
```

`API_BASE_URL` is optional for local development and can point to a deployed
backend for mobile or desktop builds.

The Flutter app now includes a **Dossiers** workspace. Log in with a local
clinician account, create a case, link ECG/EEG/imaging record IDs, review the
case, record a clinician sign-off, and inspect the audit timeline. The login
token is stored locally by the app and automatically sent with API requests.

## Medical imaging module

The Imagerie module accepts DICOM, PNG, and JPEG studies for local storage and
clinician review. It currently performs file validation and technical metadata
extraction; it does not generate a diagnostic when an imaging model is not
configured. Set `IMAGING_MODEL` only after installing and validating a specific
model adapter for the intended modality and population.

### Optional CPU MedGemma adapter

The optional adapter uses `google/medgemma-1.5-4b-it` through Transformers on
CPU. It is resource-intensive and may be slow on a laptop. Python 3.11 is
recommended for the widest PyTorch wheel compatibility.

```powershell
cd backend
python -m pip install -r requirements-imaging-cpu.txt
$env:IMAGING_MODEL = "medgemma"
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

You may need to accept the model's Hugging Face access terms and authenticate
with `huggingface-cli login` before the first model download. The output is
preliminary decision support and always remains marked for clinician review.

## GitHub handoff checklist

Before pushing the project:

- Do not commit `.env` files, Hugging Face tokens, databases, uploaded studies,
  DICOM files, or model weights.
- Keep `backend/.env.example` as the shareable configuration template.
- Run `python -m compileall -q backend/app backend/scripts`.
- Run `flutter analyze` from the `frontend` directory.
- Use a private repository if the project contains any non-public clinical
  material or internal configuration.

## Standalone offline desktop app

The project includes packaging workflows for Windows, macOS, and Linux. Each
workflow builds the Flutter desktop app, packages the FastAPI service as a
native executable, and places the backend beside the desktop executable. The
desktop app starts that local backend automatically; internet access is not
required for normal use.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\packaging\windows\build.ps1
```

For macOS or Linux, run the build on that operating system:

```bash
./packaging/build_unix.sh macos
# or
./packaging/build_unix.sh linux
```

See `packaging/README.md` for platform-specific prerequisites.

Use `IMAGING_MODEL=none` for a credential-free offline installation. Future
updates should be distributed as signed application or model packages, with a
database migration and rollback step. Do not silently replace a clinical model
without recording its version and validating its effect on results.
