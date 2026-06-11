"""
test_geometric_risk.py
======================
Quick unit test for the direction-aware geometric safety model.

Tests the 5 key scenarios described by the user:
  1. Vehicle moving away                     → SAFE
  2. Horizontal vehicle far away             → SAFE / WALK_FAST at most
  3. Horizontal vehicle very close           → STOP
  4. Vertical toward camera in CROSSING zone → STOP
  5. Vertical toward camera in LEFT zone     → WAIT

Run with: python test_geometric_risk.py
"""

from crossing_advisor import VehicleInfo
from crossing_advisor import CrossingConfig
from risk_scorer import compute_risk, rank_threats, _geometric_risk

# ── Shared zone definitions ──────────────────────────────────────────────────
ALL_ZONES = {
    "LEFT":     {"x1":   0, "y1": 200, "x2": 200, "y2": 600},
    "CROSSING": {"x1": 200, "y1": 200, "x2": 440, "y2": 600},
    "RIGHT":    {"x1": 440, "y1": 200, "x2": 640, "y2": 600},
}
CROSSING_ZONE = ALL_ZONES["CROSSING"]
CFG = CrossingConfig()

FRAME_W = 640

def _make_vi(
    track_id=1, class_id=2,
    dx=0.0, dA=0.0, ttc_sec=float("inf"),
    dist_m=10.0, speed_kmh=30.0,
    approaching=False, retreating=False,
    direction="unknown", motion_axis="unknown",
    bbox=(250, 250, 400, 500),   # centre of CROSSING zone by default
):
    return VehicleInfo(
        track_id=track_id,
        class_id=class_id,
        dx=dx, dA=dA,
        ttc_sec=ttc_sec,
        dist_m=dist_m,
        speed_kmh=speed_kmh,
        speed_mps=speed_kmh / 3.6,
        cx=(bbox[0]+bbox[2])/2,
        approaching=approaching,
        retreating=retreating,
        direction=direction,
        motion_axis=motion_axis,
        bbox=bbox,
    )


def run_case(name, vi, expect_state):
    gr = _geometric_risk(vi, CROSSING_ZONE, ALL_ZONES)
    top_k = rank_threats([vi], CROSSING_ZONE, k=3)
    risk, conf, cue, state = compute_risk(
        top_k, CROSSING_ZONE, ALL_ZONES, FRAME_W, CFG
    )
    ok = (state == expect_state) or (
        # Accept WALK_FAST as "effectively safe" for the "far horizontal" case
        expect_state in ("SAFE", "WALK_FAST") and state in ("SAFE", "WALK_FAST")
    )
    status = "✅ PASS" if ok else "❌ FAIL"
    print(f"{status}  {name}")
    print(f"       geom_risk={gr:.3f}  risk={risk:.3f}  conf={conf:.2f}  state={state}  (expected≈{expect_state})")
    if cue:
        print(f"       cue: {cue}")
    print()
    return ok


# ── Test cases ────────────────────────────────────────────────────────────────
results = []

# 1. Vehicle moving away — bounding box shrinking, retreating=True
results.append(run_case(
    "1. Vehicle moving AWAY (retreating=True)",
    _make_vi(dA=-5000, approaching=False, retreating=True,
             direction="straight", motion_axis="vertical",
             bbox=(250, 250, 400, 500)),
    expect_state="SAFE",
))

# 2. Horizontal vehicle FAR away (18 m, not in crossing zone)
results.append(run_case(
    "2. Horizontal vehicle FAR away (18 m, in RIGHT zone)",
    _make_vi(dx=60.0, dA=0, ttc_sec=float("inf"),
             dist_m=18.0, speed_kmh=40.0,
             approaching=False, retreating=False,
             direction="left_to_right", motion_axis="horizontal",
             bbox=(450, 350, 600, 520)),   # RIGHT zone
    expect_state="SAFE",
))

# 3. Horizontal vehicle CLOSE (3 m, overlapping crossing zone)
results.append(run_case(
    "3. Horizontal vehicle CLOSE (3 m, in CROSSING zone)",
    _make_vi(dx=55.0, dA=0, ttc_sec=1.5,
             dist_m=3.0, speed_kmh=60.0,
             approaching=False, retreating=False,
             direction="left_to_right", motion_axis="horizontal",
             bbox=(220, 250, 420, 500)),   # CROSSING zone
    expect_state="STOP",
))

# 4. Vertical (straight toward camera) in CROSSING zone
results.append(run_case(
    "4. Vertical TOWARD user, in CROSSING zone",
    _make_vi(dx=0.0, dA=8000, ttc_sec=2.5,
             dist_m=5.0, speed_kmh=50.0,
             approaching=True, retreating=False,
             direction="straight", motion_axis="vertical",
             bbox=(250, 300, 400, 520)),   # CROSSING zone
    expect_state="STOP",
))

# 5. Vertical toward camera in LEFT zone — should WAIT
results.append(run_case(
    "5. Vertical TOWARD user, in LEFT zone (watch)",
    _make_vi(dx=0.0, dA=3000, ttc_sec=6.0,
             dist_m=10.0, speed_kmh=30.0,
             approaching=True, retreating=False,
             direction="straight", motion_axis="vertical",
             bbox=(50, 300, 180, 520)),    # LEFT zone
    expect_state="WAIT",
))

# ── Summary ──────────────────────────────────────────────────────────────────
passed = sum(results)
total  = len(results)
print(f"{'='*50}")
print(f"Results: {passed}/{total} passed")
if passed == total:
    print("🟢 All geometric model tests passed!")
else:
    print("🔴 Some tests failed — review logic above.")
