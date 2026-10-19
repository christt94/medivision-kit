"""Filesystem locations that work in source and packaged desktop builds."""

import os
from pathlib import Path


RUNTIME_ROOT = Path(os.getenv("MEDIVISION_RUNTIME_ROOT", Path.cwd())).resolve()


def runtime_path(configured_path: str) -> Path:
    path = Path(configured_path)
    return path if path.is_absolute() else RUNTIME_ROOT / path
