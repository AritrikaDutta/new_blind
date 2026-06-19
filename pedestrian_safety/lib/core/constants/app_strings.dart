class AppStrings {
  AppStrings._();

  static const String appTitle = 'Pedestrian Safety Assistant';
  static const String appSubtitle =
      'Real-time crossing safety for visually impaired pedestrians';
  static const String appTagline = 'Hybrid Physics + AI';

  // ── Home screen ───────────────────────────────────────────────────────
  static const String liveCamera = 'Live Camera';
  static const String liveCameraDesc = 'Real-time detection using device camera';
  static const String settings = 'Settings';
  static const String settingsDesc = 'Configure accessibility & safety parameters';

  // ── Safety states ─────────────────────────────────────────────────────
  static const String stateSafe = 'SAFE';
  static const String stateWalkFast = 'WALK_FAST';
  static const String stateWait = 'WAIT';
  static const String stateUncertain = 'UNCERTAIN';
  static const String stateStop = 'STOP';

  // ── Spoken text ───────────────────────────────────────────────────────
  static const String spokenCrossNow = 'Cross now';
  static const String spokenWalkFaster = 'Walk faster';
  static const String spokenPleaseWait = 'Please wait';
  static const String spokenStop = 'Stop';

  // ── Banner action labels ──────────────────────────────────────────────
  static const String bannerSafeToCross = 'SAFE TO CROSS';
  static const String bannerWalkFast = 'WALK FAST';
  static const String bannerRaiseLeftHand = 'RAISE LEFT HAND';
  static const String bannerRaiseRightHand = 'RAISE RIGHT HAND';
  static const String bannerStop = 'STOP !';

  // ── Metrics labels ────────────────────────────────────────────────────
  static const String fps = 'FPS';
  static const String tier = 'Tier';
  static const String falseSafe = 'False-Safe';
  static const String stateSwitches = 'State Switches';
  static const String riskScore = 'Risk';
  static const String confidence = 'Confidence';

  // ── Settings labels ───────────────────────────────────────────────────
  static const String accessibilitySettings = 'Accessibility Settings';
  static const String pedestrianSettings = 'Pedestrian Settings';
  static const String walkingSpeed = 'Walking Speed (m/s)';
  static const String roadWidth = 'Road Width (m)';
  static const String safetyMargin = 'Safety Margin (s)';
  static const String crossingTime = 'Crossing Time';
  static const String safeTtcLimit = 'Safe TTC Limit';

  // ── Report ────────────────────────────────────────────────────────────
  static const String sessionReport = 'Session Safety Report';
  static const String falseSafeEvents = 'False-Safe Events';
  static const String falseSafeRate = 'False-Safe Rate';
  static const String totalStateSwitches = 'Total State Switches';
}
