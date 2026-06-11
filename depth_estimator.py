"""
depth_estimator.py
==================
Optional AI-based monocular depth enhancement using Intel MiDaS (Section 7.1).

MiDaS outputs *inverse* depth (higher value = closer to camera).
We use it to produce a refinement scale factor that nudges the physics
distance estimate toward what the neural network "sees."

Fusion strategy (Section 8 — Hybrid Fusion):
  - Physics estimate is always the primary, safety-critical value.
  - AI scale is clamped to [0.5, 2.0] so it can only halve or double
    the physics result, never override it completely.
  - Falls back silently to scale=1.0 if model unavailable or frame fails.

GPU usage:
  - Automatically uses CUDA if available (recommended for Jetson / GPU PC).
  - ~8–15 ms per frame on a mid-range GPU with MiDaS_small.
  - Falls back to CPU (~80–120 ms) if no CUDA.

First run:
  - Downloads model weights (~100 MB) via torch.hub.
  - Subsequent runs load from local cache instantly.
"""

from __future__ import annotations
from typing import Optional
import numpy as np


class DepthEstimator:
    """
    Wraps Intel MiDaS for monocular AI depth estimation.

    Provides a per-bounding-box scale factor to refine physics distance.

    Section 7.1 — AI Depth Estimation
    Section 8   — Hybrid Fusion Strategy
    """

    def __init__(self, enabled: bool = True, model_type: str = "MiDaS_small"):
        """
        Args:
            enabled:     Set False to skip AI depth entirely.
            model_type:  "MiDaS_small" (fast, ~6M params) or
                         "DPT_Hybrid" (accurate, ~123M params, needs more VRAM).
        """
        self.enabled = enabled
        self.model_type = model_type
        self.model = None
        self.transform = None
        self.device = None
        self._ready = False

        if self.enabled:
            self._load_model()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def get_depth_map(self, frame: np.ndarray) -> Optional[np.ndarray]:
        """
        Run MiDaS on a BGR frame.

        Returns:
            Float32 array (H × W) with inverse-depth values, or None
            if the model is not ready.  Higher values = closer to camera.
        """
        if not self._ready:
            return None

        import torch
        import cv2

        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        input_batch = self.transform(rgb).to(self.device)

        with torch.no_grad():
            pred = self.model(input_batch)
            pred = torch.nn.functional.interpolate(
                pred.unsqueeze(1),
                size=frame.shape[:2],
                mode="bicubic",
                align_corners=False,
            ).squeeze()

        return pred.cpu().numpy().astype(np.float32)

    def get_bbox_scale(
        self,
        depth_map: Optional[np.ndarray],
        bbox: tuple,
        physics_dist_m: float,
    ) -> float:
        """
        Compute a multiplicative scale factor for the physics distance estimate.

        Strategy:
          1. Sample the median inverse-depth inside the bounding box (roi_inv_d).
          2. Compare to the full-frame median (frame_inv_d).
          3. A vehicle closer than average has higher roi_inv_d  → smaller relative
             distance → scale < 1 (pull physics estimate closer).
          4. Clamp to [0.5, 2.0] so physics always dominates.

        Args:
            depth_map:       Output of get_depth_map() for this frame.
            bbox:            (x1, y1, x2, y2).
            physics_dist_m:  Physics distance (unused here but kept for future fusion).

        Returns:
            Scale factor ≈ 1.0. Multiply physics distance by this.
        """
        if depth_map is None or physics_dist_m <= 0:
            return 1.0

        x1, y1, x2, y2 = (int(v) for v in bbox)
        h, w = depth_map.shape[:2]
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)

        if x2 <= x1 or y2 <= y1:
            return 1.0

        roi_inv_d   = float(np.median(depth_map[y1:y2, x1:x2]))
        frame_inv_d = float(np.median(depth_map))

        if roi_inv_d < 1e-3 or frame_inv_d < 1e-3:
            return 1.0

        # If the vehicle is twice as "inverse-deep" as the average scene element,
        # it is roughly twice as close → scale the physics distance by 0.5.
        relative_closeness = roi_inv_d / frame_inv_d   # > 1 = closer than average
        scale = 1.0 / relative_closeness               # scale < 1 = pull closer

        # Clamp to keep physics estimate dominant
        return float(np.clip(scale, 0.5, 2.0))

    @property
    def ready(self) -> bool:
        """True if the model loaded successfully."""
        return self._ready

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    def _load_model(self) -> None:
        """Download and initialise MiDaS from torch.hub."""
        try:
            import torch
            self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
            print(f"[DepthEstimator] Loading {self.model_type} on {self.device} …")

            self.model = torch.hub.load(
                "intel-isl/MiDaS", self.model_type, trust_repo=True
            )
            self.model.to(self.device)
            self.model.eval()

            midas_transforms = torch.hub.load(
                "intel-isl/MiDaS", "transforms", trust_repo=True
            )
            if self.model_type == "MiDaS_small":
                self.transform = midas_transforms.small_transform
            else:
                self.transform = midas_transforms.dpt_transform

            self._ready = True
            print(f"[DepthEstimator] Ready ✓  (device={self.device})")

        except Exception as exc:
            print(f"[DepthEstimator] Could not load model — {exc}")
            print("[DepthEstimator] Continuing without AI depth (physics-only mode).")
            self.enabled = False
            self._ready  = False
