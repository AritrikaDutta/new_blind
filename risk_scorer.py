"""
risk_scorer.py
==============
Sprint 3 — Threat Ranking & Risk Scoring.

Two public functions:
  1. rank_threats(vehicle_infos, crossing_zone, k)
       → top-K VehicleInfo sorted by threat score.

  2. compute_risk(top_k, crossing_zone, all_zones, frame_width, config, crossing_progress)
       → (risk_score, confidence, secondary_cue, proposed_state)

──────────────────────────────────────────────────────────────────────────────
GEOMETRIC SAFETY MODEL  (primary decision term)
──────────────────────────────────────────────────────────────────────────────

The user's intended model:

  Case 1 – HORIZONTAL motion (left_to_right / right_to_left):
    a. Near the user (dist_m ≤ NEAR_M)   → HIGH risk (unsafe)
    b. Far from user (dist_m >  FAR_M)   → LOW  risk (safe pass-through)

  Case 2 – VERTICAL motion (straight toward / away):
    a. Moving AWAY (retreating=True, dA < 0)  → SAFE  (risk ≈ 0)
    b. Moving TOWARD (approaching=True):
        i.  Currently in CROSSING zone         → HIGH risk (stop)
        ii. Currently in LEFT/RIGHT zone       → MEDIUM risk (watch)
            ↳ if entering crossing zone next   → HIGH (handled by overlap_risk)

  Unknown / ambiguous motion                  → conservative MEDIUM risk

──────────────────────────────────────────────────────────────────────────────
Risk formula (per vehicle):
  Risk = 0.35 × ttc_risk
       + 0.20 × speed_risk
       + 0.45 × geometric_risk    ← dominant term

Risk → Proposed State:
  < 0.25  → SAFE
  0.25–0.50 → WALK_FAST
  0.50–0.70 → WAIT
  ≥ 0.70  → STOP
"""

from __future__ import annotations
from typing import List, Tuple, Optional, Dict

from crossing_advisor import VehicleInfo, CrossingConfig
from state_machine import (
    STATE_STOP, STATE_WAIT, STATE_SAFE, STATE_WALK_FAST
)

_EPS = 1e-6

# ── Risk weight vector (sums to 1.0) ─────────────────────────────────────────
_W_TTC      = 0.35   # Time-to-collision component
_W_SPEED    = 0.20   # Speed component
_W_GEOM     = 0.45   # Geometric (zone + direction) component — dominant

# ── Speed / TTC normalisation anchors ────────────────────────────────────────
_MAX_SPEED_KMH = 80.0    # speed ≥ this → speed_risk = 1.0
_TTC_SAFE_SEC  = 12.0    # TTC ≥ this   → ttc_risk  = 0.0

# ── Risk → state thresholds ───────────────────────────────────────────────────
_THRESH_STOP      = 0.70
_THRESH_WAIT      = 0.50
_THRESH_WALK_FAST = 0.25

# ── Geometric distance thresholds ─────────────────────────────────────────────
# For HORIZONTAL traffic: if the vehicle is closer than this → dangerous
_NEAR_M = 8.0    # within 8 m and passing across → HIGH geometric risk
_FAR_M  = 14.0   # beyond 14 m and passing across → LOW geometric risk


# ─────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ─────────────────────────────────────────────────────────────────────────────

def _crossing_overlap(bbox: tuple, zone: dict) -> float:
    """Fraction of vehicle bbox area overlapping the CROSSING zone (0–1)."""
    if not zone or not bbox:
        return 0.0
    x1, y1, x2, y2 = bbox
    zx1, zy1 = zone.get("x1", 0), zone.get("y1", 0)
    zx2, zy2 = zone.get("x2", 0), zone.get("y2", 0)
    ix1 = max(x1, zx1); iy1 = max(y1, zy1)
    ix2 = min(x2, zx2); iy2 = min(y2, zy2)
    inter     = max(0, ix2 - ix1) * max(0, iy2 - iy1)
    bbox_area = max(1, (x2 - x1) * (y2 - y1))
    return min(1.0, inter / bbox_area)


def _current_zone(bbox: tuple, all_zones: Optional[Dict]) -> str:
    """
    Return the name of the zone the vehicle's bbox centre sits in.
    Returns "CROSSING", "LEFT", "RIGHT", or "none".
    """
    if not all_zones or not bbox:
        return "none"
    cx = (bbox[0] + bbox[2]) / 2
    cy = (bbox[1] + bbox[3]) / 2
    for name, z in all_zones.items():
        if (z.get("x1", 0) <= cx <= z.get("x2", 0) and
                z.get("y1", 0) <= cy <= z.get("y2", 0)):
            return name
    return "none"


def _geometric_risk(vi: VehicleInfo,
                    crossing_zone: dict,
                    all_zones: Optional[Dict]) -> float:
    """
    Compute 0.0–1.0 geometric risk using the zone + direction matrix.

    HORIZONTAL + near crossing zone  → 0.88  (unsafe — will hit user)
    HORIZONTAL + far from crossing   → 0.05  (safe — passes through before user)
    VERTICAL   + retreating (away)   → 0.00  (safe — leaving the scene)
    VERTICAL   + toward + CROSSING   → 0.92  (stop — on collision course)
    VERTICAL   + toward + LEFT/RIGHT → 0.40  (watch — may enter crossing)
    VERTICAL   + toward + no zone    → 0.55  (uncertain — conservative)
    ambiguous / unknown motion       → 0.50  (conservative default)
    """
    axis = getattr(vi, "motion_axis", "unknown")
    zone = _current_zone(vi.bbox, all_zones)

    # ── Case 1: HORIZONTAL motion ─────────────────────────────────────────────
    if axis == "horizontal":
        dist    = vi.dist_m if vi.dist_m > 0 else _FAR_M
        overlap = _crossing_overlap(vi.bbox, crossing_zone)

        # Band 3 — FAR: safe pass-through regardless of crossing overlap
        if dist >= _FAR_M:
            return 0.05

        # Band 1 — NEAR: vehicle close to the user and moving across
        if dist <= _NEAR_M:
            closeness = max(0.0, min(1.0, 1.0 - (dist / _NEAR_M)))
            base = 0.45 + 0.43 * closeness  # [0.45 → 0.88]
            if overlap > 0.15:
                base = max(base, 0.60)       # floor when vehicle is in crossing zone
            return base

        # Band 2 — INTERMEDIATE (NEAR_M < dist < FAR_M)
        frac = (dist - _NEAR_M) / (_FAR_M - _NEAR_M)  # 0.0 → 1.0
        if overlap > 0.15:
            # Vehicle is in the crossing zone but at moderate distance — still a threat
            return 0.60 - 0.15 * frac       # [0.45 → 0.60]
        else:
            return 0.45 - 0.40 * frac       # [0.05 → 0.45]

    # ── Case 2: VERTICAL motion ───────────────────────────────────────────────
    if axis == "vertical":
        retreating = getattr(vi, "retreating", False)

        # 2a: Vehicle actively moving away → safe
        if retreating or (not vi.approaching and vi.dA <= 0):
            return 0.00

        # 2b: Vehicle moving toward user
        if vi.approaching:
            if zone == "CROSSING":
                return 0.92   # stop — on direct collision course
            elif zone in ("LEFT", "RIGHT"):
                return 0.50   # watch — in side zone, heading toward crossing
            else:
                return 0.55   # conservative unknown zone

        # Not clearly approaching or retreating — neutral
        return 0.25

    # ── Ambiguous / unknown ───────────────────────────────────────────────────
    # Fall back to a conservative score based on crossing overlap
    overlap = _crossing_overlap(vi.bbox, crossing_zone)
    return 0.30 + 0.35 * overlap


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

def rank_threats(
    vehicle_infos: List[VehicleInfo],
    crossing_zone: dict,
    k: int = 3,
) -> List[VehicleInfo]:
    """
    Return the top-K most dangerous vehicles, sorted descending.

    Vehicles that are retreating (actively moving away) receive threat = 0
    and are filtered out before ranking.
    Dogs (class 3) are excluded as non-traffic threats.
    """
    def _threat(vi: VehicleInfo) -> float:
        if vi.class_id == 3:                       # dog — skip
            return 0.0
        retreating = getattr(vi, "retreating", False)
        if retreating:                             # moving away — not a threat
            return 0.0
        if not vi.approaching and vi.dA <= 0:      # stationary / fading
            # Still score it if it overlaps crossing (parked in crossing = bad)
            overlap = _crossing_overlap(vi.bbox, crossing_zone)
            return 0.05 * overlap
        ttc_f   = 1.0 / (vi.ttc_sec + _EPS)
        speed_f = vi.speed_mps
        overlap = _crossing_overlap(vi.bbox, crossing_zone)
        return ttc_f * speed_f * (0.5 + overlap)

    ranked = sorted(vehicle_infos, key=_threat, reverse=True)
    return ranked[:k]


def compute_risk(
    top_k:             List[VehicleInfo],
    crossing_zone:     dict,
    all_zones:         Optional[Dict],
    frame_width:       int,
    config:            CrossingConfig,
    crossing_progress: float = 0.0,
) -> Tuple[float, float, str, str]:
    """
    Aggregate risk across the top-K threat vehicles using the geometric model.

    Returns:
        (risk_score, confidence, secondary_cue, proposed_state)
    """
    if not top_k:
        return 0.0, 1.0, "", STATE_SAFE

    # Personalised remaining crossing time
    progress       = max(0.0, min(1.0, crossing_progress))
    remaining_dist = config.road_width_m * (1.0 - progress)
    remaining_time = remaining_dist / max(0.1, config.walk_speed_mps)
    safe_ttc       = remaining_time + config.safety_margin_sec

    worst_risk = 0.0
    worst_vi   = top_k[0]

    for vi in top_k:
        # ── TTC risk — normalised to personalised safe_ttc ───────────────────
        if vi.ttc_sec == float("inf"):
            ttc_risk = 0.0
        elif vi.ttc_sec <= 0:
            ttc_risk = 1.0
        else:
            ttc_risk = max(0.0, min(1.0,
                (safe_ttc - vi.ttc_sec) / max(safe_ttc, _EPS)))

        # ── Speed risk ───────────────────────────────────────────────────────
        speed_risk = min(1.0, vi.speed_kmh / _MAX_SPEED_KMH)

        # ── Geometric risk (zone + direction — dominant term) ────────────────
        geom_risk = _geometric_risk(vi, crossing_zone, all_zones)

        # ── Combined per-vehicle risk ─────────────────────────────────────────
        v_risk = (
            _W_TTC   * ttc_risk
            + _W_SPEED * speed_risk
            + _W_GEOM  * geom_risk
        )

        if v_risk > worst_risk:
            worst_risk = v_risk
            worst_vi   = vi

    risk_score = min(1.0, worst_risk)

    # ── Confidence: degrades when direction / motion axis are unknown ─────────
    if risk_score == 0.0:
        confidence = 1.0
    else:
        dir_known  = all(v.direction   != "unknown" for v in top_k)
        axis_known = all(getattr(v, "motion_axis", "unknown") != "unknown" for v in top_k)
        ttc_known  = all(v.ttc_sec != float("inf") or getattr(v, "retreating", False) for v in top_k)

        if dir_known and axis_known and ttc_known:
            confidence = 0.90
        elif dir_known and axis_known:
            confidence = 0.70
        elif dir_known:
            confidence = 0.55
        else:
            confidence = 0.40

    # ── Secondary spoken cue from worst vehicle ───────────────────────────────
    secondary = ""
    axis = getattr(worst_vi, "motion_axis", "unknown")
    retreating = getattr(worst_vi, "retreating", False)

    if retreating:
        secondary = "Vehicle moving away."
    elif axis == "horizontal":
        if worst_vi.direction == "right_to_left":
            secondary = "Raise your left hand."
        elif worst_vi.direction == "left_to_right":
            secondary = "Raise your right hand."
    elif axis == "vertical":
        if worst_vi.approaching:
            side = "left" if worst_vi.cx < (frame_width / 2) else "right"
            secondary = f"Vehicle approaching from your {side}."
        else:
            secondary = "Vehicle moving away."

    # ── Map risk score to proposed state ─────────────────────────────────────
    if risk_score >= _THRESH_STOP:
        state = STATE_STOP
    elif risk_score >= _THRESH_WAIT:
        state = STATE_WAIT
    elif risk_score >= _THRESH_WALK_FAST:
        state = STATE_WALK_FAST
    else:
        state = STATE_SAFE

    return risk_score, confidence, secondary, state
