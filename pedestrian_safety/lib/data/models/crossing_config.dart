import '../../core/constants/safety_constants.dart';

class CrossingConfig {
  final double roadWidthM;
  final double walkSpeedMps;
  final bool useAiDepth;
  final bool useEgoMotion;
  final int threatRankK;
  final int smoothingFrames;
  final double minConfidenceThreshold;
  final double safetyMarginSec;

  CrossingConfig({
    required this.roadWidthM,
    required this.walkSpeedMps,
    required this.useAiDepth,
    required this.useEgoMotion,
    required this.threatRankK,
    required this.smoothingFrames,
    required this.minConfidenceThreshold,
    required this.safetyMarginSec,
  });

  factory CrossingConfig.defaultConfig() {
    return CrossingConfig(
      roadWidthM: SafetyConstants.defaultRoadWidthM,
      walkSpeedMps: SafetyConstants.defaultWalkSpeedMps,
      useAiDepth: true,
      useEgoMotion: true,
      threatRankK: SafetyConstants.defaultThreatK,
      smoothingFrames: SafetyConstants.defaultSmoothingFrames,
      minConfidenceThreshold: SafetyConstants.defaultMinConfidence,
      safetyMarginSec: SafetyConstants.defaultSafetyMarginSec,
    );
  }

  CrossingConfig copyWith({
    double? roadWidthM,
    double? walkSpeedMps,
    bool? useAiDepth,
    bool? useEgoMotion,
    int? threatRankK,
    int? smoothingFrames,
    double? minConfidenceThreshold,
    double? safetyMarginSec,
  }) {
    return CrossingConfig(
      roadWidthM: roadWidthM ?? this.roadWidthM,
      walkSpeedMps: walkSpeedMps ?? this.walkSpeedMps,
      useAiDepth: useAiDepth ?? this.useAiDepth,
      useEgoMotion: useEgoMotion ?? this.useEgoMotion,
      threatRankK: threatRankK ?? this.threatRankK,
      smoothingFrames: smoothingFrames ?? this.smoothingFrames,
      minConfidenceThreshold: minConfidenceThreshold ?? this.minConfidenceThreshold,
      safetyMarginSec: safetyMarginSec ?? this.safetyMarginSec,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'roadWidthM': roadWidthM,
      'walkSpeedMps': walkSpeedMps,
      'useAiDepth': useAiDepth,
      'useEgoMotion': useEgoMotion,
      'threatRankK': threatRankK,
      'smoothingFrames': smoothingFrames,
      'minConfidenceThreshold': minConfidenceThreshold,
      'safetyMarginSec': safetyMarginSec,
    };
  }

  factory CrossingConfig.fromJson(Map<String, dynamic> json) {
    return CrossingConfig(
      roadWidthM: (json['roadWidthM'] as num?)?.toDouble() ?? SafetyConstants.defaultRoadWidthM,
      walkSpeedMps: (json['walkSpeedMps'] as num?)?.toDouble() ?? SafetyConstants.defaultWalkSpeedMps,
      useAiDepth: json['useAiDepth'] as bool? ?? true,
      useEgoMotion: json['useEgoMotion'] as bool? ?? true,
      threatRankK: json['threatRankK'] as int? ?? SafetyConstants.defaultThreatK,
      smoothingFrames: json['smoothingFrames'] as int? ?? SafetyConstants.defaultSmoothingFrames,
      minConfidenceThreshold: (json['minConfidenceThreshold'] as num?)?.toDouble() ?? SafetyConstants.defaultMinConfidence,
      safetyMarginSec: (json['safetyMarginSec'] as num?)?.toDouble() ?? SafetyConstants.defaultSafetyMarginSec,
    );
  }
}
