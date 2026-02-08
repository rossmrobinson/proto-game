"""
Batch Voice Line Generator for Proto-Game
==========================================
Reads voice_lines.json, generates .wav files via Kokoro TTS,
and drops them into assets/audio/voices/<npc_name>/<category>/

Usage:
    cd J:\proto-game\single-room\tools\tts
    .venv\Scripts\python.exe generate_voices.py

Optionally filter by NPC or category:
    .venv\Scripts\python.exe generate_voices.py --npc NPC_Alpha
    .venv\Scripts\python.exe generate_voices.py --category greetings
    .venv\Scripts\python.exe generate_voices.py --force   (regenerate all)
"""

import argparse
import json
import os
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR: Path = Path(__file__).parent
PROJECT_ROOT: Path = SCRIPT_DIR.parent.parent  # single-room/
VOICE_LINES_PATH: Path = SCRIPT_DIR / "voice_lines.json"
OUTPUT_ROOT: Path = PROJECT_ROOT / "assets" / "audio" / "voices"

# Kokoro model files — shared from the aether TTS service install
MODEL_PATH: str = os.environ.get(
    "KOKORO_MODEL_PATH",
    r"J:\aether\services\ai-pipeline\tts-service\data\kokoro-v1.0.onnx",
)
VOICES_PATH: str = os.environ.get(
    "KOKORO_VOICES_PATH",
    r"J:\aether\services\ai-pipeline\tts-service\data\voices-v1.0.bin",
)

SAMPLE_RATE: int = 24000  # Kokoro default


def load_voice_lines() -> dict:
    """Load the voice lines definition file."""
    if not VOICE_LINES_PATH.exists():
        print(f"ERROR: {VOICE_LINES_PATH} not found.")
        sys.exit(1)
    with open(VOICE_LINES_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def init_kokoro():
    """Initialize the Kokoro TTS engine."""
    from kokoro_onnx import Kokoro

    print(f"Loading Kokoro model: {MODEL_PATH}")
    print(f"Loading voices:       {VOICES_PATH}")
    t0 = time.perf_counter()
    engine = Kokoro(MODEL_PATH, VOICES_PATH)
    dt = time.perf_counter() - t0
    print(f"Kokoro ready in {dt:.1f}s")
    return engine


def init_g2p():
    """Initialize the Misaki grapheme-to-phoneme converter."""
    from misaki import en

    print("Initializing Misaki G2P...")
    g2p = en.G2P(trf=False, british=False)
    return g2p


def sanitize_filename(text: str) -> str:
    """Turn a voice line into a safe filename slug."""
    slug = text.lower().strip()
    # Keep only alphanumeric, spaces (converted to underscores)
    slug = "".join(c if c.isalnum() or c == " " else "" for c in slug)
    slug = "_".join(slug.split())
    return slug[:60]  # Cap length


def generate_line(
    engine,
    g2p,
    text: str,
    voice: str,
    speed: float,
    output_path: Path,
    lang: str = "en-us",
) -> bool:
    """Generate a single voice line and save as .wav."""
    try:
        # Phonemize
        phonemes, _ = g2p(text)
        # Synthesize
        samples, _sr = engine.create(
            phonemes, voice=voice, speed=speed, lang=lang, is_phonemes=True
        )
        # Ensure output dir exists
        output_path.parent.mkdir(parents=True, exist_ok=True)
        # Write wav
        sf.write(str(output_path), samples, SAMPLE_RATE)
        return True
    except Exception as e:
        print(f"  FAILED: {e}")
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Batch generate NPC voice lines")
    parser.add_argument("--npc", help="Only generate for this NPC name")
    parser.add_argument("--category", help="Only generate this category")
    parser.add_argument(
        "--force", action="store_true", help="Regenerate even if file exists"
    )
    parser.add_argument("--dry-run", action="store_true", help="Show what would be generated")
    args = parser.parse_args()

    data = load_voice_lines()
    npcs: list = data.get("npcs", [])

    if not npcs:
        print("No NPCs defined in voice_lines.json")
        return

    # Count total lines
    total = 0
    for npc in npcs:
        if args.npc and npc["name"] != args.npc:
            continue
        for cat in npc.get("categories", []):
            if args.category and cat["name"] != args.category:
                continue
            total += len(cat.get("lines", []))

    print(f"\n{'DRY RUN — ' if args.dry_run else ''}Generating {total} voice lines\n")

    if args.dry_run:
        for npc in npcs:
            if args.npc and npc["name"] != args.npc:
                continue
            voice = npc.get("voice", "af_sky")
            speed = npc.get("speed", 1.0)
            print(f"NPC: {npc['name']}  (voice={voice}, speed={speed})")
            for cat in npc.get("categories", []):
                if args.category and cat["name"] != args.category:
                    continue
                print(f"  {cat['name']}: {len(cat['lines'])} lines")
                for line in cat["lines"]:
                    slug = sanitize_filename(line)
                    path = OUTPUT_ROOT / npc["name"] / cat["name"] / f"{slug}.wav"
                    exists = "EXISTS" if path.exists() else "NEW"
                    print(f"    [{exists}] {line[:50]}")
        return

    # Initialize engine
    engine = init_kokoro()
    g2p = init_g2p()

    generated = 0
    skipped = 0
    failed = 0

    for npc in npcs:
        if args.npc and npc["name"] != args.npc:
            continue

        voice: str = npc.get("voice", "af_sky")
        speed: float = npc.get("speed", 1.0)
        lang: str = npc.get("lang", "en-us")
        npc_name: str = npc["name"]

        print(f"\n── {npc_name} (voice={voice}, speed={speed}) ──")

        for cat in npc.get("categories", []):
            if args.category and cat["name"] != args.category:
                continue

            cat_name: str = cat["name"]
            # Allow per-category voice/speed overrides
            cat_voice: str = cat.get("voice", voice)
            cat_speed: float = cat.get("speed", speed)

            print(f"  {cat_name}:")

            for line_text in cat["lines"]:
                slug = sanitize_filename(line_text)
                out_path = OUTPUT_ROOT / npc_name / cat_name / f"{slug}.wav"

                if out_path.exists() and not args.force:
                    skipped += 1
                    continue

                t0 = time.perf_counter()
                ok = generate_line(engine, g2p, line_text, cat_voice, cat_speed, out_path, lang)
                dt = time.perf_counter() - t0

                if ok:
                    generated += 1
                    print(f"    ✓ {slug}.wav ({dt:.2f}s)")
                else:
                    failed += 1
                    print(f"    ✗ {line_text[:40]}...")

    print(f"\n── Done ──")
    print(f"  Generated: {generated}")
    print(f"  Skipped:   {skipped} (already exist)")
    print(f"  Failed:    {failed}")
    print(f"  Output:    {OUTPUT_ROOT}")


if __name__ == "__main__":
    main()
