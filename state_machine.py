"""
state_machine.py
================
Sprint 2 — Temporal Smoothing & Stable Advice State Machine.

Internal states (5):    STOP | UNCERTAIN | WAIT | SAFE | WALK_FAST
Spoken outputs (4):     "Stop" | "Please wait" | "Cross now" | "Walk faster"

State transitions are gated by an N-frame hysteresis buffer:
  • A new state must persist for `smoothing_frames` consecutive frames
    before it is committed.
  • Low-confidence frames immediately force UNCERTAIN (safety-first).
  • Secondary direction cues appended only when confidence is high.
"""

from dataclasses import dataclass, field

# ─────────────────────────────────────────────────────────────────────────────
# State constants
# ─────────────────────────────────────────────────────────────────────────────
STATE_STOP      = "STOP"
STATE_UNCERTAIN = "UNCERTAIN"
STATE_WAIT      = "WAIT"
STATE_SAFE      = "SAFE"
STATE_WALK_FAST = "WALK_FAST"

ALL_STATES = [STATE_STOP, STATE_UNCERTAIN, STATE_WAIT, STATE_SAFE, STATE_WALK_FAST]

# spoken text + audio file stem for each internal state
_SPOKEN_MAP: dict[str, tuple[str, str]] = {
    STATE_STOP:      ("Stop",        "stop"),
    STATE_UNCERTAIN: ("Please wait", "stop"),
    STATE_WAIT:      ("Please wait", "stop"),
    STATE_SAFE:      ("Cross now",   "walk_normal"),
    STATE_WALK_FAST: ("Walk faster", "walk_fast"),
}


# ─────────────────────────────────────────────────────────────────────────────
# Output struct
# ─────────────────────────────────────────────────────────────────────────────
@dataclass
class StateOutput:
    internal_state: str          # one of ALL_STATES
    spoken_text:    str          # "Stop" / "Please wait" / "Cross now" / "Walk faster"
    audio_stem:     str          # filename stem inside voice_cache/
    confidence:     float        # 0.0–1.0
    risk_score:     float = 0.0  # raw risk value from risk scorer
    secondary_cue:  str   = ""   # optional: "Raise your right hand." etc.

    @property
    def full_spoken(self) -> str:
        """Full spoken sentence including any secondary cue."""
        if self.secondary_cue:
            return f"{self.spoken_text}. {self.secondary_cue}"
        return self.spoken_text


# ─────────────────────────────────────────────────────────────────────────────
# State machine
# ─────────────────────────────────────────────────────────────────────────────
class SafetyStateMachine:
    """
    Hysteresis-gated state machine for crossing safety advice.

    A proposed state must persist for `smoothing_frames` consecutive frames
    before it is committed to the output. This prevents rapid flickering.

    UNCERTAIN is committed immediately on any low-confidence frame —
    it is always safer to pause than to give wrong guidance.
    """

    def __init__(self, smoothing_frames: int = 8, min_confidence: float = 0.70):
        self.smoothing_frames   = smoothing_frames
        self.min_confidence     = min_confidence

        self._current_state = STATE_SAFE
        self._pending_state = STATE_SAFE
        self._pending_count = 0

    # ── public API ────────────────────────────────────────────────────
    @property
    def current_state(self) -> str:
        return self._current_state

    def update(
        self,
        proposed_state: str,
        confidence:     float,
        risk_score:     float = 0.0,
        secondary_cue:  str   = "",
    ) -> StateOutput:
        """
        Apply hysteresis gate and return a StateOutput.

        Args:
            proposed_state: Raw state from risk scorer.
            confidence:     0.0–1.0 from risk scorer.
            risk_score:     0.0–1.0 raw risk value (for logging / display).
            secondary_cue:  Direction hint string (empty if confidence low).

        Returns:
            StateOutput with the gated committed state.
        """
        assert proposed_state in ALL_STATES, f"Unknown state: {proposed_state}"

        # Low confidence → UNCERTAIN immediately (safety-first, no gate)
        if confidence < self.min_confidence:
            self._current_state = STATE_UNCERTAIN
            self._pending_state = STATE_UNCERTAIN
            self._pending_count = 0
            spoken, stem = _SPOKEN_MAP[STATE_UNCERTAIN]
            return StateOutput(
                internal_state = STATE_UNCERTAIN,
                spoken_text    = spoken,
                audio_stem     = stem,
                confidence     = confidence,
                risk_score     = risk_score,
                secondary_cue  = "",
            )

        # Same as current — reset pending accumulator
        if proposed_state == self._current_state:
            self._pending_state = proposed_state
            self._pending_count = 0

        # Continuing to accumulate the same pending state
        elif proposed_state == self._pending_state:
            self._pending_count += 1
            if self._pending_count >= self.smoothing_frames:
                self._current_state = proposed_state
                self._pending_count = 0

        # New candidate state — restart accumulation
        else:
            self._pending_state = proposed_state
            self._pending_count = 1

        spoken, stem = _SPOKEN_MAP[self._current_state]

        # Secondary cue only when confident
        cue = secondary_cue if confidence >= self.min_confidence else ""

        return StateOutput(
            internal_state = self._current_state,
            spoken_text    = spoken,
            audio_stem     = stem,
            confidence     = confidence,
            risk_score     = risk_score,
            secondary_cue  = cue,
        )

    def reset(self):
        """Call between clips or camera restarts."""
        self._current_state = STATE_SAFE
        self._pending_state = STATE_SAFE
        self._pending_count = 0
