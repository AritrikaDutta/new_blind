import 'dart:ui';

class Vehicle {
  final int trackId;
  final int classId;
  final String classLabel;
  final double distM;
  final double speedKmh;
  final double speedMps;
  final double ttcSec;
  final double cx;
  final bool approaching;
  final bool retreating;
  final String direction;
  final String motionAxis;
  final Rect bbox;

  const Vehicle({
    required this.trackId,
    required this.classId,
    required this.classLabel,
    required this.distM,
    required this.speedKmh,
    required this.speedMps,
    required this.ttcSec,
    required this.cx,
    required this.approaching,
    required this.retreating,
    required this.direction,
    required this.motionAxis,
    required this.bbox,
  });

  String get category {
    if (classId == 0) return 'light';
    if (const {1, 2, 4, 6, 7}.contains(classId)) return 'heavy';
    return 'ignored';
  }
}
