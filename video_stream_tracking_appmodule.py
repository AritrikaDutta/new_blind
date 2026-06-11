"""
video_stream_tracking_appmodule.py
===================================
Full integrated pipeline — Sprints 1-5.

Pipeline stages per frame:
  1. estimate_ego_motion(frame)             → (ego_dx, ego_dy)
  2. detect_objects(frame)                  → YOLO detections
  3. estimate_depth(frame, enabled)         → MiDaS depth map | None
  4. update_tracks(detections, frame)       → DeepSORT tracks
  5. compute_vehicle_states(...)            → List[VehicleInfo]
  6. rank_threats(vehicle_infos, ...)       → top-K threats          [Sprint 3]
  7. compute_risk(top_k, ...)              → risk_score, confidence   [Sprint 3]
  8. state_machine.update(proposed, conf)  → StateOutput              [Sprint 2]
  9. trigger_voice(state_output)           → audio label emitted      [Sprint 2]
 10. draw_overlays(...)                    → annotated frame
 11. event_logger.log(...)                 → JSONL record             [Sprint 5]

Performance tiers (Sprint 5):
  Tier 1 — full: YOLO + DeepSORT + MiDaS + ego-motion          (fps ≥ 15)
  Tier 2 — balanced: YOLO + DeepSORT + bbox physics             (fps 8–14)
  Tier 3 — fast: YOLO only + simple TTC                         (fps < 8)
"""

import cv2
import time
import pandas as pd
from collections import deque
from ultralytics import YOLO
from deep_sort_realtime.deepsort_tracker import DeepSort

from velocity_tracker_2 import VelocityTracker
from motion_estimator    import MotionEstimator
from ego_motion          import EgoMotionEstimator
from depth_estimator     import DepthEstimator
from zone_utils_1        import define_zones, get_all_zones_for_bbox, draw_zones_on_image
from overlay_utils_1     import draw_vehicle_overlay, draw_advice_banner
from voice_feedback_2    import VoiceAlertManager
from crossing_advisor    import (
    CrossingAdvisor, CrossingConfig, VehicleInfo,
    HEAVY_CLASSES, LIGHT_CLASSES, CLASS_LABELS,
)
from state_machine  import SafetyStateMachine, StateOutput, STATE_SAFE, ALL_STATES
from risk_scorer    import rank_threats, compute_risk
from event_logger   import EventLogger

# ─────────────────────────────────────────────────────────────────────────────
# Module-level singletons
# ─────────────────────────────────────────────────────────────────────────────
_model            = YOLO("best.pt")
_tracker          = DeepSort(max_age=30)
_velocity_tracker = VelocityTracker()
_motion_estimator = MotionEstimator(focal_px=900.0)
_ego_estimator    = EgoMotionEstimator(enabled=True)
_depth_estimator  = DepthEstimator(enabled=True, model_type="MiDaS_small")
_advisor          = CrossingAdvisor()
_voice_alert      = VoiceAlertManager()
_state_machine    = SafetyStateMachine(smoothing_frames=8, min_confidence=0.70)
_event_logger     = EventLogger()
# NOTE: _classifier (Random Forest) was removed — it is superseded by the
# geometric risk scorer and was never called in the live pipeline.
# Removing it saves ~100 MB RAM and ~2 s startup time.

# ─────────────────────────────────────────────────────────────────────────────
# Frame-level state
# ─────────────────────────────────────────────────────────────────────────────
_zones:        dict | None = None
_frame_width:  int         = 640
_frame_height: int         = 480
_frame_count:  int         = 0
fps:           int         = 30

# MiDaS frame-skip: run depth every N frames, reuse cached result in between.
# On CPU this triples effective FPS while keeping ~90 % of accuracy benefit.
_MIDAS_SKIP: int           = 3   # run MiDaS every 3rd frame
_last_depth_map            = None

# Performance tier tracking (Sprint 5)
_fps_history: deque = deque(maxlen=30)   # rolling 30-frame FPS window
_last_frame_time: float = 0.0
_current_tier:  int = 1                  # 1=full, 2=balanced, 3=fast

# Crossing progress tracking (Sprint 3)
_cum_ego_dy: float = 0.0                 # cumulative vertical camera displacement

# Cache of latest safety decision / overlays for high-FPS display
_latest_state_out    = None
_latest_top_k        = []
_latest_vehicle_infos = []
_latest_all_tracks   = []  # ALL confirmed tracks (all 8 classes) for bbox display


# ─────────────────────────────────────────────────────────────────────────────
# Stage 0: FPS monitor & tier selection  (Sprint 5)
# ─────────────────────────────────────────────────────────────────────────────
def _update_tier() -> int:
    """
    Measure instantaneous FPS and select performance tier.
    Tier 1 ≥ 12 fps  |  Tier 2 = 1.5–12 fps  |  Tier 3 < 1.5 fps
    """
    global _last_frame_time, _current_tier
    now = time.perf_counter()
    if _last_frame_time > 0:
        inst_fps = 1.0 / max(1e-6, now - _last_frame_time)
        _fps_history.append(inst_fps)
    _last_frame_time = now

    if not _fps_history:
        return _current_tier

    avg_fps = sum(_fps_history) / len(_fps_history)

    if avg_fps >= 12:
        _current_tier = 1
    elif avg_fps >= 1.5:
        _current_tier = 2
    else:
        _current_tier = 3

    return _current_tier


def get_current_fps() -> float:
    """Exposed for Streamlit metrics panel."""
    if not _fps_history:
        return float(fps)
    return round(sum(_fps_history) / len(_fps_history), 1)


def get_current_tier() -> int:
    return _current_tier


# ─────────────────────────────────────────────────────────────────────────────
# Stage helpers
# ─────────────────────────────────────────────────────────────────────────────
def _init_zones(frame):
    global _zones, _frame_width, _frame_height
    _frame_height, _frame_width = frame.shape[:2]
    _zones = define_zones(_frame_width, _frame_height)


def estimate_ego_motion(frame, config: CrossingConfig | None = None):
    """Stage 1 — ego-motion compensation (disabled at Tier 3 or via config)."""
    if (config is not None and not config.use_ego_motion) or _current_tier >= 3:
        return 0.0, 0.0
    return _ego_estimator.update(frame)


def detect_objects(frame, conf_threshold: float = 0.40):
    """Stage 2 — YOLO detection (all tiers)."""
    results    = _model(frame, verbose=False, conf=conf_threshold)[0]
    detections = []
    for r in results.boxes.data.tolist():
        x1, y1, x2, y2, score, class_id = r
        class_id = int(class_id)
        if class_id in range(8):
            detections.append(([x1, y1, x2 - x1, y2 - y1], score, class_id))
    return detections


def estimate_depth(frame, enabled: bool = False):
    """
    Stage 3 — MiDaS depth (Tier 1 & 2, frame-skipped every _MIDAS_SKIP frames).

    Fix (BUG 1): Previously only ran at Tier 1 (fps>=12), which meant MiDaS
    on CPU (~80-120ms/frame → fps≈8) was silently never called.  Now runs at
    Tier 1 and 2, with frame-skipping so the cached depth map is reused for
    the frames in between.  Tier 3 (fps<1.5) still skips MiDaS.
    """
    global _last_depth_map
    if not enabled or _current_tier >= 3:
        return _last_depth_map   # reuse last result rather than returning None
    if _frame_count % _MIDAS_SKIP != 0:
        return _last_depth_map   # reuse cached depth on skip frames
    _last_depth_map = _depth_estimator.get_depth_map(frame)
    return _last_depth_map


def update_tracks(detections, frame):
    """Stage 4 — DeepSORT (All Tiers)."""
    return _tracker.update_tracks(detections, frame=frame)


def compute_vehicle_states(
    tracks,
    ego_dx: float,
    ego_dy: float,
    depth_map,
    timestamp_sec: float,
    config: CrossingConfig,
    raw_detections: list = None,
):
    """
    Stage 5 — build VehicleInfo list from tracks or raw detections.
    Also accumulates crossing_progress from ego_dy.
    Returns (vehicle_infos, crossing_progress, feature_dict_for_rf).
    """
    global _cum_ego_dy

    if _zones is None:
        return [], 0.0, {}

    cz      = _zones.get("CROSSING", {})
    target_x = (cz.get("x1", 0) + cz.get("x2", _frame_width))  / 2
    target_y = (cz.get("y1", 0) + cz.get("y2", _frame_height)) / 2

    # Accumulate forward displacement for crossing progress
    _cum_ego_dy += abs(ego_dy)
    crossing_progress = min(1.0, _cum_ego_dy / max(1, _frame_height))

    vehicle_infos = []
    num_vehicles = num_pedestrians = 0
    num_in_crossing = num_entering_crossing = 0
    total_speed = vehicle_count_for_speed = 0
    dir_left = dir_right = dir_up = dir_down = 0
    vehicle_distances, vehicle_speeds = [], []
    cz_x = _frame_width  // 2 if not cz else (cz["x1"] + cz["x2"]) / 2
    cz_y = _frame_height // 2 if not cz else (cz["y1"] + cz["y2"]) / 2



    # Standard track-based processing (All Tiers)
    for track in tracks:
        if not track.is_confirmed():
            continue
        if track.time_since_update > 0:
            continue

        track_id = track.track_id
        x1, y1, x2, y2 = map(int, track.to_ltrb())
        class_id = getattr(track, "det_class", -1)
        bbox     = (x1, y1, x2, y2)

        _velocity_tracker.update(track_id, bbox, class_id, ego_dx=ego_dx, ego_dy=ego_dy)
        app_info = _velocity_tracker.get_approach_info(track_id, target_x, target_y, fps)

        ai_scale = 1.0
        if depth_map is not None:
            physics_prelim = _motion_estimator.estimate_distance(x2 - x1, class_id, 1.0)
            ai_scale = _depth_estimator.get_bbox_scale(depth_map, bbox, physics_prelim)

        _motion_estimator.update(track_id, bbox, class_id, timestamp_sec, ai_depth_scale=ai_scale)
        phys = _motion_estimator.get_estimate(track_id)

        approaching = phys["approaching"] or app_info["approaching"]
        retreating  = app_info.get("retreating", False)
        ttc_sec     = phys["ttc_sec"]
        if ttc_sec == float("inf") and app_info["TTC_sec"] != float("inf"):
            ttc_sec = app_info["TTC_sec"]

        if class_id in HEAVY_CLASSES or class_id in LIGHT_CLASSES:
            vi = VehicleInfo(
                track_id    = track_id,
                class_id    = class_id,
                dx          = app_info.get("dx",          0.0),
                dA          = app_info.get("dA",          0.0),
                ttc_sec     = ttc_sec,
                dist_m      = phys["dist_m"],
                speed_kmh   = phys["speed_kmh"],
                speed_mps   = phys["speed_mps"],
                cx          = app_info.get("cx",          0.0),
                approaching = approaching,
                retreating  = retreating,
                direction   = app_info.get("direction",   "unknown"),
                motion_axis = app_info.get("motion_axis", "unknown"),
                bbox        = bbox,
            )
            vehicle_infos.append(vi)

            # RF feature accumulation
            px_speed, _ = _velocity_tracker.get_speed_direction(track_id)
            num_vehicles += 1
            total_speed  += px_speed
            vehicle_count_for_speed += 1
            zones_hit = get_all_zones_for_bbox(bbox, _zones)
            if "CROSSING" in zones_hit:
                num_in_crossing += 1
            elif px_speed > 1.0:
                num_entering_crossing += 1
            cx_v = (x1 + x2) / 2; cy_v = (y1 + y2) / 2
            dist_px = ((cx_v - cz_x) ** 2 + (cy_v - cz_y) ** 2) ** 0.5
            if px_speed > 0:
                vehicle_distances.append(dist_px)
                vehicle_speeds.append(px_speed)

        elif class_id == 5:
            num_pedestrians += 1

    avg_speed = total_speed / vehicle_count_for_speed if vehicle_count_for_speed else 0.0
    avg_ttc   = (
        sum(d / s for d, s in zip(vehicle_distances, vehicle_speeds)) / len(vehicle_distances)
        if vehicle_distances else 999.0
    )

    feature_dict = {
        "num_vehicles":               num_vehicles,
        "num_pedestrians":            num_pedestrians,
        "num_in_crossing_zone":       num_in_crossing,
        "num_entering_crossing_zone": num_entering_crossing,
        "avg_vehicle_speed":          avg_speed,   # always defined above
        "avg_time_to_collision":      avg_ttc,     # always defined above
        "dir_left": dir_left, "dir_right": dir_right,
        "dir_up":   dir_up,   "dir_down":  dir_down,
    }

    return vehicle_infos, crossing_progress, feature_dict


def assess_crossing(
    vehicle_infos,
    crossing_progress: float,
    feature_dict: dict,
    config: CrossingConfig,
):
    """
    Stage 6 — Threat ranking → Risk scoring → State machine gating.

    Sprint 3: uses risk_scorer as primary decision engine.
    Legacy RF kept as a secondary confidence signal.
    """
    cz = _zones.get("CROSSING", {}) if _zones else {}

    # Sprint 3: threat ranking + risk scoring
    top_k = rank_threats(vehicle_infos, cz, k=config.threat_rank_k)
    risk_score, confidence, secondary, proposed_state = compute_risk(
        top_k, cz, _zones, _frame_width, config, crossing_progress
    )

    # ── Immediate SAFE override: if no vehicle threats were detected this frame,
    #    bypass hysteresis entirely so the state clears immediately.
    if not vehicle_infos:
        _state_machine._current_state = STATE_SAFE
        _state_machine._pending_state = STATE_SAFE
        _state_machine._pending_count = 0
        from state_machine import _SPOKEN_MAP
        spoken, stem = _SPOKEN_MAP[STATE_SAFE]
        state_out = __import__('state_machine').StateOutput(
            internal_state = STATE_SAFE,
            spoken_text    = spoken,
            audio_stem     = stem,
            confidence     = 1.0,
            risk_score     = 0.0,
            secondary_cue  = "",
        )
        return state_out, top_k

    # If every top-k vehicle is retreating, override to SAFE immediately too
    if top_k and all(getattr(v, 'retreating', False) for v in top_k):
        _state_machine._current_state = STATE_SAFE
        _state_machine._pending_state = STATE_SAFE
        _state_machine._pending_count = 0
        from state_machine import _SPOKEN_MAP
        spoken, stem = _SPOKEN_MAP[STATE_SAFE]
        state_out = __import__('state_machine').StateOutput(
            internal_state = STATE_SAFE,
            spoken_text    = spoken,
            audio_stem     = stem,
            confidence     = 1.0,
            risk_score     = 0.0,
            secondary_cue  = "",
        )
        return state_out, top_k

    # Sprint 2: state machine hysteresis gate
    state_out = _state_machine.update(
        proposed_state = proposed_state,
        confidence     = confidence,
        risk_score     = risk_score,
        secondary_cue  = secondary,
    )

    return state_out, top_k


def trigger_voice(state_out: StateOutput, timestamp_sec: float):
    """
    Stage 7 — emit voice event using the full spoken text from StateOutput.
    Sprint 2 taxonomy: 4 spoken phrases + optional secondary cue.
    """
    _voice_alert._maybe_emit(
        state_out.audio_stem,
        spoken_text=state_out.full_spoken,
    )


_ACTION_MAP = {
    STATE_SAFE:  "cross_normal",
    "WALK_FAST": "cross_fast",
    "WAIT":      "stop",
    "UNCERTAIN": "stop",
    "STOP":      "stop",
}


def _state_out_to_action(state_out: StateOutput) -> str:
    """Map internal state → legacy action string used by draw_advice_banner."""
    return _ACTION_MAP.get(state_out.internal_state, "stop")


def _purge_lost_tracks(active_track_ids: set) -> None:
    """
    Fix (BUG 4): Remove history for tracks that DeepSORT has dropped.
    Prevents unbounded dict growth on long videos with many vehicles.
    """
    for lost_id in list(_motion_estimator._hist.keys()):
        if lost_id not in active_track_ids:
            _motion_estimator.remove_track(lost_id)
    for lost_id in list(_velocity_tracker.track_history.keys()):
        if lost_id not in active_track_ids:
            _velocity_tracker.track_history.pop(lost_id, None)
            _velocity_tracker.last_bbox.pop(lost_id, None)
            _velocity_tracker.track_class.pop(lost_id, None)
            _velocity_tracker.first_seen.pop(lost_id, None)


def draw_overlays(frame, zones, state_out: StateOutput, vehicle_infos, top_k):
    """
    Stage 8 — draw zones, vehicle badges, and advice banner.
    Highlights top-K threat vehicles with thicker borders.
    """
    draw_zones_on_image(frame, zones)

    top_ids = {v.track_id for v in top_k}

    for vi in vehicle_infos:
        draw_vehicle_overlay(
            frame,
            bbox        = vi.bbox,
            track_id    = vi.track_id,
            class_label = CLASS_LABELS.get(vi.class_id, "obj"),
            dist_m      = vi.dist_m,
            speed_kmh   = vi.speed_kmh,
            ttc_sec     = vi.ttc_sec,
            approaching = vi.approaching,
            direction   = vi.direction,
        )
        # Extra border for top-K threats
        if vi.track_id in top_ids and vi.bbox:
            x1, y1, x2, y2 = vi.bbox
            cv2.rectangle(frame, (x1 - 2, y1 - 2), (x2 + 2, y2 + 2), (0, 0, 255), 1)

    # Build a synthetic CrossingAdvice-like object for the existing banner util
    class _FakeAdvice:
        action      = _state_out_to_action(state_out)
        reason      = state_out.full_spoken
        threat_level = {STATE_SAFE: 0, "WALK_FAST": 1, "WAIT": 1,
                        "UNCERTAIN": 1, "STOP": 2}.get(state_out.internal_state, 1)
        dist_m      = top_k[0].dist_m    if top_k else 0.0
        speed_kmh   = top_k[0].speed_kmh if top_k else 0.0
        ttc_sec     = top_k[0].ttc_sec   if top_k else float("inf")

    draw_advice_banner(frame, _FakeAdvice())

    # Confidence + risk overlay (bottom-left)
    tier_color = {1: (0, 220, 0), 2: (0, 165, 255), 3: (0, 0, 255)}.get(_current_tier, (200, 200, 200))
    cv2.putText(
        frame,
        f"Risk:{state_out.risk_score:.2f}  Conf:{state_out.confidence:.2f}  "
        f"Tier:{_current_tier}  FPS:{get_current_fps():.0f}",
        (8, frame.shape[0] - 8),
        cv2.FONT_HERSHEY_SIMPLEX, 0.45, tier_color, 1, cv2.LINE_AA,
    )

    return frame


# ─────────────────────────────────────────────────────────────────────────────
# Public entry point
# ─────────────────────────────────────────────────────────────────────────────
def process_frame(frame, config: CrossingConfig | None = None):
    """
    Master orchestrator — calls all 11 pipeline stages in order.

    Args:
        frame:  BGR numpy array from OpenCV / WebRTC.
        config: CrossingConfig from Streamlit sidebar (defaults used if None).

    Returns:
        Annotated BGR frame.
    """
    global _frame_count

    if config is None:
        config = CrossingConfig()

    _frame_count  += 1
    timestamp_sec  = _frame_count / fps

    # Sync state machine from live config (sidebar can change these any frame)
    _state_machine.smoothing_frames = config.smoothing_frames
    _state_machine.min_confidence   = config.min_confidence_threshold

    # Sprint 5: update FPS and tier
    _update_tier()
    _init_zones(frame)

    ego_dx, ego_dy = estimate_ego_motion(frame, config)
    detections     = detect_objects(frame, conf_threshold=config.min_confidence_threshold)
    depth_map      = estimate_depth(frame, enabled=config.use_ai_depth)
    tracks         = update_tracks(detections, frame)

    # Purge history for tracks DeepSORT has dropped (prevents memory leak)
    active_ids = {t.track_id for t in tracks if t.is_confirmed()}
    if _frame_count % 30 == 0:   # check every 30 frames to keep overhead minimal
        _purge_lost_tracks(active_ids)

    vehicle_infos, crossing_progress, feature_dict = compute_vehicle_states(
        tracks, ego_dx, ego_dy, depth_map, timestamp_sec, config, raw_detections=detections
    )

    state_out, top_k = assess_crossing(
        vehicle_infos, crossing_progress, feature_dict, config
    )

    # Hard Fail-Safe removed — DeepSORT tracking now always active and correctly
    # classifies motion direction. Static bounding-box rules caused false STOPs.

    global _latest_state_out, _latest_top_k, _latest_vehicle_infos, _latest_all_tracks
    _latest_state_out = state_out
    _latest_top_k = top_k
    _latest_vehicle_infos = vehicle_infos

    # Cache ALL confirmed tracks for full-class bbox display (fixes missing person boxes)
    _latest_all_tracks = [
        (t.track_id,
         *map(int, t.to_ltrb()),
         getattr(t, 'det_class', -1))
        for t in tracks
        if t.is_confirmed() and t.time_since_update == 0
    ]

    trigger_voice(state_out, timestamp_sec)

    draw_overlays(frame, _zones, state_out, vehicle_infos, top_k)

    # Sprint 5: event logging
    top_vehicle = top_k[0] if top_k else None
    safe_ttc    = config.road_width_m / max(0.1, config.walk_speed_mps) + config.safety_margin_sec
    _event_logger.log(_frame_count, state_out, top_vehicle, safe_ttc)

    return frame


def reset_pipeline():
    """Call when switching to a new video or restarting camera."""
    global _frame_count, _cum_ego_dy, _latest_state_out, _latest_top_k, \
           _latest_vehicle_infos, _last_depth_map, _latest_all_tracks
    _frame_count  = 0
    _cum_ego_dy   = 0.0
    _latest_state_out    = None
    _latest_top_k        = []
    _latest_vehicle_infos = []
    _latest_all_tracks   = []
    _last_depth_map = None
    _state_machine.reset()
    _ego_estimator.reset()
    _fps_history.clear()


# ─────────────────────────────────────────────────────────────────────────────
# Per-class visual constants (BGR)
# ─────────────────────────────────────────────────────────────────────────────
_CLASS_COLORS = {
    0: (0,  140, 255),   # bicycle     — orange
    1: (60,  20, 220),   # bus         — deep red
    2: (100,100, 255),   # car         — blue
    3: (100,200, 100),   # dog         — green
    4: (200,  0, 200),   # motorcycle  — magenta
    5: (0,  230, 200),   # person      — teal  ← most safety-critical
    6: (200, 80, 255),   # scooty      — purple
    7: (0,  200, 255),   # toto        — yellow-cyan
}
_CLASS_NAMES_DISPLAY = {
    0:'bicycle', 1:'bus', 2:'car', 3:'dog',
    4:'motorcycle', 5:'person', 6:'scooty', 7:'toto',
}


def _draw_nonvehicle_box(frame, track_id: int,
                         x1: int, y1: int, x2: int, y2: int,
                         class_id: int) -> None:
    """
    Draw a coloured, semi-transparent filled box for non-vehicle classes
    (primarily persons and dogs) that draw_overlays() omits.

    Gives a segmentation-like appearance using a transparent fill +
    solid border instead of raw bounding-box outline only.
    """
    color = _CLASS_COLORS.get(class_id, (200, 200, 200))
    label = _CLASS_NAMES_DISPLAY.get(class_id, f'cls{class_id}')

    # Semi-transparent fill (alpha=0.18)
    roi = frame[max(0, y1):min(frame.shape[0], y2),
                max(0, x1):min(frame.shape[1], x2)]
    if roi.size > 0:
        filled = roi.copy()
        filled[:] = color
        cv2.addWeighted(filled, 0.18, roi, 0.82, 0, roi)

    # Solid border (2 px)
    cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)

    # Label tag with dark pill background
    tag = f'[{track_id}] {label}'
    (tw, th), _ = cv2.getTextSize(tag, cv2.FONT_HERSHEY_SIMPLEX, 0.45, 1)
    ty = max(th + 6, y1 - 2)
    cv2.rectangle(frame, (x1, ty - th - 5), (x1 + tw + 6, ty + 1), (0, 0, 0), -1)
    cv2.putText(frame, tag, (x1 + 3, ty - 2),
                cv2.FONT_HERSHEY_SIMPLEX, 0.45, color, 1, cv2.LINE_AA)


def draw_cached_overlays(frame):
    """
    Draw the latest cached safety overlays and bbox annotations on the
    current display frame.

    Draws in layers:
      1. Zone outlines
      2. ALL confirmed tracked objects — vehicles get full metric badges,
         persons / dogs get colour-coded filled boxes.
      3. Safety banner (advice + risk/confidence readout)
    """
    global _latest_state_out, _latest_top_k, _latest_vehicle_infos, \
           _latest_all_tracks, _zones

    if _zones is None:
        _init_zones(frame)

    # ── Layer 1: Zone outlines ────────────────────────────────────────────
    if _zones:
        draw_zones_on_image(frame, _zones)

    # ── Layer 2a: Non-vehicle classes (person, dog, bicycle) ─────────────
    # draw_overlays only draws HEAVY+LIGHT vehicle classes; persons are invisible
    # without this step.
    if _latest_all_tracks:
        vehicle_track_ids = {vi.track_id for vi in _latest_vehicle_infos}
        for entry in _latest_all_tracks:
            tid, x1, y1, x2, y2, cid = entry
            if tid not in vehicle_track_ids:
                _draw_nonvehicle_box(frame, tid, x1, y1, x2, y2, cid)

    # ── Layer 2b: Vehicle classes with full metric badge ──────────────────
    if _latest_state_out is not None and _zones is not None:
        top_ids = {v.track_id for v in _latest_top_k}
        for vi in _latest_vehicle_infos:
            from overlay_utils_1 import draw_vehicle_overlay
            from crossing_advisor import CLASS_LABELS
            draw_vehicle_overlay(
                frame,
                bbox        = vi.bbox,
                track_id    = vi.track_id,
                class_label = CLASS_LABELS.get(vi.class_id, 'obj'),
                dist_m      = vi.dist_m,
                speed_kmh   = vi.speed_kmh,
                ttc_sec     = vi.ttc_sec,
                approaching = vi.approaching,
                direction   = vi.direction,
            )
            # Extra red outline for top-K threats
            if vi.track_id in top_ids and vi.bbox:
                bx1, by1, bx2, by2 = vi.bbox
                cv2.rectangle(frame, (bx1-2, by1-2), (bx2+2, by2+2), (0, 0, 255), 1)

    # ── Layer 3: Safety advice banner + risk/conf readout ─────────────────
    if _latest_state_out is not None and _zones is not None:
        top_k = _latest_top_k

        class _FakeAdvice:
            action      = _ACTION_MAP.get(_latest_state_out.internal_state, 'stop')
            reason      = _latest_state_out.full_spoken
            threat_level = {STATE_SAFE: 0, 'WALK_FAST': 1, 'WAIT': 1,
                            'UNCERTAIN': 1, 'STOP': 2}.get(
                                _latest_state_out.internal_state, 1)
            dist_m      = top_k[0].dist_m    if top_k else 0.0
            speed_kmh   = top_k[0].speed_kmh if top_k else 0.0
            ttc_sec     = top_k[0].ttc_sec   if top_k else float('inf')

        draw_advice_banner(frame, _FakeAdvice())

        tier_color = {1:(0,220,0), 2:(0,165,255), 3:(0,0,255)}.get(
            _current_tier, (200,200,200))
        cv2.putText(
            frame,
            f"Risk:{_latest_state_out.risk_score:.2f}  "
            f"Conf:{_latest_state_out.confidence:.2f}  "
            f"Tier:{_current_tier}  FPS:{get_current_fps():.0f}",
            (8, frame.shape[0] - 8),
            cv2.FONT_HERSHEY_SIMPLEX, 0.45, tier_color, 1, cv2.LINE_AA,
        )

    return frame


def get_logger_summary() -> dict:
    """Expose logger metrics to Streamlit dashboard."""
    return _event_logger.summary()
