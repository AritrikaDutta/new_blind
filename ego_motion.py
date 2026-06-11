"""
ego_motion.py
=============
Ego-motion compensation using Farneback dense optical flow (Section 6.4).

When the user (camera) is walking, every object in the frame appears to
shift. Without compensation, a stationary parked car would look like it's
"approaching" because the camera is moving toward it.

Algorithm:
  1. Downscale the current and previous grayscale frames for speed.
  2. Compute Farneback dense optical flow between them.
  3. Sample flow vectors only from background border strips
     (top edge, left edge, right edge) — these should be static scene features.
  4. Take the robust median to eliminate moving vehicles from the estimate.
  5. Return (ego_dx, ego_dy) in original-resolution pixel coordinates.

Usage (each frame, before VelocityTracker.update):
    ego_dx, ego_dy = ego_estimator.update(frame)
    velocity_tracker.update(track_id, bbox, class_id, ego_dx=ego_dx, ego_dy=ego_dy)
"""

from __future__ import annotations
import cv2
import numpy as np


# Processing scale — lower = faster but less accurate
_FLOW_SCALE: float = 0.40

# Fraction of frame width/height used as border background mask
_BORDER_FRAC: float = 0.15

# Clamp ego-motion estimate to this max (pixels/frame).
# Beyond this it's likely a noisy outlier.
_MAX_EGO_PX: float = 80.0


class EgoMotionEstimator:
    """
    Estimates per-frame camera self-motion using dense optical flow on
    static background regions (top/left/right border strips).

    Section 6.4 — Ego-Motion Compensation
    """

    def __init__(
        self,
        scale: float = _FLOW_SCALE,
        border_frac: float = _BORDER_FRAC,
        enabled: bool = True,
    ):
        """
        Args:
            scale:        Downscale factor for optical flow computation.
            border_frac:  Fraction of frame used as background mask.
            enabled:      Set False to skip compensation (useful for static camera).
        """
        self.scale = scale
        self.border_frac = border_frac
        self.enabled = enabled

        self._prev_gray_small: np.ndarray | None = None
        self.ego_dx: float = 0.0
        self.ego_dy: float = 0.0

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def update(self, frame: np.ndarray) -> tuple[float, float]:
        """
        Process a new BGR frame and return (ego_dx, ego_dy) in original pixels.

        Call this once per frame, BEFORE updating the VelocityTracker,
        so the compensation values are fresh.

        Returns:
            (ego_dx, ego_dy): Camera translation this frame.
              Positive ego_dx means camera moved right (objects apparent-shift left).
        """
        if not self.enabled:
            self.ego_dx, self.ego_dy = 0.0, 0.0
            return 0.0, 0.0

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape
        sh = max(1, int(h * self.scale))
        sw = max(1, int(w * self.scale))
        gray_small = cv2.resize(gray, (sw, sh), interpolation=cv2.INTER_LINEAR)

        if self._prev_gray_small is None:
            self._prev_gray_small = gray_small
            self.ego_dx, self.ego_dy = 0.0, 0.0
            return 0.0, 0.0

        # Dense Farneback optical flow
        flow = cv2.calcOpticalFlowFarneback(
            self._prev_gray_small, gray_small, None,
            pyr_scale=0.5,
            levels=3,
            winsize=13,
            iterations=3,
            poly_n=5,
            poly_sigma=1.2,
            flags=0,
        )
        self._prev_gray_small = gray_small

        # Build a background mask: top strip + left strip + right strip.
        # We exclude the bottom half (road surface) and centre (vehicles).
        mask = np.zeros((sh, sw), dtype=bool)
        bx = max(1, int(sw * self.border_frac))
        by = max(1, int(sh * self.border_frac))
        mask[:by, :]   = True    # top strip  — sky / buildings
        mask[:, :bx]   = True    # left strip  — road edge
        mask[:, -bx:]  = True    # right strip — road edge

        bg_flow = flow[mask]     # shape (N, 2), each row is (dx, dy)

        if len(bg_flow) == 0:
            self.ego_dx, self.ego_dy = 0.0, 0.0
            return 0.0, 0.0

        # Median is robust against vehicles that stray into the border strip
        raw_dx = float(np.median(bg_flow[:, 0])) / self.scale
        raw_dy = float(np.median(bg_flow[:, 1])) / self.scale

        # Clamp to prevent extreme outliers from corrupting tracking
        self.ego_dx = float(np.clip(raw_dx, -_MAX_EGO_PX, _MAX_EGO_PX))
        self.ego_dy = float(np.clip(raw_dy, -_MAX_EGO_PX, _MAX_EGO_PX))

        return self.ego_dx, self.ego_dy

    def compensate_cx(self, cx_raw: float) -> float:
        """
        Return the ego-stabilised x-centre of an object.

        If the camera moved right by ego_dx pixels, a stationary object
        appears to have moved LEFT by ego_dx.  To "undo" this apparent
        motion we ADD ego_dx back:
            cx_stabilised = cx_raw + ego_dx
        """
        return cx_raw + self.ego_dx

    def compensate_cy(self, cy_raw: float) -> float:
        """Return the ego-stabilised y-centre of an object."""
        return cy_raw + self.ego_dy

    def reset(self) -> None:
        """Call when switching to a new video or camera stream."""
        self._prev_gray_small = None
        self.ego_dx = 0.0
        self.ego_dy = 0.0
