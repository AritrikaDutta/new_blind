/// Safety-related constants ported from Python crossing_advisor.py and risk_scorer.py.
class SafetyConstants {
  SafetyConstants._();

  // ── Default crossing config ───────────────────────────────────────────
  static const double defaultRoadWidthM = 8.0;
  static const double defaultWalkSpeedMps = 0.8;
  static const double defaultSafetyMarginSec = 2.5;
  static const double defaultMinConfidence = 0.65;
  static const int defaultSmoothingFrames = 3;
  static const int defaultThreatK = 4;

  // ── TTC multipliers (Section 9) ───────────────────────────────────────
  static const double stopMult = 1.00;
  static const double fastMult = 1.40;
  static const double hardStopSec = 2.0;

  // ── Risk weight vector ────────────────────────────────────────────────
  static const double wTtc = 0.35;
  static const double wSpeed = 0.20;
  static const double wGeom = 0.45;

  // ── Risk normalisation anchors ────────────────────────────────────────
  static const double maxSpeedKmh = 80.0;
  static const double ttcSafeSec = 12.0;

  // ── Risk → state thresholds ───────────────────────────────────────────
  static const double threshStop = 0.70;
  static const double threshWait = 0.50;
  static const double threshWalkFast = 0.25;

  // ── Geometric distance thresholds ─────────────────────────────────────
  static const double nearM = 8.0;
  static const double farM = 14.0;

  // ── Detection class IDs ───────────────────────────────────────────────
  static const int classBicycle = 0;
  static const int classBus = 1;
  static const int classCar = 2;
  static const int classDog = 3;
  static const int classMotorcycle = 4;
  static const int classPerson = 5;
  static const int classScooty = 6;
  static const int classToto = 7;

  static const Set<int> heavyClasses = {1, 2, 4, 6, 7};
  static const Set<int> lightClasses = {0};

  static const Map<int, String> classLabels = {
    0: 'bicycle',
    1: 'bus',
    2: 'car',
    3: 'dog',
    4: 'motorcycle',
    5: 'person',
    6: 'scooty',
    7: 'toto',
  };

  // ── Zone layout fractions ─────────────────────────────────────────────
  static const double zoneLeftWidth = 0.20;
  static const double zoneRightWidth = 0.20;
  static const double zoneCrossingTop = 0.40;
  static const double zoneCrossingBottom = 1.0;

  // ── Performance tier FPS thresholds ───────────────────────────────────
  static const double tier1Fps = 12.0;
  static const double tier3Fps = 1.5;

  // ── Voice alert cooldown ──────────────────────────────────────────────
  static const double voiceCooldownSec = 8.0;
}
