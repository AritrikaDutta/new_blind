import 'dart:ui';
import '../../core/constants/safety_constants.dart';
import '../../domain/entities/vehicle.dart';

class VehicleInfo {
  final int trackId;
  final int classId;
  final double dx;
  final double dA;
  final double ttcSec;
  final double distM;
  final double speedKmh;
  final double speedMps;
  final double cx;
  final double speedPx;
  final double distancePx;
  final bool approaching;
  final bool retreating;
  final String direction;
  final String motionAxis;
  final Rect bbox;

  VehicleInfo({
    required this.trackId,
    required this.classId,
    this.dx = 0.0,
    this.dA = 0.0,
    this.ttcSec = double.infinity,
    this.distM = 0.0,
    this.speedKmh = 0.0,
    this.speedMps = 0.0,
    this.cx = 0.0,
    this.speedPx = 0.0,
    this.distancePx = 0.0,
    this.approaching = false,
    this.retreating = false,
    this.direction = 'unknown',
    this.motionAxis = 'unknown',
    required this.bbox,
  });

  String get category {
    if (classId == SafetyConstants.classBicycle) return 'light';
    if (SafetyConstants.heavyClasses.contains(classId)) return 'heavy';
    return 'ignored';
  }

  String get classLabel {
    return SafetyConstants.classLabels[classId] ?? 'unknown';
  }

  Vehicle toEntity() {
    return Vehicle(
      trackId: trackId,
      classId: classId,
      classLabel: classLabel,
      distM: distM,
      speedKmh: speedKmh,
      speedMps: speedMps,
      ttcSec: ttcSec,
      cx: cx,
      approaching: approaching,
      retreating: retreating,
      direction: direction,
      motionAxis: motionAxis,
      bbox: bbox,
    );
  }
}
