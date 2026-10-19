#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🚀 Starting MediVision Kit..."

# ── Backend ──────────────────────────────────────────────────────────────────
pkill -f "uvicorn app.main:app" 2>/dev/null || true
sleep 1
cd "$BASE/backend"
source .venv/bin/activate
uvicorn app.main:app --reload --port 8000 &
echo "✅ Backend  → http://localhost:8000"

# ── Frontend ─────────────────────────────────────────────────────────────────
cd "$BASE/frontend"
flutter run -d chrome --web-port 3000 &
echo "✅ Frontend → Chrome"

wait
