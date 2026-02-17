"""
Voice Builder Server — Kokoro TTS voice design tool.

FastAPI backend that serves a browser UI for blending Kokoro voices,
previewing TTS output, saving/loading voice presets, and batch-generating
voice lines from intimate-voice-lines.md or voice_lines.json.

Start:
    cd J:\proto-game\single-room\tools\tts
    python voice-builder-server.py          # or via VS Code task

ENV overrides:
    VOICE_BUILDER_PORT   (default 8790)
    KOKORO_MODEL_PATH    path to kokoro-v1.0.onnx
    KOKORO_VOICES_PATH   path to voices-v1.0.bin
"""

from __future__ import annotations

import asyncio
import io
import json
import os
import re
import time
import traceback
from pathlib import Path
from typing import Any

import numpy as np
import soundfile as sf
import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, StreamingResponse

# ── Paths ────────────────────────────────────────────────────────────────────

SCRIPT_DIR: Path = Path(__file__).parent
PROJECT_ROOT: Path = SCRIPT_DIR.parent.parent  # single-room/
PRESETS_DIR: Path = SCRIPT_DIR / "voice-presets"
VOICE_LINES_MD: Path = PROJECT_ROOT.parent / "docs" / "intimate-voice-lines.md"
VOICE_LINES_JSON: Path = SCRIPT_DIR / "voice_lines.json"
OUTPUT_ROOT: Path = PROJECT_ROOT / "assets" / "audio" / "voices"
UI_PATH: Path = SCRIPT_DIR / "voice-builder-ui.html"

MODEL_PATH: str = os.environ.get(
    "KOKORO_MODEL_PATH",
    r"J:\aether\services\ai-pipeline\tts-service\data\kokoro-v1.0.onnx",
)
VOICES_PATH: str = os.environ.get(
    "KOKORO_VOICES_PATH",
    r"J:\aether\services\ai-pipeline\tts-service\data\voices-v1.0.bin",
)

PORT: int = int(os.environ.get("VOICE_BUILDER_PORT", "8790"))
SAMPLE_RATE: int = 24000

# ── Kokoro singleton ─────────────────────────────────────────────────────────

_engine: Any = None
_g2p: Any = None
_available_voices: list[str] = []


def _get_engine():
    global _engine, _available_voices
    if _engine is None:
        from kokoro_onnx import Kokoro

        print(f"Loading Kokoro model: {MODEL_PATH}")
        t0 = time.perf_counter()
        _engine = Kokoro(MODEL_PATH, VOICES_PATH)
        dt = time.perf_counter() - t0
        print(f"Kokoro ready in {dt:.1f}s")
        _available_voices = sorted(_engine.get_voices())
        print(f"Available voices ({len(_available_voices)}): {', '.join(_available_voices[:10])}...")
    return _engine


def _get_g2p():
    global _g2p
    if _g2p is None:
        from misaki import en

        print("Initializing Misaki G2P...")
        _g2p = en.G2P(trf=False, british=False)
    return _g2p


# ── Mood presets ─────────────────────────────────────────────────────────────

MOOD_PRESETS: dict[str, dict[str, Any]] = {
    "neutral": {
        "speed": 1.0,
        "blend_bias": 0.0,
        "description": "Default — natural speaking voice",
    },
    "gentle": {
        "speed": 0.85,
        "blend_bias": -0.15,
        "description": "Soft and slow — afterglow, comfort, tenderness",
    },
    "flirty": {
        "speed": 0.95,
        "blend_bias": -0.05,
        "description": "Slightly breathy and playful",
    },
    "assertive": {
        "speed": 1.05,
        "blend_bias": 0.10,
        "description": "Confident, commanding tone",
    },
    "aggressive": {
        "speed": 1.20,
        "blend_bias": 0.20,
        "description": "Intense, demanding, rough",
    },
    "breathless": {
        "speed": 1.30,
        "blend_bias": 0.05,
        "description": "Fast, gasping — mid-climax",
    },
    "whisper": {
        "speed": 0.80,
        "blend_bias": -0.20,
        "description": "Hushed intimate whisper",
    },
}


# ── Synthesis helpers ────────────────────────────────────────────────────────

def _synthesize(
    text: str,
    voice_a: str,
    voice_b: str | None,
    blend: float,
    speed: float,
    lang: str = "en-us",
) -> np.ndarray:
    """Synthesize text, optionally blending two voices."""
    engine = _get_engine()
    g2p = _get_g2p()
    phonemes, _ = g2p(text)

    if voice_b and voice_b != voice_a and blend > 0.001:
        # Get voice style vectors and blend
        style_a = engine.get_voice_style(voice_a)
        style_b = engine.get_voice_style(voice_b)
        blended = style_a * (1.0 - blend) + style_b * blend
        samples, _ = engine.create(
            phonemes, voice=blended, speed=speed, lang=lang, is_phonemes=True
        )
    else:
        samples, _ = engine.create(
            phonemes, voice=voice_a, speed=speed, lang=lang, is_phonemes=True
        )
    return samples


def _samples_to_wav_bytes(samples: np.ndarray) -> bytes:
    """Convert float32 samples → WAV bytes in memory."""
    buf = io.BytesIO()
    sf.write(buf, samples, SAMPLE_RATE, format="WAV", subtype="PCM_16")
    buf.seek(0)
    return buf.read()


def _sanitize_filename(text: str) -> str:
    slug = text.lower().strip()
    slug = re.sub(r"[^a-z0-9 ]", "", slug)
    slug = "_".join(slug.split())
    return slug[:60]


# ── Voice lines parser ───────────────────────────────────────────────────────

def _parse_voice_lines_md() -> dict[str, list[str]]:
    """Parse intimate-voice-lines.md into {category: [lines]}."""
    if not VOICE_LINES_MD.exists():
        return {}
    text = VOICE_LINES_MD.read_text(encoding="utf-8")
    categories: dict[str, list[str]] = {}
    current_cat: str | None = None
    current_sub: str | None = None

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if line.startswith("## ") and not line.startswith("### "):
            current_cat = line[3:].strip()
            current_sub = None
            if current_cat not in categories:
                categories[current_cat] = []
        elif line.startswith("### "):
            current_sub = line[4:].strip()
            key = f"{current_cat} > {current_sub}" if current_cat else current_sub
            if key not in categories:
                categories[key] = []
            current_cat_save = current_cat
            current_cat = key  # temporarily redirect
        elif line.startswith("- \"") or line.startswith('- "'):
            # Extract quoted text
            match = re.search(r'"(.+)"', line)
            if match and current_cat:
                categories[current_cat].append(match.group(1))
        # Reset subcategory redirect after non-header, non-list
        if line.startswith("## ") and not line.startswith("### "):
            pass  # already handled

    return categories


# ── FastAPI app ──────────────────────────────────────────────────────────────

app = FastAPI(title="Voice Builder", version="1.0.0")


@app.get("/", response_class=HTMLResponse)
async def serve_ui():
    if not UI_PATH.exists():
        raise HTTPException(404, "UI file not found")
    return HTMLResponse(UI_PATH.read_text(encoding="utf-8"))


@app.get("/health")
async def health():
    return {"status": "ok", "port": PORT}


@app.get("/api/voices")
async def list_voices():
    """List all available Kokoro voice IDs."""
    _get_engine()  # ensure loaded
    return {"voices": _available_voices}


@app.get("/api/moods")
async def list_moods():
    """List mood presets with their parameters."""
    return {"moods": MOOD_PRESETS}


@app.post("/api/preview")
async def preview_tts(request: Request):
    """Generate a TTS preview and return WAV audio."""
    body = await request.json()
    text: str = body.get("text", "Hello, this is a voice test.")
    voice_a: str = body.get("voice_a", "af_sky")
    voice_b: str = body.get("voice_b", "")
    blend: float = float(body.get("blend", 0.0))
    speed: float = float(body.get("speed", 1.0))
    mood: str = body.get("mood", "")

    # Apply mood modifiers
    if mood and mood in MOOD_PRESETS:
        mp = MOOD_PRESETS[mood]
        speed *= mp["speed"]
        blend = max(0.0, min(1.0, blend + mp["blend_bias"]))

    try:
        samples = _synthesize(text, voice_a, voice_b, blend, speed)
        wav_bytes = _samples_to_wav_bytes(samples)
        return StreamingResponse(
            io.BytesIO(wav_bytes),
            media_type="audio/wav",
            headers={"Content-Disposition": "inline; filename=preview.wav"},
        )
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(500, f"Synthesis failed: {exc}")


@app.get("/api/presets")
async def list_presets():
    """List saved voice presets."""
    PRESETS_DIR.mkdir(parents=True, exist_ok=True)
    presets = []
    for p in sorted(PRESETS_DIR.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            presets.append({"filename": p.stem, **data})
        except (json.JSONDecodeError, OSError):
            pass
    return {"presets": presets}


@app.post("/api/presets/save")
async def save_preset(request: Request):
    """Save a voice preset."""
    body = await request.json()
    name: str = body.get("name", "").strip()
    if not name:
        raise HTTPException(400, "Preset name required")
    slug = re.sub(r"[^a-z0-9_-]", "", name.lower().replace(" ", "-"))
    if not slug:
        raise HTTPException(400, "Invalid preset name")

    preset = {
        "name": name,
        "voice_a": body.get("voice_a", "af_sky"),
        "voice_b": body.get("voice_b", ""),
        "blend": float(body.get("blend", 0.0)),
        "speed": float(body.get("speed", 1.0)),
        "mood_variants": body.get("mood_variants", {}),
    }
    PRESETS_DIR.mkdir(parents=True, exist_ok=True)
    path = PRESETS_DIR / f"{slug}.json"
    path.write_text(json.dumps(preset, indent=2), encoding="utf-8")
    return {"saved": slug, "path": str(path)}


@app.get("/api/presets/{name}")
async def load_preset(name: str):
    """Load a specific voice preset."""
    path = PRESETS_DIR / f"{name}.json"
    if not path.exists():
        raise HTTPException(404, f"Preset '{name}' not found")
    data = json.loads(path.read_text(encoding="utf-8"))
    return data


@app.delete("/api/presets/{name}")
async def delete_preset(name: str):
    """Delete a voice preset."""
    path = PRESETS_DIR / f"{name}.json"
    if not path.exists():
        raise HTTPException(404, f"Preset '{name}' not found")
    path.unlink()
    return {"deleted": name}


@app.get("/api/voice-lines")
async def get_voice_lines():
    """Return parsed voice line categories from the markdown doc."""
    categories = _parse_voice_lines_md()
    return {"categories": {k: v for k, v in categories.items()}}


@app.post("/api/batch-generate")
async def batch_generate(request: Request):
    """
    Batch-generate WAV files for voice lines.

    Body:
        npc_name: str
        voice_a, voice_b, blend, speed: voice params
        mood_variants: dict  (mood → {blend_bias, speed_mult})
        categories: list[str] | null  (null = all)
        category_moods: dict[str, str]  (category → mood name)
        force: bool  (regenerate existing)
    """
    body = await request.json()
    npc_name: str = body.get("npc_name", "NPC_Custom")
    voice_a: str = body.get("voice_a", "af_sky")
    voice_b: str = body.get("voice_b", "")
    blend: float = float(body.get("blend", 0.0))
    speed: float = float(body.get("speed", 1.0))
    category_moods: dict = body.get("category_moods", {})
    filter_cats: list | None = body.get("categories")
    force: bool = body.get("force", False)

    all_lines = _parse_voice_lines_md()
    if not all_lines:
        raise HTTPException(404, "No voice lines found in markdown")

    generated = 0
    skipped = 0
    failed = 0
    results: list[dict] = []

    for cat_name, lines in all_lines.items():
        if filter_cats and cat_name not in filter_cats:
            continue

        # Determine mood for this category
        mood_name = category_moods.get(cat_name, "neutral")
        mp = MOOD_PRESETS.get(mood_name, MOOD_PRESETS["neutral"])
        cat_speed = speed * mp["speed"]
        cat_blend = max(0.0, min(1.0, blend + mp["blend_bias"]))

        safe_cat = re.sub(r"[^a-z0-9_-]", "", cat_name.lower().replace(" ", "-").replace(">", ""))
        cat_dir = OUTPUT_ROOT / npc_name / safe_cat

        for line_text in lines:
            slug = _sanitize_filename(line_text)
            out_path = cat_dir / f"{slug}.wav"

            if out_path.exists() and not force:
                skipped += 1
                results.append({"line": line_text, "status": "skipped"})
                continue

            try:
                samples = _synthesize(line_text, voice_a, voice_b, cat_blend, cat_speed)
                out_path.parent.mkdir(parents=True, exist_ok=True)
                sf.write(str(out_path), samples, SAMPLE_RATE)
                generated += 1
                results.append({"line": line_text, "status": "ok", "path": str(out_path)})
            except Exception as exc:
                failed += 1
                results.append({"line": line_text, "status": "failed", "error": str(exc)})

    return {
        "npc_name": npc_name,
        "generated": generated,
        "skipped": skipped,
        "failed": failed,
        "total": generated + skipped + failed,
        "results": results,
    }


# ── Main ─────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print(f"\n  Voice Builder → http://127.0.0.1:{PORT}\n")
    uvicorn.run(app, host="127.0.0.1", port=PORT, log_level="info")
