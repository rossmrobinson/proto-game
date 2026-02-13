"""BPM Loopback Helper — WASAPI system audio capture + BPM detection.

Captures system audio via WASAPI loopback (Windows), analyses onsets in the
bass band, and exposes the current BPM estimate over a tiny HTTP endpoint.

Dependencies (pip install):
    soundcard   — cross-platform audio capture with loopback support
    numpy       — fast DSP

Usage:
    python bpm_loopback_helper.py --port 8799

The Godot BPMExternalListener polls GET /bpm and receives:
    {"bpm": 120.5, "confidence": 0.8}
"""

import argparse
import json
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Any

import numpy as np

try:
    import soundcard as sc
except ImportError:
    print("[bpm_loopback_helper] ERROR: 'soundcard' package not installed.")
    print("  pip install soundcard numpy")
    raise SystemExit(1)

# ── Globals ──────────────────────────────────────────────────────────────────

current_bpm: float = 0.0
confidence: float = 0.0
lock = threading.Lock()

# ── BPM Analysis ─────────────────────────────────────────────────────────────

SAMPLE_RATE = 44100
CHUNK_SIZE = 2048
MIN_BPM = 60.0
MAX_BPM = 180.0
ONSET_THRESHOLD = 1.5
SMOOTHING = 0.9


def analyse_loop() -> None:
    """Continuously capture system audio and detect BPM."""
    global current_bpm, confidence

    # Get default loopback device (system audio output mirrored)
    try:
        loopback = sc.get_microphone(
            id=str(sc.default_speaker().name),
            include_loopback=True,
        )
    except Exception as exc:
        print(f"[bpm_loopback_helper] Could not open loopback device: {exc}")
        return

    energy_history: list[float] = []
    onset_times: list[float] = []
    raw_bpm: float = 0.0

    print(f"[bpm_loopback_helper] Capturing from: {loopback.name}")

    with loopback.recorder(samplerate=SAMPLE_RATE, channels=1) as recorder:
        while True:
            data = recorder.record(numframes=CHUNK_SIZE)
            mono = data[:, 0] if data.ndim > 1 else data

            # RMS energy
            energy = float(np.sqrt(np.mean(mono ** 2)))
            energy_history.append(energy)
            if len(energy_history) > 60:
                energy_history.pop(0)

            avg_energy = sum(energy_history) / len(energy_history) if energy_history else 0.0

            # Onset detection
            now = time.monotonic()
            if avg_energy > 1e-5 and energy > avg_energy * ONSET_THRESHOLD:
                if not onset_times or (now - onset_times[-1]) > 0.2:
                    onset_times.append(now)
                    if len(onset_times) > 16:
                        onset_times.pop(0)

                    if len(onset_times) >= 4:
                        intervals = [
                            onset_times[i] - onset_times[i - 1]
                            for i in range(1, len(onset_times))
                            if onset_times[i] - onset_times[i - 1] > 0
                        ]
                        if intervals:
                            intervals.sort()
                            median = intervals[len(intervals) // 2]
                            if median > 0:
                                detected = 60.0 / median
                                while detected < MIN_BPM:
                                    detected *= 2
                                while detected > MAX_BPM:
                                    detected /= 2
                                if MIN_BPM <= detected <= MAX_BPM:
                                    raw_bpm = detected
                                    with lock:
                                        current_bpm = current_bpm * SMOOTHING + raw_bpm * (1 - SMOOTHING)
                                        confidence = min(len(onset_times) / 12.0, 1.0)


# ── HTTP Server ──────────────────────────────────────────────────────────────

class BPMHandler(BaseHTTPRequestHandler):
    """Minimal JSON endpoint."""

    def do_GET(self) -> None:   # noqa: N802
        if self.path == "/bpm":
            with lock:
                payload: dict[str, Any] = {
                    "bpm": round(current_bpm, 1),
                    "confidence": round(confidence, 2),
                }
            body = json.dumps(payload).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/health":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format: str, *args: Any) -> None:
        # Suppress per-request logging
        pass


def main() -> None:
    parser = argparse.ArgumentParser(description="BPM Loopback Helper")
    parser.add_argument("--port", type=int, default=8799)
    args = parser.parse_args()

    # Start analysis thread
    t = threading.Thread(target=analyse_loop, daemon=True)
    t.start()

    # Start HTTP server
    server = HTTPServer(("127.0.0.1", args.port), BPMHandler)
    print(f"[bpm_loopback_helper] HTTP server on http://127.0.0.1:{args.port}/bpm")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
