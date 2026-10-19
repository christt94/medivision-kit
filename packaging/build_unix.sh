#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-macos}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND="$ROOT/backend"
FRONTEND="$ROOT/frontend"
VENV="$BACKEND/.venv-packaging"

if [[ "$TARGET" != "macos" && "$TARGET" != "linux" ]]; then
  echo "Usage: $0 [macos|linux]" >&2
  exit 2
fi

command -v flutter >/dev/null || { echo "Flutter is not on PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 is not on PATH" >&2; exit 1; }

cd "$ROOT"
if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install -r "$BACKEND/requirements-packaging.txt"
"$VENV/bin/python" -m PyInstaller --noconfirm --clean --onefile \
  --name medivision_backend --paths "$BACKEND" "$BACKEND/standalone_server.py"

if [[ ! -d "$FRONTEND/$TARGET" ]]; then
  flutter create --platforms="$TARGET" "$FRONTEND"
fi
flutter build "$TARGET" --release \
  --dart-define=API_BASE_URL=http://127.0.0.1:8000/api

if [[ "$TARGET" == "macos" ]]; then
  RELEASE_DIR="$FRONTEND/build/macos/Build/Products/Release/medivision_kit.app/Contents/MacOS"
else
  RELEASE_DIR="$FRONTEND/build/linux/x64/release/bundle"
fi

mkdir -p "$RELEASE_DIR/backend"
cp "$BACKEND/dist/medivision_backend" "$RELEASE_DIR/backend/medivision_backend"
chmod +x "$RELEASE_DIR/backend/medivision_backend"
echo "Standalone $TARGET build created at: $RELEASE_DIR"
