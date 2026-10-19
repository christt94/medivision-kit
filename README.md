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

## Frontend Setup

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port 3000 \
  --dart-define=API_BASE_URL=http://localhost:8000/api
```

`API_BASE_URL` is optional for local development and can point to a deployed
backend for mobile or desktop builds.

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
