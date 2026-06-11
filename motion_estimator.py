"""
motion_estimator.py
===================
Physics-based distance and approach-speed estimator (Section 6 of spec).

Uses the pinhole camera model:
    distance_m = (real_width_m * focal_px) / pixel_width_px

Then tracks distance across frames (with linear regression) to compute:
    approach_speed_mps  — how fast the vehicle is closing (m/s)
    speed_kmh           — same, in km/h
    ttc_sec             — time-to-collision = distance_m / approach_speed_mps

If AI depth is available, a scale factor refines the physics estimate.

Calibration note (one-time setup):
    Place a car (real width ~1.8 m) at a known distance D (m).
    Measure its pixel width W in the frame.
    Then: FOCAL_PX = W * D / 1.8
"""

from __future__ import annotations
from collections import defaultdict
from typing import Optional

# ---------------------------------------------------------------------------
# Real-world vehicle widths (metres). Class IDs match the custom YOLO model:
#   0=bicycle  1=bus  2=car  3=dog  4=motorcycle  5=person  6=scooty  7=toto
# ---------------------------------------------------------------------------
REAL_WIDTHS_M: dict[int, float] = {
    0: 0.60,   # bicycle
    1: 2.50,   # bus
    2: 1.80,   # car
    3: 0.40,   # dog
    4: 0.80,   # motorcycle
    5: 0.50,   # person
    6: 0.80,   # scooty
    7: 1.40,   # toto
}

# ---------------------------------------------------------------------------
# Camera constant.
# Phone camera at ~1080p has FOCAL_PX ≈ 800–1200.
# 900 is a safe default for a mid-range smartphone rear camera.
# Adjust via calibration if needed.
# ---------------------------------------------------------------------------
FOCAL_PX: float = 900.0

# Minimum history frames before computing approach speed
_MIN_HIST: int = 4

# Minimum closing speed to classify as "approaching" (m/s ~ 1 km/h)
_MIN_APPROACH_MPS: float = 0.28


class MotionEstimator:
    """
    Maintains per-track metric distance history and computes physics-based
    distance, approach speed (m/s & km/h), and time-to-collision.

    Section 6.1 — Distance Estimation
    Section 6.3 — Time-to-Collision
    """

    def __init__(self, focal_px: float = FOCAL_PX, max_history: int = 25):
        self.focal_px = focal_px
        self.max_history = max_history
        # track_id → list of (distance_m, timestamp_sec)
        self._hist: dict[int, list] = defaultdict(list)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def estimate_distance(
        self,
        pixel_width: float,
        class_id: int,
        ai_depth_scale: float = 1.0,
    ) -> float:
        """
        Estimate metric distance to one vehicle from its bounding-box width.

        Args:
            pixel_width:      Width of the bbox in pixels.
            class_id:         YOLO class id (0–7).
            ai_depth_scale:   Refinement factor from MiDaS (1.0 = no AI).

        Returns:
            Estimated distance in metres.
        """
        real_w = REAL_WIDTHS_M.get(class_id, 1.80)
        if pixel_width < 1.0:
            return 999.0
        dist = (real_w * self.focal_px) / pixel_width * ai_depth_scale
        return round(dist, 2)

    def update(
        self,
        track_id: int,
        bbox: tuple,
        class_id: int,
        timestamp_sec: float,
        ai_depth_scale: float = 1.0,
    ) -> None:
        """
        Record a new observation for the given track.

        Args:
            track_id:        Unique tracker ID.
            bbox:            (x1, y1, x2, y2) bounding box in pixels.
            class_id:        YOLO class id.
            timestamp_sec:   Wall-clock in seconds (frame_index / fps).
            ai_depth_scale:  Scale factor from MiDaS (default 1.0).
        """
        pixel_w = bbox[2] - bbox[0]
        dist_m = self.estimate_distance(pixel_w, class_id, ai_depth_scale)
        self._hist[track_id].append((dist_m, timestamp_sec))
        if len(self._hist[track_id]) > self.max_history:
            self._hist[track_id].pop(0)

    def get_estimate(self, track_id: int) -> dict:
        """
        Return the current physics estimate for a tracked vehicle.

        Returns a dict with keys:
            dist_m       — current estimated distance (m)
            speed_mps    — approach speed in m/s  (0 if moving away)
            speed_kmh    — approach speed in km/h  (0 if moving away)
            ttc_sec      — time-to-collision in seconds (inf if moving away)
            approaching  — True if vehicle is closing on the user
        """
        hist = self._hist.get(track_id, [])
        if len(hist) < 2:
            return self._null(hist)

        current_dist = hist[-1][0]

        if len(hist) < _MIN_HIST:
            # Too few samples → simple two-point estimate
            dt = hist[-1][1] - hist[0][1]
            dd = hist[0][0] - hist[-1][0]          # positive = closing
            if dt < 1e-6:
                return self._null(hist)
            approach_mps = dd / dt

        else:
            # Linear regression over full history
            # Fits dist = slope * t + intercept
            # Negative slope ⟹ distance decreasing ⟹ approaching
            n = len(hist)
            ts = [h[1] for h in hist]
            ds = [h[0] for h in hist]
            t_mean = sum(ts) / n
            d_mean = sum(ds) / n
            num = sum((ts[i] - t_mean) * (ds[i] - d_mean) for i in range(n))
            den = sum((ts[i] - t_mean) ** 2 for i in range(n))
            slope = num / den if abs(den) > 1e-9 else 0.0
            # slope = d(dist)/dt;  negative slope = approaching
            approach_mps = -slope             # positive means closing

        if approach_mps > _MIN_APPROACH_MPS:
            approaching = True
            ttc_sec = current_dist / approach_mps
            ttc_sec = min(ttc_sec, 999.0)
        else:
            approaching = False
            ttc_sec = float('inf')

        return {
            "dist_m":      current_dist,
            "speed_mps":   round(max(approach_mps, 0.0), 2),
            "speed_kmh":   round(max(approach_mps * 3.6, 0.0), 1),
            "ttc_sec":     round(ttc_sec, 2) if approaching else float('inf'),
            "approaching": approaching,
        }

    def remove_track(self, track_id: int) -> None:
        """Release history for a lost track."""
        self._hist.pop(track_id, None)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _null(hist: list) -> dict:
        dist = hist[-1][0] if hist else 999.0
        return {
            "dist_m":      dist,
            "speed_mps":   0.0,
            "speed_kmh":   0.0,
            "ttc_sec":     float('inf'),
            "approaching": False,
        }
