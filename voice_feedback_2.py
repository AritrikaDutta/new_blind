import os
import time
from typing import Optional, Dict

_last_alert_event: Dict[str, object] = {"label": None, "ts": 0.0, "seq": 0}

# ---------------------------------------------------------------------------
# Mapping from CrossingAdvice action → audio file stem
# The corresponding .mp3 files should live in voice_cache/.
# ---------------------------------------------------------------------------
ACTION_AUDIO_MAP = {
    "cross_normal":       "walk_normal",
    "cross_fast":         "walk_fast",
    "signal_hand_left":   "signal_hand_left",
    "signal_hand_right":  "signal_hand_right",
    "stop":               "stop",
}

# ---------------------------------------------------------------------------
# Richer directional templates (Section 9.3 — Directional Guidance)
# These labels are emitted so the Streamlit / IoT layer can play the right clip.
# ---------------------------------------------------------------------------
DIRECTION_LABELS = {
    # action key → (audio_stem, spoken text for TTS fallback)
    "cross_normal":       ("walk_normal",        "Safe to cross"),
    "cross_fast":         ("walk_fast",           "Walk faster"),
    "signal_hand_left":   ("signal_hand_left",    "Raise your left hand, vehicle from your right"),
    "signal_hand_right":  ("signal_hand_right",   "Raise your right hand, vehicle from your left"),
    "stop":               ("stop",                "Stop — vehicle approaching"),
}


class VoiceAlertManager:
    def __init__(self, temp_audio_dir: str = "voice_cache", cooldown_seconds: float = 8.0):
        self.last_state: Optional[str] = None   # last emitted label
        self.last_time:  float         = 0.0
        self.cooldown:   float         = cooldown_seconds
        self.audio_folder = temp_audio_dir
        os.makedirs(self.audio_folder, exist_ok=True)

    # ─── resolve a pre-recorded mp3 ──────────────────────────────────────
    def _resolve_prerecorded(self, stem: str) -> Optional[str]:
        candidates = [
            os.path.join(self.audio_folder, f"{stem}.mp3"),
            os.path.join(self.audio_folder, f"{stem.lower()}.mp3"),
            os.path.join(self.audio_folder, f"{stem.title()}.mp3"),
            os.path.join(self.audio_folder, f"{stem.upper()}.mp3"),
        ]
        for p in candidates:
            if os.path.exists(p):
                return p
        return None

    # ─── emit event so Streamlit / IoT layer can pick it up ──────────────
    def _emit_event(self, label: str, spoken_text: str = ""):
        global _last_alert_event
        _last_alert_event = {
            "label":       label,
            "spoken_text": spoken_text,
            "ts":          time.time(),
            "seq":         int(_last_alert_event.get("seq", 0)) + 1,
        }
        print(f"[VoiceEvent] {_last_alert_event}")

    # ─── legacy interface (simple safe/unsafe) ────────────────────────────
    def update_and_speak(self, is_safe: bool, timestamp: float):
        """Map boolean safe → label and emit."""
        label = "walk_normal" if is_safe else "stop"
        self._maybe_emit(label)

    # ─── NEW: richer interface driven by CrossingAdvice ──────────────────
    def update_with_advice(self, advice, timestamp: float):
        """
        Accept a CrossingAdvice object (from crossing_advisor.py) and emit
        the appropriate voice label with spoken text.

        Section 9.3 — Directional Guidance:
            signal_hand_right → "Raise your right hand, vehicle from your left"
            signal_hand_left  → "Raise your left hand, vehicle from your right"
        """
        stem, spoken = DIRECTION_LABELS.get(
            advice.action, ("stop", "Stop — vehicle approaching")
        )
        self._maybe_emit(stem, spoken_text=spoken)

    # ─── common throttle / de-dupe logic ─────────────────────────────────
    def _maybe_emit(self, label: str, spoken_text: str = ""):
        now = time.time()
        if self.last_state != label or (now - self.last_time) > self.cooldown:
            path = self._resolve_prerecorded(label)
            if not path:
                print(f"[VoiceWarn] Missing audio for '{label}' in {self.audio_folder}.")
            self._emit_event(label, spoken_text=spoken_text)
            self.last_time  = now
            self.last_state = label


def get_last_alert_event() -> Dict[str, object]:
    """Return the latest alert event dict: {label, spoken_text, ts, seq}."""
    return dict(_last_alert_event)
