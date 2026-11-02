#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
animated-wallpaper-picker.sh
==============================================================================
Emite una fila por fondo animado disponible en la biblioteca de wallmotion:

  key <TAB> label <TAB> image_thumbnail_path

Consumido por el panel ImagePickerPanel de Quickshell.
==============================================================================
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

CFG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wallmotion"
LIB_DIR = CFG_DIR / "library"
THUMB_DIR = CFG_DIR / "thumbs"
LIB_JSON = CFG_DIR / "library.json"

VIDEO_EXTS = {".mp4", ".webm", ".mkv", ".mov", ".m4v", ".avi", ".gif", ".ogv"}


def ensure_thumbnail(video_path: Path, thumb_path: Path) -> bool:
    """Genera miniatura JPG para el vídeo si no existe o está vacía."""
    if thumb_path.exists() and thumb_path.stat().st_size > 1000:
        return True
    if not shutil.which("ffmpeg"):
        return False
    THUMB_DIR.mkdir(parents=True, exist_ok=True)
    cmd = [
        "ffmpeg", "-v", "quiet", "-nostdin", "-y",
        "-ss", "00:00:01",
        "-i", str(video_path),
        "-frames:v", "1",
        "-vf", "scale=480:-2:flags=bilinear",
        "-q:v", "5",
        str(thumb_path)
    ]
    try:
        subprocess.run(cmd, capture_output=True, timeout=15, check=False)
        return thumb_path.exists() and thumb_path.stat().st_size > 1000
    except (subprocess.SubprocessError, OSError):
        return False


def main():
    items = []
    seen_ids = set()

    # 1. Cargar biblioteca registrada en library.json
    if LIB_JSON.exists():
        try:
            raw = json.loads(LIB_JSON.read_text("utf-8"))
            if isinstance(raw, list):
                items = raw
        except Exception:
            items = []

    # 2. Emitir entradas registradas válidas
    for it in items:
        item_id = it.get("id") or it.get("slug")
        if not item_id:
            continue
        seen_ids.add(item_id)
        
        video_path = Path(it.get("path", ""))
        thumb_path = Path(it.get("thumb", "")) if it.get("thumb") else (THUMB_DIR / f"{item_id}.jpg")
        
        if not video_path.exists():
            continue
            
        if not thumb_path.exists() or thumb_path.stat().st_size <= 1000:
            ensure_thumbnail(video_path, thumb_path)
            
        title = it.get("title") or item_id.replace("-", " ").replace("_", " ").title()
        thumb_str = str(thumb_path) if thumb_path.exists() else ""
        sys.stdout.write(f"{item_id}\t{title}\t{thumb_str}\n")

    # 3. Detectar archivos de vídeo en library/ no registrados aún
    if LIB_DIR.is_dir():
        for file in sorted(LIB_DIR.iterdir()):
            if file.is_file() and file.suffix.lower() in VIDEO_EXTS:
                file_id = file.stem
                if file_id in seen_ids:
                    continue
                seen_ids.add(file_id)
                thumb_path = THUMB_DIR / f"{file_id}.jpg"
                ensure_thumbnail(file, thumb_path)
                title = file_id.replace("-", " ").replace("_", " ").title()
                thumb_str = str(thumb_path) if thumb_path.exists() else ""
                sys.stdout.write(f"{file_id}\t{title}\t{thumb_str}\n")


if __name__ == "__main__":
    main()

