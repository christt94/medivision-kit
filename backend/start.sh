#!/bin/bash
# Répertoire réel du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$SCRIPT_DIR"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")/frontend"

echo "🚀 Starting MediVision Kit..."
echo "📁 Backend  : $BACKEND_DIR"
echo "📁 Frontend : $FRONTEND_DIR"

# --- Backend ---
cd "$BACKEND_DIR" || { echo "❌ Backend folder not found: $BACKEND_DIR"; exit 1; }
source ".venv/bin/activate"
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000 &
BACKEND_PID=$!
echo "✅ Backend  → http://localhost:8000 (PID $BACKEND_PID)"

# --- Frontend ---
cd "$FRONTEND_DIR" || { echo "❌ Frontend folder not found: $FRONTEND_DIR"; exit 1; }
flutter run -d chrome &
FRONTEND_PID=$!
echo "✅ Frontend → Chrome (PID $FRONTEND_PID)"

# Arrêt propre avec Ctrl+C
trap "kill $BACKEND_PID $FRONTEND_PID 2>/dev/null; echo '👋 Stopped.'" INT
wait