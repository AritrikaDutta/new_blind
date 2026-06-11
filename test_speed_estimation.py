"""
test_speed_estimation.py
========================
Full physics + AI hybrid pipeline for pedestrian crossing safety.

Pipeline (one frame):
  1. Ego-motion estimation  — remove camera-walking drift
  2. YOLO detection         — find vehicles
  3. AI depth map           — MiDaS on GPU (optional, async-style: computed once
                              per frame and reused for all detections)
  4. DeepSORT tracking      — assign stable IDs across frames
  5. Per-track update:
       a. VelocityTracker   — ego-corrected lateral + area regression
       b. MotionEstimator   — metric distance, approach speed, metric TTC
       c. AI depth fusion   — refine physics distance with MiDaS scale
  6. CrossingAdvisor.assess — user-crossing time model → action decision
  7. Voice feedback         — emit audio label / event
  8. Overlay drawing        — rich per-vehicle badge + HUD banner

Configuration knobs (change here, everything else adapts):
"""

import cv2
from ultralytics import YOLO
from deep_sort_realtime.deepsort_tracker import DeepSort

from velocity_tracker_2  import VelocityTracker
from motion_estimator    import MotionEstimator
from ego_motion          import EgoMotionEstimator
from depth_estimator     import DepthEstimator
from crossing_advisor    import CrossingAdvisor, VehicleInfo
from overlay_utils_1     import (define_zones, draw_zones_on_image,
                                  draw_vehicle_overlay, draw_advice_banner)
from voice_feedback_2    import VoiceAlertManager

# ──────────────────────────────────────────────────────────────────────────────
# CONFIG — edit these values to tune the system
# ──────────────────────────────────────────────────────────────────────────────
VIDEO_PATH    = "data/video 9.mp4"
OUTPUT_PATH   = "data/output_video9_v3.mp4"

USE_AI_DEPTH  = True       # Set False to skip MiDaS (faster, less accurate)
EGO_MOTION    = True       # Set False for a static camera (e.g. tripod test)
ROAD_WIDTH_M  = 8.0        # Typical 2-lane Indian road (metres)
FOCAL_PX      = 900.0      # Phone camera focal length in pixels at 1080p
                            # Calibrate: FOCAL_PX = pixel_width * known_dist / real_width

DRAW_ZONES    = True        # Draw crossing / left / right zone rectangles
# ──────────────────────────────────────────────────────────────────────────────


def main():
    cap = cv2.VideoCapture(VIDEO_PATH)
    if not cap.isOpened():
        print(f"[Error] Cannot open {VIDEO_PATH}")
        return

    fps    = cap.get(cv2.CAP_PROP_FPS) or 30.0
    width  = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out    = cv2.VideoWriter(OUTPUT_PATH, fourcc, fps, (width, height))

    # ── Initialise all modules ─────────────────────────────────────────
    print("[Init] Loading YOLO model …")
    model           = YOLO("best.pt")

    tracker         = DeepSort(max_age=30)
    velocity_tracker = VelocityTracker()
    motion_estimator = MotionEstimator(focal_px=FOCAL_PX)
    ego_estimator    = EgoMotionEstimator(enabled=EGO_MOTION)
    depth_estimator  = DepthEstimator(enabled=USE_AI_DEPTH)
    advisor          = CrossingAdvisor(road_width_m=ROAD_WIDTH_M)
    voice_alert      = VoiceAlertManager()

    zones = define_zones(width, height)
    cz    = zones.get("CROSSING", {})
    target_x = (cz.get("x1", 0) + cz.get("x2", width))  / 2
    target_y = (cz.get("y1", 0) + cz.get("y2", height)) / 2

    frame_count = 0
    print(f"[Start] Processing {VIDEO_PATH} …\n")

    while cap.isOpened():
        ret, frame = cap.read()
        if not ret:
            break

        frame_count += 1
        timestamp_sec = frame_count / fps

        # ── Step 1: Ego-motion ────────────────────────────────────────
        ego_dx, ego_dy = ego_estimator.update(frame)

        # ── Step 2: YOLO detection ────────────────────────────────────
        results    = model(frame, verbose=False)[0]
        detections = []
        for r in results.boxes.data.tolist():
            x1, y1, x2, y2, score, cid = r
            cid = int(cid)
            if cid in range(8):
                detections.append(([x1, y1, x2 - x1, y2 - y1], score, cid))

        # ── Step 3: AI depth map (one per frame, shared by all boxes) ─
        depth_map = depth_estimator.get_depth_map(frame) if USE_AI_DEPTH else None

        # ── Step 4: DeepSORT tracking ─────────────────────────────────
        tracks = tracker.update_tracks(detections, frame=frame)

        # ── Step 5: Per-track update ──────────────────────────────────
        vehicle_infos = []

        for track in tracks:
            if not track.is_confirmed():
                continue

            track_id = track.track_id
            x1, y1, x2, y2 = map(int, track.to_ltrb())
            class_id = getattr(track, "det_class", -1)
            bbox     = (x1, y1, x2, y2)

            # 5a — Velocity tracker (ego-corrected lateral + area)
            velocity_tracker.update(
                track_id, bbox, class_id,
                ego_dx=ego_dx, ego_dy=ego_dy
            )

            # 5b — Approach info from ego-corrected history
            app_info = velocity_tracker.get_approach_info(
                track_id, target_x, target_y, fps
            )

            # 5c — AI depth scale for this bbox
            ai_scale = 1.0
            if depth_map is not None:
                physics_prelim = motion_estimator.estimate_distance(
                    x2 - x1, class_id, ai_depth_scale=1.0
                )
                ai_scale = depth_estimator.get_bbox_scale(
                    depth_map, bbox, physics_prelim
                )

            # 5d — Metric distance + speed from physics model (+ AI scale)
            motion_estimator.update(
                track_id, bbox, class_id, timestamp_sec,
                ai_depth_scale=ai_scale
            )
            phys = motion_estimator.get_estimate(track_id)

            # ── Merge: prefer physics TTC when available (more reliable metric),
            #          use area-growth TTC as cross-check.
            #          If physics says approaching but area growth says not,
            #          trust physics (handles fast-approaching head-on vehicles).
            approaching = phys["approaching"] or app_info["approaching"]
            ttc_sec = phys["ttc_sec"]
            if ttc_sec == float('inf') and app_info["TTC_sec"] != float('inf'):
                # Fall back to area-growth TTC if physics can't compute one
                ttc_sec = app_info["TTC_sec"]

            vi = VehicleInfo(
                track_id   = track_id,
                class_id   = class_id,
                dx         = app_info.get("dx",        0.0),
                dA         = app_info.get("dA",        0.0),
                ttc_sec    = ttc_sec,
                dist_m     = phys["dist_m"],
                speed_kmh  = phys["speed_kmh"],
                speed_mps  = phys["speed_mps"],
                cx         = app_info.get("cx",        0.0),
                approaching = approaching,
                direction  = app_info.get("direction", "unknown"),
                bbox       = bbox,
            )
            vehicle_infos.append(vi)

            # ── Per-vehicle overlay ───────────────────────────────────
            from crossing_advisor import CLASS_LABELS
            label = CLASS_LABELS.get(class_id, "unknown")
            draw_vehicle_overlay(
                frame, bbox, track_id, label,
                dist_m     = phys["dist_m"],
                speed_kmh  = phys["speed_kmh"],
                ttc_sec    = ttc_sec,
                approaching = approaching,
                direction  = app_info.get("direction", "unknown"),
            )

        # ── Step 6: Crossing advisor ──────────────────────────────────
        advice = advisor.assess(vehicle_infos, width)

        # ── Step 7: Voice feedback ────────────────────────────────────
        voice_alert.update_with_advice(advice, timestamp_sec)

        # ── Step 8: Overlay ───────────────────────────────────────────
        if DRAW_ZONES:
            draw_zones_on_image(frame, zones)

        draw_advice_banner(frame, advice)

        # Ego-motion debug indicator (top-right corner)
        if EGO_MOTION:
            ego_txt = f"EGO dx:{ego_dx:+.1f} dy:{ego_dy:+.1f}"
            cv2.putText(frame, ego_txt, (width - 240, height - 12),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.42, (200, 200, 50), 1, cv2.LINE_AA)

        out.write(frame)

        if frame_count % 30 == 0:
            ai_str = f"  depth_scale≈{ai_scale:.2f}" if USE_AI_DEPTH else ""
            print(
                f"  Frame {frame_count:5d} | "
                f"ego=({ego_dx:+.1f},{ego_dy:+.1f}) | "
                f"action={advice.action:<20s} | "
                f"TTC={advice.ttc_sec:.1f}s{ai_str}"
            )

    cap.release()
    out.release()
    print(f"\n[Done] Saved → {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
