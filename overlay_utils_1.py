# overlay_utils_1.py

import cv2
import math

# ─────────────────────────────────────────────────────────────────────────────
# Zone layout helpers
# ─────────────────────────────────────────────────────────────────────────────

def define_zones(image_width, image_height):
    left_w         = 0.20
    right_w        = 0.20
    crossing_top   = 0.4
    crossing_bottom = 1.0

    zones = {
        "CROSSING": {
            "x1": int(image_width * left_w),
            "y1": int(image_height * crossing_top),
            "x2": int(image_width * (1 - right_w)),
            "y2": int(image_height * crossing_bottom),
        },
        "LEFT": {
            "x1": 0,
            "y1": 0,
            "x2": int(image_width * left_w),
            "y2": image_height,
        },
        "RIGHT": {
            "x1": int(image_width * (1 - right_w)),
            "y1": 0,
            "x2": image_width,
            "y2": image_height,
        },
        "CENTER_DISTANT": {
            "x1": int(image_width * left_w),
            "y1": 0,
            "x2": int(image_width * (1 - right_w)),
            "y2": int(image_height * crossing_top),
        },
    }
    return zones


def get_all_zones_for_bbox(bbox, zones):
    x1, y1, x2, y2 = bbox
    matching_zones = []
    for name, z in zones.items():
        zx1, zy1, zx2, zy2 = z["x1"], z["y1"], z["x2"], z["y2"]
        if not (x2 < zx1 or x1 > zx2 or y2 < zy1 or y1 > zy2):
            matching_zones.append(name)
    return matching_zones


def draw_zones_on_image(image, zones, color_map=None):
    if color_map is None:
        color_map = {
            "CROSSING":       (0, 255, 0),
            "LEFT":           (255, 0, 0),
            "RIGHT":          (0, 0, 255),
            "CENTER_DISTANT": (0, 255, 255),
        }
    for name, z in zones.items():
        color = color_map.get(name, (255, 255, 255))
        cv2.rectangle(image, (z["x1"], z["y1"]), (z["x2"], z["y2"]), color, 2)
        cv2.putText(image, name, (z["x1"] + 5, z["y1"] + 20),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
    return image


# ─────────────────────────────────────────────────────────────────────────────
# Vehicle overlay — rich per-detection badge
# ─────────────────────────────────────────────────────────────────────────────

_TTC_BAR_W  = 60    # px — width of TTC countdown bar
_TTC_BAR_H  = 8     # px — height of TTC countdown bar
_TTC_MAX    = 12.0  # seconds that maps to an "empty" bar


def draw_vehicle_overlay(
    frame,
    bbox: tuple,
    track_id: int,
    class_label: str,
    dist_m: float,
    speed_kmh: float,
    ttc_sec: float,
    approaching: bool,
    direction: str,
):
    """
    Draw a rich per-vehicle information badge on the frame.

    Shows:
      • Coloured bounding box  (cyan = approaching, grey = moving away)
      • Class label + track ID
      • Distance in metres
      • Approach speed in km/h
      • TTC countdown bar  (green → yellow → red)
      • Direction arrow glyph  (← → ↑ or AWAY)

    Args:
        frame:       BGR image to draw on (modified in-place).
        bbox:        (x1, y1, x2, y2) bounding box.
        track_id:    DeepSORT track ID.
        class_label: Human-readable class name (e.g. "car").
        dist_m:      Estimated distance in metres.
        speed_kmh:   Estimated approach speed in km/h.
        ttc_sec:     Time-to-collision in seconds (float('inf') if not approaching).
        approaching: True if vehicle is getting closer.
        direction:   "left_to_right" | "right_to_left" | "straight" | "unknown".
    """
    x1, y1, x2, y2 = int(bbox[0]), int(bbox[1]), int(bbox[2]), int(bbox[3])

    # ── Bounding box colour ────────────────────────────────────────────
    if approaching:
        if ttc_sec < 4.0:
            box_color = (0, 0, 255)        # red  — danger
        elif ttc_sec < 8.0:
            box_color = (0, 165, 255)      # orange — caution
        else:
            box_color = (0, 255, 255)      # cyan  — approaching but safe
    else:
        box_color = (160, 160, 160)        # grey  — moving away / static

    thickness = 3 if approaching and ttc_sec < 6.0 else 2
    cv2.rectangle(frame, (x1, y1), (x2, y2), box_color, thickness)

    # ── Direction arrow glyph ─────────────────────────────────────────
    arrow = {"left_to_right": " ->", "right_to_left": "<- ", "straight": " ^ ", "unknown": "   "}.get(direction, "   ")

    # ── Text lines ────────────────────────────────────────────────────
    ttc_str = f"TTC:{ttc_sec:.1f}s" if ttc_sec != float('inf') else "TTC:---"
    lines = [
        f"[{track_id}] {class_label}{arrow}",
        f"Dist:{dist_m:.1f}m  {speed_kmh:.0f}km/h",
        ttc_str,
    ]

    font       = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.45
    font_thick = 1
    line_h     = 14

    text_x = x1
    text_y = max(line_h * len(lines) + 4, y1 - 4)   # place above box

    # Semi-transparent dark background for readability
    bg_w = 170
    bg_h = line_h * len(lines) + 4
    bg_y1 = text_y - bg_h + 2
    bg_x2 = min(frame.shape[1], text_x + bg_w)
    if bg_y1 >= 0 and text_x >= 0:
        overlay = frame.copy()
        cv2.rectangle(overlay, (text_x, bg_y1), (bg_x2, text_y + 2), (0, 0, 0), -1)
        cv2.addWeighted(overlay, 0.45, frame, 0.55, 0, frame)

    for i, line in enumerate(lines):
        y_pos = text_y - (len(lines) - 1 - i) * line_h
        cv2.putText(frame, line, (text_x + 2, y_pos),
                    font, font_scale, box_color, font_thick, cv2.LINE_AA)

    # ── TTC countdown bar ─────────────────────────────────────────────
    if approaching and ttc_sec != float('inf'):
        bar_x = x1
        bar_y = y2 + 4

        # Fraction full = how much time remains (more time = more green = more bar)
        frac = min(1.0, ttc_sec / _TTC_MAX)

        # Colour: red (danger) → yellow (caution) → green (safe)
        if frac < 0.33:
            bar_col = (0, 0, 255)
        elif frac < 0.66:
            bar_col = (0, 165, 255)
        else:
            bar_col = (0, 220, 0)

        bar_right = bar_x + _TTC_BAR_W
        bar_bot   = bar_y + _TTC_BAR_H
        if bar_right <= frame.shape[1] and bar_bot <= frame.shape[0]:
            # Background (dark)
            cv2.rectangle(frame, (bar_x, bar_y), (bar_right, bar_bot), (40, 40, 40), -1)
            # Filled portion
            fill_w = int(_TTC_BAR_W * frac)
            cv2.rectangle(frame, (bar_x, bar_y), (bar_x + fill_w, bar_bot), bar_col, -1)
            # Border
            cv2.rectangle(frame, (bar_x, bar_y), (bar_right, bar_bot), (200, 200, 200), 1)


# ─────────────────────────────────────────────────────────────────────────────
# Advice banner — full-width HUD at the top of the frame
# ─────────────────────────────────────────────────────────────────────────────

_ACTION_COLORS = {
    "cross_normal":      (0,   200,   0),
    "cross_fast":        (0,   200, 200),
    "signal_hand_left":  (0,   165, 255),
    "signal_hand_right": (0,   165, 255),
    "stop":              (0,     0, 255),
}

_ACTION_ICONS = {
    "cross_normal":      "SAFE TO CROSS",
    "cross_fast":        "WALK FAST",
    "signal_hand_left":  "RAISE LEFT HAND",
    "signal_hand_right": "RAISE RIGHT HAND",
    "stop":              "STOP !",
}


def draw_advice_banner(frame, advice):
    """
    Draw a full-width semi-transparent banner at the top of the frame
    showing the current crossing action, reason, and key metrics.

    Args:
        frame:  BGR image (modified in-place).
        advice: CrossingAdvice dataclass from crossing_advisor.py.
    """
    h, w = frame.shape[:2]
    banner_h = 70

    # Semi-transparent background
    overlay = frame.copy()
    color = _ACTION_COLORS.get(advice.action, (0, 200, 0))
    dark  = tuple(max(0, c - 140) for c in color)
    cv2.rectangle(overlay, (0, 0), (w, banner_h), dark, -1)
    cv2.addWeighted(overlay, 0.55, frame, 0.45, 0, frame)

    # Primary action text (large)
    icon = _ACTION_ICONS.get(advice.action, advice.action.upper())
    cv2.putText(frame, icon, (16, 38),
                cv2.FONT_HERSHEY_SIMPLEX, 1.1, color, 3, cv2.LINE_AA)

    # Reason / detail line (small)
    cv2.putText(frame, advice.reason[:80], (16, 60),
                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (220, 220, 220), 1, cv2.LINE_AA)

    # Right-side metrics panel
    if advice.threat_level > 0 and advice.dist_m > 0:
        metrics = (
            f"Dist {advice.dist_m:.1f}m  "
            f"Speed {advice.speed_kmh:.0f}km/h  "
            f"TTC {advice.ttc_sec:.1f}s"
            if advice.ttc_sec != float('inf') else
            f"Dist {advice.dist_m:.1f}m  Speed {advice.speed_kmh:.0f}km/h"
        )
        cv2.putText(frame, metrics, (w - 360, 38),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 1, cv2.LINE_AA)

    return frame
