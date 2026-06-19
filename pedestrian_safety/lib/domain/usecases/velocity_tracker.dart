import 'dart:math';
import 'dart:ui';

class TrackHistoryPoint {
  final double cx;
  final double cy;
  final double area;

  const TrackHistoryPoint({
    required this.cx,
    required this.cy,
    required this.area,
  });
}

class ApproachInfo {
  final bool approaching;
  final bool retreating;
  final double dA;
  final double dx;
  final double dy;
  final String motionAxis;
  final double ttcSec;
  final double cx;
  final String direction;

  const ApproachInfo({
    required this.approaching,
    required this.retreating,
    required this.dA,
    required this.dx,
    required this.dy,
    required this.motionAxis,
    required this.ttcSec,
    required this.cx,
    required this.direction,
  });
}

class VelocityTracker {
  final int maxHistory;
  final Map<int, List<TrackHistoryPoint>> trackHistory = {};
  final Map<int, int> firstSeen = {};
  final Map<int, Rect> lastBbox = {};
  final Map<int, int> trackClass = {};

  VelocityTracker({this.maxHistory = 15});

  void update(int trackId, Rect bbox, {int? classId, double egoDx = 0.0, double egoDy = 0.0}) {
    final double cx = (bbox.left + bbox.right) / 2.0 + egoDx;
    final double cy = (bbox.top + bbox.bottom) / 2.0 + egoDy;
    final double area = bbox.width * bbox.height;

    final history = trackHistory.putIfAbsent(trackId, () => []);
    history.add(TrackHistoryPoint(cx: cx, cy: cy, area: area));
    if (history.length > maxHistory) {
      history.removeAt(0);
    }

    lastBbox[trackId] = bbox;
    if (classId != null) {
      trackClass[trackId] = classId;
    }
    firstSeen.putIfAbsent(trackId, () => history.length);
  }

  (double, String) getSpeedDirection(int trackId) {
    final history = trackHistory[trackId];
    if (history == null || history.length < 2) {
      return (0.0, 'unknown');
    }

    final double dx = history.last.cx - history.first.cx;
    final double dy = history.last.cy - history.first.cy;
    final double speed = sqrt(dx * dx + dy * dy);

    String direction;
    if (dx.abs() > dy.abs()) {
      direction = dx > 0 ? 'right' : 'left';
    } else {
      direction = dy > 0 ? 'down' : 'up';
    }

    return (speed, direction);
  }

  int getClassId(int trackId) {
    return trackClass[trackId] ?? -1;
  }

  double getSpeedPixelsPerFrame(int trackId) {
    final history = trackHistory[trackId];
    if (history == null || history.length < 2) {
      return 0.0;
    }
    final double dx = history.last.cx - history.first.cx;
    final double dy = history.last.cy - history.first.cy;
    final double dist = sqrt(dx * dx + dy * dy);
    return dist / (history.length - 1);
  }

  ApproachInfo getApproachInfo(int trackId, double targetX, double targetY, {double fps = 30.0}) {
    final history = trackHistory[trackId];
    if (history == null || history.length < 3) {
      return ApproachInfo(
        approaching: false,
        retreating: false,
        dA: 0.0,
        dx: 0.0,
        dy: 0.0,
        motionAxis: 'unknown',
        ttcSec: double.infinity,
        cx: history?.last.cx ?? 0.0,
        direction: 'unknown',
      );
    }

    final int n = history.length;
    final List<double> t = List.generate(n, (i) => i / fps);

    final double sumT = t.reduce((a, b) => a + b);
    final double sumT2 = t.map((ti) => ti * ti).reduce((a, b) => a + b);
    final double denominator = n * sumT2 - sumT * sumT;

    double dAdt = 0.0;
    double dXdt = 0.0;
    double dYdt = 0.0;

    if (denominator.abs() > 1e-9) {
      final List<double> areas = history.map((h) => h.area).toList();
      final double sumA = areas.reduce((a, b) => a + b);
      final double sumTA = List.generate(n, (i) => t[i] * areas[i]).reduce((a, b) => a + b);
      dAdt = (n * sumTA - sumT * sumA) / denominator;

      final List<double> cxs = history.map((h) => h.cx).toList();
      final double sumCx = cxs.reduce((a, b) => a + b);
      final double sumTCx = List.generate(n, (i) => t[i] * cxs[i]).reduce((a, b) => a + b);
      dXdt = (n * sumTCx - sumT * sumCx) / denominator;

      final List<double> cys = history.map((h) => h.cy).toList();
      final double sumCy = cys.reduce((a, b) => a + b);
      final double sumTCy = List.generate(n, (i) => t[i] * cys[i]).reduce((a, b) => a + b);
      dYdt = (n * sumTCy - sumT * sumCy) / denominator;
    }

    final double cx = history.last.cx;
    final double currentArea = history.last.area;

    bool approaching = false;
    bool retreating = false;
    double ttcSec = double.infinity;

    if (dAdt > 0.03 * currentArea) {
      ttcSec = currentArea / dAdt;
      approaching = true;
      retreating = false;
    } else if (dAdt < -0.03 * currentArea) {
      ttcSec = double.infinity;
      approaching = false;
      retreating = true;
    }

    String direction = 'straight';
    if (dXdt > 15.0) {
      direction = 'left_to_right';
    } else if (dXdt < -15.0) {
      direction = 'right_to_left';
    }

    String motionAxis = 'ambiguous';
    final double absDx = dXdt.abs();
    final double absDy = dYdt.abs();

    if (absDx > 20.0 && absDx > absDy * 1.5) {
      motionAxis = 'horizontal';
    } else if (approaching || retreating || absDy > 10.0) {
      motionAxis = 'vertical';
    }

    return ApproachInfo(
      approaching: approaching,
      retreating: retreating,
      dA: dAdt,
      dx: dXdt,
      dy: dYdt,
      motionAxis: motionAxis,
      ttcSec: ttcSec,
      cx: cx,
      direction: direction,
    );
  }

  void purgeLostTracks(Set<int> activeTrackIds) {
    trackHistory.removeWhere((key, value) => !activeTrackIds.contains(key));
    firstSeen.removeWhere((key, value) => !activeTrackIds.contains(key));
    lastBbox.removeWhere((key, value) => !activeTrackIds.contains(key));
    trackClass.removeWhere((key, value) => !activeTrackIds.contains(key));
  }
}
