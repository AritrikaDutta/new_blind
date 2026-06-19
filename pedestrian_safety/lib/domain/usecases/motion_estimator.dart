import 'dart:math';

class MotionObservation {
  final double distanceM;
  final double timestampSec;

  const MotionObservation({
    required this.distanceM,
    required this.timestampSec,
  });
}

class PhysicsEstimate {
  final double distM;
  final double speedMps;
  final double speedKmh;
  final double ttcSec;
  final bool approaching;

  const PhysicsEstimate({
    required this.distM,
    required this.speedMps,
    required this.speedKmh,
    required this.ttcSec,
    required this.approaching,
  });
}

class MotionEstimator {
  final double focalPx;
  final int maxHistory;
  final Map<int, List<MotionObservation>> hist = {};

  MotionEstimator({
    this.focalPx = 900.0,
    this.maxHistory = 25,
  });

  static const Map<int, double> realWidthsM = {
    0: 0.60, // bicycle
    1: 2.50, // bus
    2: 1.80, // car
    3: 0.40, // dog
    4: 0.80, // motorcycle
    5: 0.50, // person
    6: 0.80, // scooty
    7: 1.40, // toto
  };

  static const int minHist = 4;
  static const double minApproachMps = 0.28;

  double estimateDistance(double pixelWidth, int classId, {double aiDepthScale = 1.0}) {
    final double realW = realWidthsM[classId] ?? 1.80;
    if (pixelWidth < 1.0) {
      return 999.0;
    }
    final double dist = (realW * focalPx) / pixelWidth * aiDepthScale;
    return double.parse(dist.toStringAsFixed(2));
  }

  void update(int trackId, double pixelWidth, int classId, double timestampSec, {double aiDepthScale = 1.0}) {
    final double distM = estimateDistance(pixelWidth, classId, aiDepthScale: aiDepthScale);
    final observations = hist.putIfAbsent(trackId, () => []);
    observations.add(MotionObservation(distanceM: distM, timestampSec: timestampSec));
    if (observations.length > maxHistory) {
      observations.removeAt(0);
    }
  }

  PhysicsEstimate getEstimate(int trackId) {
    final observations = hist[trackId];
    if (observations == null || observations.isEmpty) {
      return _nullEstimate(0.0);
    }
    if (observations.length < 2) {
      return _nullEstimate(observations.last.distanceM);
    }

    final double currentDist = observations.last.distanceM;
    double approachMps = 0.0;

    if (observations.length < minHist) {
      final double dt = observations.last.timestampSec - observations.first.timestampSec;
      final double dd = observations.first.distanceM - observations.last.distanceM;
      if (dt < 1e-6) {
        return _nullEstimate(currentDist);
      }
      approachMps = dd / dt;
    } else {
      final int n = observations.length;
      final List<double> ts = observations.map((o) => o.timestampSec).toList();
      final List<double> ds = observations.map((o) => o.distanceM).toList();

      final double tMean = ts.reduce((a, b) => a + b) / n;
      final double dMean = ds.reduce((a, b) => a + b) / n;

      double num = 0.0;
      double den = 0.0;
      for (int i = 0; i < n; i++) {
        num += (ts[i] - tMean) * (ds[i] - dMean);
        den += pow(ts[i] - tMean, 2);
      }

      final double slope = den.abs() > 1e-9 ? num / den : 0.0;
      approachMps = -slope; // positive means closing
    }

    bool approaching = false;
    double ttcSec = double.infinity;

    if (approachMps > minApproachMps) {
      approaching = true;
      ttcSec = currentDist / approachMps;
      ttcSec = min(ttcSec, 999.0);
    }

    return PhysicsEstimate(
      distM: currentDist,
      speedMps: double.parse(max(approachMps, 0.0).toStringAsFixed(2)),
      speedKmh: double.parse(max(approachMps * 3.6, 0.0).toStringAsFixed(1)),
      ttcSec: approaching ? double.parse(ttcSec.toStringAsFixed(2)) : double.infinity,
      approaching: approaching,
    );
  }

  void removeTrack(int trackId) {
    hist.remove(trackId);
  }

  PhysicsEstimate _nullEstimate(double defaultDist) {
    final double dist = defaultDist > 0 ? defaultDist : 999.0;
    return PhysicsEstimate(
      distM: dist,
      speedMps: 0.0,
      speedKmh: 0.0,
      ttcSec: double.infinity,
      approaching: false,
    );
  }
}
