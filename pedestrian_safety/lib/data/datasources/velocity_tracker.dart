import 'dart:math';
import 'dart:ui';

class TrackObservation {
  final double cx;
  final double cy;
  final double area;
  final double distM;
  final double timestampSec;

  const TrackObservation({
    required this.cx,
    required this.cy,
    required this.area,
    required this.distM,
    required this.timestampSec,
  });
}

class TrackedVehicleEstimate {
  final int trackId;
  final int classId;
  final double distM;
  final double speedMps;
  final double speedKmh;
  final double ttcSec;
  final bool approaching;
  final bool retreating;
  final String direction;
  final String motionAxis;
  final Rect bbox;

  const TrackedVehicleEstimate({
    required this.trackId,
    required this.classId,
    required this.distM,
    required this.speedMps,
    required this.speedKmh,
    required this.ttcSec,
    required this.approaching,
    required this.retreating,
    required this.direction,
    required this.motionAxis,
    required this.bbox,
  });
}

class VelocityTracker {
  final int maxHistory;
  final Map<int, List<TrackObservation>> _trackHistory = {};
  final Map<int, int> _trackClasses = {};
  final Map<int, Rect> _lastBboxes = {};
  final Map<int, int> _framesSinceLastSeen = {};
  int _nextTrackId = 1;
  final DateTime _startTime = DateTime.now();

  static const double focalPx = 900.0;
  static const int minHistory = 4;
  static const double minApproachMps = 0.28;

  static const Map<int, double> averageFrontalWidths = {
    0: 0.6, // bicycle
    1: 2.5, // bus
    2: 1.8, // car
    3: 0.5, // dog
    4: 0.8, // motorcycle
    5: 0.5, // person
    6: 0.8, // scooty
    7: 1.4, // toto
  };

  VelocityTracker({this.maxHistory = 15});

  void reset() {
    _trackHistory.clear();
    _trackClasses.clear();
    _lastBboxes.clear();
    _framesSinceLastSeen.clear();
    _nextTrackId = 1;
  }

  /// Updates the tracker with the set of detections in the current frame.
  /// Returns estimates for all currently tracked vehicles.
  List<TrackedVehicleEstimate> update(
      List<(int classId, double confidence, Rect bbox)> detections) {
    final double timestampSec =
        DateTime.now().difference(_startTime).inMilliseconds / 1000.0;
    final Set<int> matchedTrackIds = {};

    for (final det in detections) {
      final int classId = det.$1;
      final Rect bbox = det.$3;
      final double width = bbox.width;
      final double cx = bbox.center.dx;
      final double cy = bbox.center.dy;
      final double area = bbox.width * bbox.height;

      // Calculate distance based on pinhole model
      final double realW = averageFrontalWidths[classId] ?? 1.8;
      final double distM = width > 0.0 ? (realW * focalPx) / width : 999.0;

      // Match to existing track
      int matchedId = -1;
      double bestIoU = 0.15; // minimum IoU threshold

      for (final activeId in _trackHistory.keys) {
        if (_trackClasses[activeId] != classId) continue;
        final Rect? prevBbox = _lastBboxes[activeId];
        if (prevBbox != null) {
          final double iou = _calculateIoU(bbox, prevBbox);
          if (iou > bestIoU) {
            bestIoU = iou;
            matchedId = activeId;
          }
        }
      }

      if (matchedId != -1) {
        matchedTrackIds.add(matchedId);
        _lastBboxes[matchedId] = bbox;
        _framesSinceLastSeen[matchedId] = 0;
        _trackHistory[matchedId]!.add(TrackObservation(
          cx: cx,
          cy: cy,
          area: area,
          distM: distM,
          timestampSec: timestampSec,
        ));
        if (_trackHistory[matchedId]!.length > maxHistory) {
          _trackHistory[matchedId]!.removeAt(0);
        }
      } else {
        // Create new track
        final int newId = _nextTrackId++;
        _trackClasses[newId] = classId;
        _lastBboxes[newId] = bbox;
        _framesSinceLastSeen[newId] = 0;
        _trackHistory[newId] = [
          TrackObservation(
            cx: cx,
            cy: cy,
            area: area,
            distM: distM,
            timestampSec: timestampSec,
          )
        ];
        matchedTrackIds.add(newId);
      }
    }

    // Clean up lost tracks
    final List<int> toRemove = [];
    for (final trackId in _trackHistory.keys) {
      if (!matchedTrackIds.contains(trackId)) {
        _framesSinceLastSeen[trackId] =
            (_framesSinceLastSeen[trackId] ?? 0) + 1;
        if (_framesSinceLastSeen[trackId]! > 8) {
          toRemove.add(trackId);
        }
      }
    }
    for (final id in toRemove) {
      _trackHistory.remove(id);
      _trackClasses.remove(id);
      _lastBboxes.remove(id);
      _framesSinceLastSeen.remove(id);
    }

    // Generate estimates for active tracks
    final List<TrackedVehicleEstimate> estimates = [];
    for (final trackId in _trackHistory.keys) {
      final List<TrackObservation> hist = _trackHistory[trackId]!;
      final Rect bbox = _lastBboxes[trackId]!;
      final int classId = _trackClasses[trackId]!;

      if (hist.isEmpty) continue;

      final double currentDist = hist.last.distM;
      double approachMps = 0.0;

      if (hist.length < minHistory) {
        if (hist.length >= 2) {
          final double dt = hist.last.timestampSec - hist.first.timestampSec;
          final double dd =
              hist.first.distM - hist.last.distM; // positive = closing
          if (dt > 1e-6) {
            approachMps = dd / dt;
          }
        }
      } else {
        // Linear regression over full history (distance vs time)
        final int n = hist.length;
        double sumT = 0.0;
        double sumD = 0.0;
        for (final obs in hist) {
          sumT += obs.timestampSec;
          sumD += obs.distM;
        }
        final double tMean = sumT / n;
        final double dMean = sumD / n;

        double num = 0.0;
        double den = 0.0;
        for (final obs in hist) {
          num += (obs.timestampSec - tMean) * (obs.distM - dMean);
          den += pow(obs.timestampSec - tMean, 2);
        }

        final double slope = den.abs() > 1e-9 ? num / den : 0.0;
        approachMps =
            -slope; // positive slope in distance-decreasing context means approaching
      }

      // Approach classification
      final bool approaching = approachMps > minApproachMps;

      // Retreating classification (check if distance is increasing)
      final bool retreating =
          hist.length >= 2 && (approachMps < -minApproachMps);

      double ttcSec = double.infinity;
      if (approaching && approachMps > 0) {
        ttcSec = currentDist / approachMps;
      }

      // Calculate lateral speed (dx_dt) for direction and motion axis
      double dxDt = 0.0;
      double dyDt = 0.0;
      if (hist.length >= 2) {
        final double dt = hist.last.timestampSec - hist.first.timestampSec;
        if (dt > 1e-6) {
          dxDt = (hist.last.cx - hist.first.cx) / dt;
          dyDt = (hist.last.cy - hist.first.cy) / dt;
        }
      }

      final String direction = dxDt > 15.0
          ? "left_to_right"
          : dxDt < -15.0
              ? "right_to_left"
              : "straight";

      final double absDx = dxDt.abs();
      final double absDy = dyDt.abs();
      final String motionAxis = (absDx > 20.0 && absDx > absDy * 1.5)
          ? "horizontal"
          : (approaching || retreating || absDy > 10.0)
              ? "vertical"
              : "ambiguous";

      estimates.add(TrackedVehicleEstimate(
        trackId: trackId,
        classId: classId,
        distM: currentDist,
        speedMps: approachMps.clamp(0.0, 100.0),
        speedKmh: (approachMps * 3.6).clamp(0.0, 360.0),
        ttcSec: ttcSec,
        approaching: approaching,
        retreating: retreating,
        direction: direction,
        motionAxis: motionAxis,
        bbox: bbox,
      ));
    }

    return estimates;
  }

  double _calculateIoU(Rect boxA, Rect boxB) {
    final double xA = max(boxA.left, boxB.left);
    final double yA = max(boxA.top, boxB.top);
    final double xB = min(boxA.right, boxB.right);
    final double yB = min(boxA.bottom, boxB.bottom);

    final double interArea = max(0.0, xB - xA) * max(0.0, yB - yA);
    final double boxAArea = boxA.width * boxA.height;
    final double boxBArea = boxB.width * boxB.height;

    if (boxAArea + boxBArea - interArea == 0) return 0.0;
    return interArea / (boxAArea + boxBArea - interArea);
  }
}
