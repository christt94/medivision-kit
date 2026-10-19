"""Entry point used by the packaged desktop application."""

import os

# Set this before importing the application so all runtime paths (database,
# uploads, reports, and model files) resolve beside the packaged backend.
os.environ.setdefault("MEDIVISION_RUNTIME_ROOT", os.getcwd())

import uvicorn
from app.main import app


if __name__ == "__main__":
    uvicorn.run(
        app,
        host=os.getenv("MEDIVISION_HOST", "127.0.0.1"),
        port=int(os.getenv("MEDIVISION_PORT", "8000")),
        reload=False,
        workers=1,
    )
