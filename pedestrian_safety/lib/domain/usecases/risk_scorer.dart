import 'dart:math';
import 'dart:ui';
import '../../core/constants/safety_constants.dart';
import '../../data/models/crossing_config.dart';
import '../../data/models/vehicle_info.dart';
import '../entities/safety_state.dart';
import '../entities/zone.dart';

class RiskScorer {
  static const double _eps = 1e-6;

  static double _crossingOverlap(Rect bbox, Zone? crossingZone) {
    if (crossingZone == null) return 0.0;
    final Rect crossingRect = crossingZone.rect;
    final double intersectLeft = max(bbox.left, crossingRect.left);
    final double intersectTop = max(bbox.top, crossingRect.top);
    final double intersectRight = min(bbox.right, crossingRect.right);
    final double intersectBottom = min(bbox.bottom, crossingRect.bottom);

    if (intersectLeft >= intersectRight || intersectTop >= intersectBottom) {
      return 0.0;
    }

    final double intersectArea = (intersectRight - intersectLeft) * (intersectBottom - intersectTop);
    final double bboxArea = bbox.width * bbox.height;

    if (bboxArea <= 0) return 0.0;
    return min(1.0, intersectArea / bboxArea);
  }

  static String _currentZoneName(Rect bbox, Map<String, Zone>? allZones) {
    if (allZones == null) return 'none';
    final double cx = (bbox.left + bbox.right) / 2.0;
    final double cy = (bbox.top + bbox.bottom) / 2.0;

    for (final entry in allZones.entries) {
      if (entry.value.rect.contains(Offset(cx, cy))) {
        return entry.key;
      }
    }
    return 'none';
  }

  static double _geometricRisk(VehicleInfo vi, Zone? crossingZone, Map<String, Zone>? allZones) {
    final String axis = vi.motionAxis;
    final String zone = _currentZoneName(vi.bbox, allZones);

    // Case 1: HORIZONTAL motion
    if (axis == 'horizontal') {
      final double dist = vi.distM > 0 ? vi.distM : SafetyConstants.farM;
      final double overlap = _crossingOverlap(vi.bbox, crossingZone);

      if (dist >= SafetyConstants.farM) {
        return 0.05;
      }

      if (dist <= SafetyConstants.nearM) {
        final double closeness = max(0.0, min(1.0, 1.0 - (dist / SafetyConstants.nearM)));
        double base = 0.45 + 0.43 * closeness; // [0.45 -> 0.88]
        if (overlap > 0.15) {
          base = max(base, 0.60);
        }
        return base;
      }

      // Intermediate band
      final double frac = (dist - SafetyConstants.nearM) / (SafetyConstants.farM - SafetyConstants.nearM);
      if (overlap > 0.15) {
        return 0.60 - 0.15 * frac;
      } else {
        return 0.45 - 0.40 * frac;
      }
    }

    // Case 2: VERTICAL motion
    if (axis == 'vertical') {
      final bool retreating = vi.retreating;

      if (retreating || (!vi.approaching && vi.dA <= 0)) {
        return 0.00;
      }

      if (vi.approaching) {
        if (zone == 'CROSSING') {
          return 0.92;
        } else if (zone == 'LEFT' || zone == 'RIGHT') {
          return 0.50;
        } else {
          return 0.55;
        }
      }

      return 0.25;
    }

    // Ambiguous / unknown
    final double overlap = _crossingOverlap(vi.bbox, crossingZone);
    return 0.30 + 0.35 * overlap;
  }

  static List<VehicleInfo> rankThreats(List<VehicleInfo> vehicleInfos, Zone? crossingZone, {int k = 3}) {
    double threatScore(VehicleInfo vi) {
      if (vi.classId == SafetyConstants.classDog) {
        return 0.0;
      }
      if (vi.retreating) {
        return 0.0;
      }
      if (!vi.approaching && vi.dA <= 0) {
        final double overlap = _crossingOverlap(vi.bbox, crossingZone);
        return 0.05 * overlap;
      }
      final double ttcF = 1.0 / (vi.ttcSec + _eps);
      final double speedF = vi.speedMps;
      final double overlap = _crossingOverlap(vi.bbox, crossingZone);
      return ttcF * speedF * (0.5 + overlap);
    }

    final List<VehicleInfo> ranked = List.from(vehicleInfos);
    ranked.sort((a, b) => threatScore(b).compareTo(threatScore(a)));
    return ranked.take(k).toList();
  }

  static (double riskScore, double confidence, String secondaryCue, SafetyState proposedState) computeRisk(
    List<VehicleInfo> topK,
    Zone? crossingZone,
    Map<String, Zone>? allZones,
    double frameWidth,
    CrossingConfig config, {
    double crossingProgress = 0.0,
  }) {
    if (topK.isEmpty) {
      return (0.0, 1.0, '', SafetyState.safe);
    }

    final double progress = max(0.0, min(1.0, crossingProgress));
    final double remainingDist = config.roadWidthM * (1.0 - progress);
    final double remainingTime = remainingDist / max(0.1, config.walkSpeedMps);
    final double safeTtc = remainingTime + config.safetyMarginSec;

    double worstRisk = 0.0;
    VehicleInfo worstVi = topK.first;

    for (final vi in topK) {
      double ttcRisk = 0.0;
      if (vi.ttcSec == double.infinity) {
        ttcRisk = 0.0;
      } else if (vi.ttcSec <= 0.0) {
        ttcRisk = 1.0;
      } else {
        ttcRisk = max(0.0, min(1.0, (safeTtc - vi.ttcSec) / max(safeTtc, _eps)));
      }

      final double speedRisk = min(1.0, vi.speedKmh / SafetyConstants.maxSpeedKmh);
      final double geomRisk = _geometricRisk(vi, crossingZone, allZones);

      final double vRisk = SafetyConstants.wTtc * ttcRisk +
          SafetyConstants.wSpeed * speedRisk +
          SafetyConstants.wGeom * geomRisk;

      if (vRisk > worstRisk) {
        worstRisk = vRisk;
        worstVi = vi;
      }
    }

    final double riskScore = min(1.0, worstRisk);

    double confidence = 0.40;
    if (riskScore == 0.0) {
      confidence = 1.0;
    } else {
      final bool dirKnown = topK.every((v) => v.direction != 'unknown');
      final bool axisKnown = topK.every((v) => v.motionAxis != 'unknown');
      final bool ttcKnown = topK.every((v) => v.ttcSec != double.infinity || v.retreating);

      if (dirKnown && axisKnown && ttcKnown) {
        confidence = 0.90;
      } else if (dirKnown && axisKnown) {
        confidence = 0.70;
      } else if (dirKnown) {
        confidence = 0.55;
      }
    }

    String secondary = '';
    final String axis = worstVi.motionAxis;
    final bool retreating = worstVi.retreating;

    if (retreating) {
      secondary = 'Vehicle moving away.';
    } else if (axis == 'horizontal') {
      if (worstVi.direction == 'right_to_left') {
        secondary = 'Raise your left hand.';
      } else if (worstVi.direction == 'left_to_right') {
        secondary = 'Raise your right hand.';
      }
    } else if (axis == 'vertical') {
      if (worstVi.approaching) {
        final String side = worstVi.cx < (frameWidth / 2.0) ? 'left' : 'right';
        secondary = 'Vehicle approaching from your $side.';
      } else {
        secondary = 'Vehicle moving away.';
      }
    }

    SafetyState state;
    if (riskScore >= SafetyConstants.threshStop) {
      state = SafetyState.stop;
    } else if (riskScore >= SafetyConstants.threshWait) {
      state = SafetyState.wait;
    } else if (riskScore >= SafetyConstants.threshWalkFast) {
      state = SafetyState.walkFast;
    } else {
      state = SafetyState.safe;
    }

    return (riskScore, confidence, secondary, state);
  }
}
