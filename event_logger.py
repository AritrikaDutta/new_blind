"""
event_logger.py
===============
Sprint 5 — Structured JSON-lines event logger.

Writes one JSON object per significant event (state change or periodic tick)
to  crossing_events.jsonl  in the project directory.

Each record contains:
    timestamp_sec, frame, advice_state, spoken_text, confidence, risk_score,
    top_vehicle_id, ttc_sec, dist_m, speed_kmh, secondary_cue,
    false_safe_flag (True when system said SAFE but TTC < safe_ttc).

Usage:
    from event_logger import EventLogger
    logger = EventLogger()
    logger.log(frame_idx, state_output, top_vehicle, safe_ttc)
    logger.close()
"""

from __future__ import annotations
import json
import time
import os
from typing import Optional
from state_machine import StateOutput, STATE_SAFE
from crossing_advisor import VehicleInfo


class EventLogger:
    """
    Appends structured JSON-line records to `crossing_events.jsonl`.
    Only logs when the internal state changes OR every `tick_frames` frames.
    """

    def __init__(
        self,
        path:        str = "crossing_events.jsonl",
        tick_frames: int = 30,        # periodic log even when state is stable
    ):
        self.path        = path
        self.tick_frames = tick_frames
        self._last_state = None
        self._frame_mod  = 0
        self._fp         = open(path, "a", encoding="utf-8")
        self.false_safe_count   = 0
        self.total_safe_frames  = 0
        self.state_switches     = 0
        self._prev_state        = None

    # ──────────────────────────────────────────────────────────────────
    def log(
        self,
        frame_idx:   int,
        state_out:   StateOutput,
        top_vehicle: Optional[VehicleInfo] = None,
        safe_ttc:    float = 6.67,
    ) -> bool:
        """
        Write a log record if the state changed or tick interval reached.

        Returns True if a record was written (useful for testing).
        """
        state_changed   = (state_out.internal_state != self._last_state)
        tick_hit        = (self._frame_mod % self.tick_frames == 0)

        if not (state_changed or tick_hit):
            self._frame_mod += 1
            return False

        # ── False-safe detection (primary safety KPI) ─────────────────
        false_safe = False
        if state_out.internal_state == STATE_SAFE and top_vehicle is not None:
            if (top_vehicle.approaching and
                    top_vehicle.ttc_sec != float("inf") and
                    top_vehicle.ttc_sec < safe_ttc):
                false_safe = True
                self.false_safe_count += 1

        if state_out.internal_state == STATE_SAFE:
            self.total_safe_frames += 1

        if state_changed and self._prev_state is not None:
            self.state_switches += 1

        record = {
            "timestamp_sec":  round(time.time(), 3),
            "frame":          frame_idx,
            "advice_state":   state_out.internal_state,
            "spoken_text":    state_out.spoken_text,
            "secondary_cue":  state_out.secondary_cue,
            "confidence":     round(state_out.confidence, 3),
            "risk_score":     round(state_out.risk_score, 3),
            "top_vehicle_id": top_vehicle.track_id if top_vehicle else None,
            "ttc_sec":        round(top_vehicle.ttc_sec, 2) if top_vehicle and top_vehicle.ttc_sec != float("inf") else None,
            "dist_m":         round(top_vehicle.dist_m, 2)  if top_vehicle else None,
            "speed_kmh":      round(top_vehicle.speed_kmh, 1) if top_vehicle else None,
            "false_safe":     false_safe,
        }

        self._fp.write(json.dumps(record) + "\n")
        self._fp.flush()

        self._last_state = state_out.internal_state
        self._prev_state = state_out.internal_state
        self._frame_mod += 1
        return True

    # ──────────────────────────────────────────────────────────────────
    def summary(self) -> dict:
        """Return aggregated safety metrics (call after processing ends)."""
        false_safe_rate = (
            self.false_safe_count / max(1, self.total_safe_frames)
        )
        return {
            "false_safe_count":   self.false_safe_count,
            "total_safe_frames":  self.total_safe_frames,
            "false_safe_rate":    round(false_safe_rate, 4),
            "state_switches":     self.state_switches,
            "log_path":           os.path.abspath(self.path),
        }

    def close(self):
        """Flush and close the log file."""
        self._fp.flush()
        self._fp.close()

    def __del__(self):
        try:
            self._fp.close()
        except Exception:
            pass
