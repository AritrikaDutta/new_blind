# crossing_advisor.py
"""
Decision engine for crossing guidance.

Upgrade (Section 9 — User-Centric Decision System):
  The system now compares each vehicle's TTC against the time the user
  actually needs to cross the road, rather than fixed 2 s / 5 s buckets.

  user_cross_time_sec = ROAD_WIDTH_M / USER_WALK_SPEED_MPS  ≈ 6.7 s

  Decision logic:
    TTC < user_cross_time_sec × STOP_FACTOR      → STOP (vehicle arrives first)
    TTC < user_cross_time_sec × FAST_FACTOR      → WALK FAST / SIGNAL
    TTC ≥ user_cross_time_sec × FAST_FACTOR      → SAFE TO CROSS

VehicleInfo now also carries dist_m and speed_kmh from MotionEstimator
so voice/overlay layers can report real metric values.
"""

import math
from dataclasses import dataclass, field
from typing import List, Optional

@dataclass
class CrossingConfig:
    road_width_m: float = 8.0
    walk_speed_mps: float = 1.2
    use_ai_depth: bool = True
    use_ego_motion: bool = True
    threat_rank_k: int = 3
    smoothing_frames: int = 8
    audio_mode: str = "local"
    safety_margin_sec: float = 1.5
    min_confidence_threshold: float = 0.70

# ---------------------------------------------------------------------------
# Vehicle class sets   (0=bicycle 1=bus 2=car 3=dog 4=motorcycle 5=person
#                       6=scooty 7=toto)
# ---------------------------------------------------------------------------
LIGHT_CLASSES  = {0}              # bicycle
HEAVY_CLASSES  = {1, 2, 4, 6, 7} # bus / car / motorcycle / scooty / toto

CLASS_LABELS = {
    0: "bicycle", 1: "bus",   2: "car",
    3: "dog",     4: "motorcycle", 5: "person",
    6: "scooty",  7: "toto",
}

# ---------------------------------------------------------------------------
# Section 9 — User motion model
# ---------------------------------------------------------------------------
ROAD_WIDTH_M        = 8.0    # typical 2-lane Indian road
USER_WALK_SPEED_MPS = 1.2    # average adult walking speed (m/s)

# Derived: how many seconds the user needs to finish crossing
USER_CROSS_TIME_SEC = ROAD_WIDTH_M / USER_WALK_SPEED_MPS   # ≈ 6.67 s

# Threat multipliers (relative to user crossing time)
#   TTC < USER_CROSS_TIME × STOP_MULT  → STOP
#   TTC < USER_CROSS_TIME × FAST_MULT  → WALK FAST / SIGNAL
STOP_MULT = 1.00   # vehicle arrives before or just as user finishes crossing
FAST_MULT = 1.40   # vehicle arrives within 40 % margin → hurry
# TTC ≥ USER_CROSS_TIME × FAST_MULT → SAFE

STOP_TTC_SEC = USER_CROSS_TIME_SEC * STOP_MULT   # ≈ 6.7 s
FAST_TTC_SEC = USER_CROSS_TIME_SEC * FAST_MULT   # ≈ 9.3 s

# Hard lower-bound: < 2 s is always STOP regardless of road width
HARD_STOP_SEC = 2.0

# Legacy speed thresholds kept for fallback
SPEED_SLOW_KMH = 10.0
SPEED_FAST_KMH = 30.0


# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------
@dataclass
class VehicleInfo:
    """Per-vehicle snapshot passed into the advisor each frame."""
    track_id:    int
    class_id:    int
    dx:          float          # Lateral pixel-rate (ego-corrected px/s)
    dA:          float          # Area growth rate  (px²/s)
    ttc_sec:     float          # Time-to-Collision in seconds

    # Physics-metric fields (from MotionEstimator) ─────────────────────
    dist_m:      float  = 0.0   # Estimated distance in metres
    speed_kmh:   float  = 0.0   # Estimated approach speed (km/h)
    speed_mps:   float  = 0.0   # Estimated approach speed (m/s)

    # Retained fields ───────────────────────────────────────────────────
    cx:          float  = 0.0
    speed_px:    float  = 0.0
    distance_px: float  = 0.0
    approaching: bool   = False
    retreating:  bool   = False    # NEW: bounding box actively shrinking (moving away)
    direction:   str    = "unknown"
    motion_axis: str    = "unknown"  # NEW: "horizontal" | "vertical" | "ambiguous"
    bbox:        tuple  = ()

    @property
    def category(self) -> str:
        if self.class_id in LIGHT_CLASSES:  return "light"
        if self.class_id in HEAVY_CLASSES:  return "heavy"
        return "ignored"

    @property
    def class_label(self) -> str:
        return CLASS_LABELS.get(self.class_id, "unknown")


@dataclass
class CrossingAdvice:
    """Output of the advisor — tells the user what to do."""
    action:       str   # "cross_normal" | "cross_fast" | "signal_hand_left"
                        # | "signal_hand_right" | "stop"
    walking_speed: str  # "normal" | "fast" | "stop"
    signal_hand:  bool
    reason:       str
    threat_level: int   = 0   # 0=safe 1=caution 2=danger
    dist_m:       float = 0.0 # distance of most dangerous vehicle (m)
    speed_kmh:    float = 0.0 # speed of most dangerous vehicle (km/h)
    ttc_sec:      float = float('inf')


# ---------------------------------------------------------------------------
# Advisor
# ---------------------------------------------------------------------------
class CrossingAdvisor:
    """
    Evaluates all approaching vehicles and returns a single CrossingAdvice.

    Decision is based on the user-centric model (Section 9):
        Does the user have enough time to cross before the vehicle arrives?
    """

    def __init__(
        self,
        cooldown_frames:    int   = 60,
        escalation_frames:  int   = 5,
        road_width_m:       float = ROAD_WIDTH_M,
        walk_speed_mps:     float = USER_WALK_SPEED_MPS,
    ):
        self.road_width_m    = road_width_m
        self.walk_speed_mps  = walk_speed_mps

        # Derived thresholds
        cross_time           = road_width_m / walk_speed_mps
        self.stop_ttc_sec    = max(HARD_STOP_SEC, cross_time * STOP_MULT)
        self.fast_ttc_sec    = cross_time * FAST_MULT

        # Hysteresis state
        self.cooldown_frames    = cooldown_frames
        self.escalation_frames  = escalation_frames
        self.current_threat     = 0
        self.current_action     = "cross_normal"
        self.current_walk       = "normal"
        self.current_signal     = False
        self.current_signal_dir = None
        self.current_reason     = "Safe to cross"
        self.current_dist_m     = 0.0
        self.current_speed_kmh  = 0.0
        self.current_ttc_sec    = float('inf')

        self.frames_since_high_threat = 0
        self.escalation_counter = 0
        self.pending_threat     = 0
        self.pending_action     = "cross_normal"
        self.pending_walk       = "normal"
        self.pending_signal     = False
        self.pending_signal_dir = None
        self.pending_reason     = "Safe to cross"
        self.pending_dist_m     = 0.0
        self.pending_speed_kmh  = 0.0
        self.pending_ttc_sec    = float('inf')

    # ------------------------------------------------------------------
    # Per-vehicle threat scoring (Section 9.2)
    # ------------------------------------------------------------------
    def _vehicle_threat(self, v: VehicleInfo) -> dict:
        """Score a single vehicle using the user-crossing time model."""
        if v.category not in ("light", "heavy"):
            return self._safe_result(v, f"Tracking {v.class_label} — not a threat")

        # Moving away → no threat (use explicit retreating flag first, then fallback)
        if getattr(v, "retreating", False):
            return self._safe_result(v, f"{v.class_label} retreating — no threat")
        if not v.approaching and v.dA <= 0 and v.speed_mps < 0.1:
            return self._safe_result(v, f"{v.class_label} moving away — no threat")

        ttc = v.ttc_sec
        if ttc == float('inf'):
            # Looming (area growing) but no finite TTC — use hard stop check
            if v.dA > 0 and v.dist_m < 5.0:
                ttc = 1.5   # treat as imminent
            else:
                return self._safe_result(v, f"{v.class_label} safe — no TTC")

        threat, walk, signal, signal_dir, reason = 0, "normal", False, None, ""

        # ── Tier 3: STOP ── vehicle arrives before user finishes crossing
        if ttc < self.stop_ttc_sec:
            threat = 2
            walk   = "stop"
            reason = (
                f"{v.class_label} {v.dist_m:.1f}m away, "
                f"TTC {ttc:.1f}s — STOP"
            )

        # ── Tier 2: WALK FAST / SIGNAL ── tight window
        elif ttc < self.fast_ttc_sec:
            threat = 1
            walk   = "fast"
            # Determine which side the vehicle is coming from (Section 9.3)
            if v.direction == "left_to_right" or v.dx > 15:
                signal = True
                signal_dir = "left"
                reason = (
                    f"{v.class_label} from LEFT ({v.dist_m:.1f}m, "
                    f"{v.speed_kmh:.0f}km/h) — signal RIGHT hand"
                )
            elif v.direction == "right_to_left" or v.dx < -15:
                signal = True
                signal_dir = "right"
                reason = (
                    f"{v.class_label} from RIGHT ({v.dist_m:.1f}m, "
                    f"{v.speed_kmh:.0f}km/h) — signal LEFT hand"
                )
            else:
                reason = (
                    f"{v.class_label} straight ahead ({v.dist_m:.1f}m, "
                    f"{v.speed_kmh:.0f}km/h) — walk fast"
                )

        # ── Tier 1: SAFE ── plenty of time
        else:
            threat = 0
            walk   = "normal"
            reason = (
                f"{v.class_label} {v.dist_m:.1f}m, "
                f"TTC {ttc:.1f}s — safe to cross"
            )

        return {
            "threat":     threat,
            "walk":       walk,
            "signal":     signal,
            "signal_dir": signal_dir,
            "reason":     reason,
            "track_id":   v.track_id,
            "cx":         v.cx,
            "dist_m":     v.dist_m,
            "speed_kmh":  v.speed_kmh,
            "ttc_sec":    ttc,
        }

    # ------------------------------------------------------------------
    # Aggregate across all vehicles
    # ------------------------------------------------------------------
    def assess(self, vehicles: List[VehicleInfo], frame_width: int) -> CrossingAdvice:
        """Evaluate all tracked vehicles and return the most urgent advice."""

        approaching = [v for v in vehicles if v.approaching or v.dA > 0]

        if not approaching:
            return CrossingAdvice(
                action        = "cross_normal",
                walking_speed = "normal",
                signal_hand   = False,
                reason        = "No approaching vehicles — safe to cross",
                threat_level  = 0,
            )

        # ── Step 1: Instantaneous threat ──────────────────────────────
        worst_threat    = 0
        worst_walk      = "normal"
        any_signal      = False
        signal_dir      = None
        worst_reason    = ""
        worst_dist_m    = 0.0
        worst_speed_kmh = 0.0
        worst_ttc_sec   = float('inf')

        t_results = [self._vehicle_threat(v) for v in approaching]

        for t in t_results:
            if t["threat"] > worst_threat:
                worst_threat    = t["threat"]
                worst_reason    = t["reason"]
                worst_dist_m    = t["dist_m"]
                worst_speed_kmh = t["speed_kmh"]
                worst_ttc_sec   = t["ttc_sec"]

        for t in t_results:
            if t["threat"] == worst_threat and worst_threat > 0:
                if t["walk"] == "stop":
                    worst_walk = "stop"
                elif t["walk"] == "fast" and worst_walk != "stop":
                    worst_walk = "fast"
                if t["signal"]:
                    any_signal  = True
                    # Direction is determined by which side the cx is on
                    signal_dir  = "left" if t["cx"] < (frame_width / 2) else "right"

        # Map to action label
        if worst_walk == "stop":
            instant_action = "stop"
        elif any_signal:
            # signal_dir is "left" when vehicle is on left side →
            # user should raise the hand facing TOWARD traffic (right hand)
            instant_action = (
                "signal_hand_right" if signal_dir == "left"
                else "signal_hand_left"
            )
        elif worst_walk == "fast":
            instant_action = "cross_fast"
        else:
            instant_action = "cross_normal"

        instant_reason = worst_reason or "Safe to cross"

        # ── Step 2: Hysteresis / debounce ────────────────────────────
        if worst_threat > self.current_threat:
            if worst_threat == self.pending_threat:
                self.escalation_counter += 1
            else:
                self.pending_threat     = worst_threat
                self.pending_action     = instant_action
                self.pending_walk       = worst_walk
                self.pending_signal     = any_signal
                self.pending_signal_dir = signal_dir
                self.pending_reason     = instant_reason
                self.pending_dist_m     = worst_dist_m
                self.pending_speed_kmh  = worst_speed_kmh
                self.pending_ttc_sec    = worst_ttc_sec
                self.escalation_counter = 1

            if self.escalation_counter >= self.escalation_frames:
                self._commit_pending()

        elif worst_threat == self.current_threat:
            self.escalation_counter       = 0
            self.frames_since_high_threat = 0
            # Keep metric info fresh even when threat is stable
            self.current_dist_m    = worst_dist_m
            self.current_speed_kmh = worst_speed_kmh
            self.current_ttc_sec   = worst_ttc_sec

        else:
            self.escalation_counter = 0
            self.frames_since_high_threat += 1
            if self.frames_since_high_threat >= self.cooldown_frames:
                self.current_threat     = worst_threat
                self.current_action     = instant_action
                self.current_walk       = worst_walk
                self.current_signal     = any_signal
                self.current_signal_dir = signal_dir
                self.current_reason     = instant_reason
                self.current_dist_m     = worst_dist_m
                self.current_speed_kmh  = worst_speed_kmh
                self.current_ttc_sec    = worst_ttc_sec
                self.frames_since_high_threat = 0

        return CrossingAdvice(
            action        = self.current_action,
            walking_speed = self.current_walk,
            signal_hand   = self.current_signal,
            reason        = self.current_reason,
            threat_level  = self.current_threat,
            dist_m        = self.current_dist_m,
            speed_kmh     = self.current_speed_kmh,
            ttc_sec       = self.current_ttc_sec,
        )

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _commit_pending(self):
        self.current_threat     = self.pending_threat
        self.current_action     = self.pending_action
        self.current_walk       = self.pending_walk
        self.current_signal     = self.pending_signal
        self.current_signal_dir = self.pending_signal_dir
        self.current_reason     = self.pending_reason
        self.current_dist_m     = self.pending_dist_m
        self.current_speed_kmh  = self.pending_speed_kmh
        self.current_ttc_sec    = self.pending_ttc_sec
        self.frames_since_high_threat = 0

    @staticmethod
    def _safe_result(v: VehicleInfo, reason: str) -> dict:
        return {
            "threat":     0,
            "walk":       "normal",
            "signal":     False,
            "signal_dir": None,
            "reason":     reason,
            "track_id":   v.track_id,
            "cx":         v.cx,
            "dist_m":     v.dist_m,
            "speed_kmh":  v.speed_kmh,
            "ttc_sec":    float('inf'),
        }

    @staticmethod
    def _ttc_bucket(ttc_sec: float) -> str:
        """Legacy helper retained for any external callers."""
        if ttc_sec is None or ttc_sec > FAST_TTC_SEC:
            return "far"
        if ttc_sec < HARD_STOP_SEC:
            return "close"
        return "medium"
