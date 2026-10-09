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
