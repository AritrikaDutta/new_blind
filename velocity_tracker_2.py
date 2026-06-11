import math
from collections import defaultdict

# Average physical WIDTHS of vehicle classes in meters
# Used to estimate scale for frontal/diagonal camera views
#   0 = bicycle, 1 = bus, 2 = car, 3 = dog, 4 = motorcycle, 5 = person, 6 = scooty, 7 = toto
AVERAGE_FRONTAL_WIDTHS_M = {
    0: 0.6,   # bicycle
    1: 2.5,   # bus
    2: 1.8,   # car
    3: 0.5,   # dog
    4: 0.8,   # motorcycle
    5: 0.5,   # person
    6: 0.8,   # scooty
    7: 1.4    # toto
}

class VelocityTracker:
    def __init__(self, max_history=15):
        self.track_history = defaultdict(list)
        self.max_history = max_history
        self.first_seen = {}
        self.last_bbox = {}
        self.track_class = {}           # track_id → YOLO class_id

    def update(self, track_id, bbox, class_id=None, ego_dx: float = 0.0, ego_dy: float = 0.0):
        """
        Update track history with the latest bounding box.

        Args:
            track_id:  Unique DeepSORT track identifier.
            bbox:      (x1, y1, x2, y2) bounding box.
            class_id:  YOLO class id (0–7).
            ego_dx:    Camera translation this frame (pixels, horizontal).
                       Provided by EgoMotionEstimator.update().
            ego_dy:    Camera translation this frame (pixels, vertical).

        Ego-motion correction (Section 6.4):
            If the camera moves RIGHT by ego_dx pixels, every object in
            the frame appears to shift LEFT by ego_dx.  To remove this
            apparent shift we ADD ego_dx back so the stored cx is in a
            "camera-stabilised" reference frame:
                cx_stabilised = cx_raw + ego_dx
        """
        cx = (bbox[0] + bbox[2]) / 2 + ego_dx   # ego-corrected centre x
        cy = (bbox[1] + bbox[3]) / 2 + ego_dy   # ego-corrected centre y
        area = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1])
        self.track_history[track_id].append((cx, cy, area))
        if len(self.track_history[track_id]) > self.max_history:
            self.track_history[track_id].pop(0)

        self.last_bbox[track_id] = bbox
        if class_id is not None:
            self.track_class[track_id] = class_id
        if track_id not in self.first_seen:
            self.first_seen[track_id] = len(self.track_history[track_id])

    def get_speed_direction(self, track_id):
        history = self.track_history[track_id]
        if len(history) < 2:
            return 0.0, 'unknown'

        dx = history[-1][0] - history[0][0]
        dy = history[-1][1] - history[0][1]
        speed = math.sqrt(dx**2 + dy**2)

        if abs(dx) > abs(dy):
            direction = 'right' if dx > 0 else 'left'
        else:
            direction = 'down' if dy > 0 else 'up'

        return speed, direction

    def get_class_id(self, track_id):
        """Return the YOLO class_id stored for this track, or -1."""
        return self.track_class.get(track_id, -1)

    def get_speed_pixels_per_frame(self, track_id):
        """Smoothed speed in pixels / frame over the history window."""
        history = self.track_history.get(track_id, [])
        if len(history) < 2:
            return 0.0
        dx = history[-1][0] - history[0][0]
        dy = history[-1][1] - history[0][1]
        dist = math.sqrt(dx ** 2 + dy ** 2)
        return dist / (len(history) - 1)   # per-frame average

    def get_approach_info(self, track_id, target_x, target_y, fps=30):
        """
        Return approach diagnostics using ego-corrected history.

        Ego-motion correction has already been applied in update(), so the
        cx values stored in history are already "world-stabilised".  The
        regression therefore reflects real vehicle motion, not camera drift.

        Returns:
            dict with keys: approaching, retreating, dA, dx, dy,
                            motion_axis, TTC_sec, cx, direction
            
            motion_axis:
                "horizontal" — lateral drift dominates (vehicle passing across)
                "vertical"   — depth change dominates (vehicle toward/away)
                "ambiguous"  — insufficient movement for classification
        """
        history = self.track_history.get(track_id, [])
        if len(history) < 3:
            return {
                "approaching": False,
                "retreating":  False,
                "dA":          0.0,
                "dx":          0.0,
                "dy":          0.0,
                "motion_axis": "unknown",
                "TTC_sec":     float('inf'),
                "cx":          history[-1][0] if history else 0.0,
                "direction":   "unknown",
            }

        # Time array in seconds
        n = len(history)
        t = [i / fps for i in range(n)]

        sum_t  = sum(t)
        sum_t2 = sum(ti * ti for ti in t)
        denominator = (n * sum_t2 - sum_t ** 2)

        if denominator == 0:
            dA_dt = dx_dt = dy_dt = 0.0
        else:
            # ── Area regression ─────────────────────────────────────────
            areas  = [h[2] for h in history]
            sum_A  = sum(areas)
            sum_tA = sum(t[i] * areas[i] for i in range(n))
            dA_dt  = (n * sum_tA - sum_t * sum_A) / denominator

            # ── cx regression (lateral; ego-corrected) ───────────────────
            cxs    = [h[0] for h in history]
            sum_cx = sum(cxs)
            sum_tcx= sum(t[i] * cxs[i] for i in range(n))
            dx_dt  = (n * sum_tcx - sum_t * sum_cx) / denominator

            # ── cy regression (vertical; ego-corrected) ──────────────────
            cys    = [h[1] for h in history]
            sum_cy = sum(cys)
            sum_tcy= sum(t[i] * cys[i] for i in range(n))
            dy_dt  = (n * sum_tcy - sum_t * sum_cy) / denominator

        cx, cy, current_area = history[-1]

        # ── Approach / retreat classification ────────────────────────────
        # Area growing >3 %/s  → approaching (vehicle getting bigger in frame)
        # Area shrinking >3%/s → retreating  (vehicle moving away)
        if dA_dt > (0.03 * current_area):
            ttc_sec    = current_area / dA_dt
            approaching = True
            retreating  = False
        elif dA_dt < -(0.03 * current_area):
            ttc_sec    = float('inf')
            approaching = False
            retreating  = True          # vehicle actively moving away
        else:
            ttc_sec    = float('inf')
            approaching = False
            retreating  = False

        # ── Lateral direction ────────────────────────────────────────────
        if dx_dt > 15.0:
            direction = "left_to_right"
        elif dx_dt < -15.0:
            direction = "right_to_left"
        else:
            direction = "straight"

        # ── Motion axis ──────────────────────────────────────────────────
        # "horizontal" when lateral drift clearly dominates depth change
        # "vertical"   when area change or vertical shift dominates
        abs_dx = abs(dx_dt)
        abs_dy = abs(dy_dt)
        if abs_dx > 20.0 and abs_dx > abs_dy * 1.5:
            motion_axis = "horizontal"
        elif approaching or retreating or abs_dy > 10.0:
            motion_axis = "vertical"
        else:
            motion_axis = "ambiguous"

        return {
            "approaching": approaching,
            "retreating":  retreating,
            "dA":          dA_dt,
            "dx":          dx_dt,
            "dy":          dy_dt,
            "motion_axis": motion_axis,
            "TTC_sec":     ttc_sec,
            "cx":          cx,
            "direction":   direction,
        }

    def get_time_to_collision(self, track_id, target_zone):
        history = self.track_history[track_id]
        if len(history) < 2:
            return None

        cx, cy, _ = history[-1]
        prev_cx, prev_cy, _ = history[0]
        dx = cx - prev_cx
        dy = cy - prev_cy
        speed = math.sqrt(dx ** 2 + dy ** 2)
        if speed < 1e-5:
            return None

        zx = (target_zone["x1"] + target_zone["x2"]) / 2
        zy = (target_zone["y1"] + target_zone["y2"]) / 2
        dist = math.sqrt((cx - zx) ** 2 + (cy - zy) ** 2)
        return round(dist / speed, 2)

    def is_moving_toward_zone(self, track_id, target_zone):
        history = self.track_history[track_id]
        if len(history) < 2:
            return False

        cx, cy, _ = history[-1]
        prev_cx, prev_cy, _ = history[0]
        dx = cx - prev_cx
        dy = cy - prev_cy

        zx = (target_zone["x1"] + target_zone["x2"]) / 2
        zy = (target_zone["y1"] + target_zone["y2"]) / 2

        vx = zx - cx
        vy = zy - cy

        dot_product = dx * vx + dy * vy
        return dot_product > 0

    def get_features(self, track_id, zones=None):
        if track_id not in self.track_history or len(self.track_history[track_id]) < 2:
            return None

        history = self.track_history[track_id]
        cx, cy, _ = history[-1]
        prev_cx, prev_cy, _ = history[0]
        dx = cx - prev_cx
        dy = cy - prev_cy
        speed = math.sqrt(dx**2 + dy**2)
        direction_angle = math.degrees(math.atan2(dy, dx)) if dx != 0 else 90.0
        is_stationary = 1 if speed < 1.0 else 0
        time_visible = len(history)

        bbox = self.last_bbox.get(track_id)
        if bbox is None or zones is None:
            return None

        x1, y1, x2, y2 = bbox
        crossing = zones["CROSSING"]
        zx1, zy1, zx2, zy2 = crossing["x1"], crossing["y1"], crossing["x2"], crossing["y2"]
        iou_crossing = self._iou(bbox, (zx1, zy1, zx2, zy2))

        bbox_center = ((x1 + x2) / 2, (y1 + y2) / 2)
        zone_left = zones["LEFT"]
        zone_right = zones["RIGHT"]

        in_left = 1 if self._intersects(bbox, zone_left) else 0
        in_right = 1 if self._intersects(bbox, zone_right) else 0

        crossing_center_x = (crossing["x1"] + crossing["x2"]) / 2
        crossing_center_y = (crossing["y1"] + crossing["y2"]) / 2
        dist_to_crossing = math.sqrt((cx - crossing_center_x) ** 2 + (cy - crossing_center_y) ** 2)

        return {
            "speed": round(speed, 2),
            "direction_angle": round(direction_angle, 2),
            "dx": round(dx, 2),
            "dy": round(dy, 2),
            "is_stationary": is_stationary,
            "time_visible": time_visible,
            "distance_to_crossing": round(dist_to_crossing, 2),
            "iou_crossing": round(iou_crossing, 2),
            "in_left_zone": in_left,
            "in_right_zone": in_right
        }

    def _intersects(self, bbox, zone):
        x1, y1, x2, y2 = bbox
        zx1, zy1, zx2, zy2 = zone["x1"], zone["y1"], zone["x2"], zone["y2"]
        return not (x2 < zx1 or x1 > zx2 or y2 < zy1 or y1 > zy2)

    def _iou(self, boxA, boxB):
        xA = max(boxA[0], boxB[0])
        yA = max(boxA[1], boxB[1])
        xB = min(boxA[2], boxB[2])
        yB = min(boxA[3], boxB[3])

        interArea = max(0, xB - xA) * max(0, yB - yA)
        boxAArea = (boxA[2] - boxA[0]) * (boxA[3] - boxA[1])
        boxBArea = (boxB[2] - boxB[0]) * (boxB[3] - boxB[1])

        if boxAArea + boxBArea - interArea == 0:
            return 0.0
        return interArea / float(boxAArea + boxBArea - interArea)
