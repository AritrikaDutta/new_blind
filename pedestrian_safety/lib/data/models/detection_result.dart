import 'dart:ui';
import '../../core/constants/safety_constants.dart';

class DetectionResult {
  final Rect bbox;
  final double score;
  final int classId;

  const DetectionResult({
    required this.bbox,
    required this.score,
    required this.classId,
  });

  String get label => SafetyConstants.classLabels[classId] ?? 'unknown';
}
