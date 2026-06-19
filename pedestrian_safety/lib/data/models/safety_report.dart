class SafetyReport {
  final int falseSafeCount;
  final double falseSafeRate;
  final int stateSwitches;
  final String logPath;
  final List<double> riskHistory;

  const SafetyReport({
    required this.falseSafeCount,
    required this.falseSafeRate,
    required this.stateSwitches,
    required this.logPath,
    required this.riskHistory,
  });

  factory SafetyReport.empty() {
    return const SafetyReport(
      falseSafeCount: 0,
      falseSafeRate: 0.0,
      stateSwitches: 0,
      logPath: '',
      riskHistory: [],
    );
  }
}
