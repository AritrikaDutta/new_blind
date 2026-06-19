import 'dart:math';
import 'dart:ui';
import '../models/vehicle_info.dart';

enum MockScenario {
  clearRoad,
  approachingCar,
  passingTraffic,
  retreatingVehicle;

  String get displayName {
    switch (this) {
      case MockScenario.clearRoad:
        return 'Clear Road (Safe)';
      case MockScenario.approachingCar:
        return 'Approaching High-Speed Vehicle (Threat)';
      case MockScenario.passingTraffic:
        return 'Passing Cross Traffic (Caution)';
      case MockScenario.retreatingVehicle:
        return 'Retreating Vehicle (Safe)';
    }
  }
}

class MockDatasource {
  int _frameCount = 0;
  MockScenario _scenario = MockScenario.clearRoad;

  void setScenario(MockScenario scenario) {
    _scenario = scenario;
    _frameCount = 0;
  }

  void reset() {
    _frameCount = 0;
  }

  List<VehicleInfo> getNextFrameDetections(double width, double height, {double fps = 30.0}) {
    _frameCount++;
    final double elapsedSec = _frameCount / fps;

    switch (_scenario) {
      case MockScenario.clearRoad:
        return [];

      case MockScenario.approachingCar:
        // A single car (class_id = 2) starting at 35 meters and moving toward the user
        // Speed = 40 km/h (~11.1 m/s).
        // Distance = 35 - 11.1 * elapsedSec
        final double speedMps = 11.1;
        final double speedKmh = 40.0;
        final double dist = 35.0 - speedMps * elapsedSec;

        if (dist < 1.0) {
          // Reset scenario cycle
          _frameCount = 0;
          return [];
        }

        // Bounding box size: width = (real_width * focal_px) / distance
        // Let real_width = 1.8m, focal_px = 900.0
        final double bboxW = (1.8 * 900.0) / dist;
        final double bboxH = bboxW * 0.75;

        // Position it center-screen moving slightly vertically
        final double cx = width / 2.0;
        final double cy = height * 0.4 + (height * 0.5 * (1.0 - (dist / 35.0)));

        final Rect bbox = Rect.fromCenter(
          center: Offset(cx, cy),
          width: bboxW,
          height: bboxH,
        );

        final double ttc = dist / speedMps;

        return [
          VehicleInfo(
            trackId: 1,
            classId: 2, // car
            dx: 0.0,
            dA: bboxW * bboxH * 0.05, // growing area
            ttcSec: ttc,
            distM: dist,
            speedKmh: speedKmh,
            speedMps: speedMps,
            cx: cx,
            approaching: true,
            retreating: false,
            direction: 'straight',
            motionAxis: 'vertical',
            bbox: bbox,
          )
        ];

      case MockScenario.passingTraffic:
        // A car moving horizontally from left to right
        // Speed = 30 km/h (~8.3 m/s).
        // It starts at left screen edge and moves to right.
        // Let's say dist is static at 7.0 meters (inside near range)
        final double speedMps = 8.3;
        final double speedKmh = 30.0;
        final double dist = 7.0;

        // Bbox size remains relatively static
        final double bboxW = (1.8 * 900.0) / dist;
        final double bboxH = bboxW * 0.75;

        // Horizontal speed in pixels per frame: speedMps * scale_factor
        final double dxPxFrame = 5.0; // Simulated pixel rate
        final double cx = (elapsedSec * fps * dxPxFrame) % (width + 200.0) - 100.0;
        final double cy = height * 0.6;

        final Rect bbox = Rect.fromCenter(
          center: Offset(cx, cy),
          width: bboxW,
          height: bboxH,
        );

        final String direction = 'left_to_right';

        return [
          VehicleInfo(
            trackId: 2,
            classId: 2, // car
            dx: dxPxFrame * fps,
            dA: 0.0,
            ttcSec: double.infinity, // Horizontal traffic does not directly collide
            distM: dist,
            speedKmh: speedKmh,
            speedMps: speedMps,
            cx: cx,
            approaching: false,
            retreating: false,
            direction: direction,
            motionAxis: 'horizontal',
            bbox: bbox,
          )
        ];

      case MockScenario.retreatingVehicle:
        // A motorcycle (class_id = 4) moving away from the user
        // Speed = 25 km/h (~6.9 m/s).
        // Distance starts at 5 meters and increases.
        final double speedMps = 6.9;
        final double speedKmh = 25.0;
        final double dist = 5.0 + speedMps * elapsedSec;

        if (dist > 40.0) {
          _frameCount = 0;
          return [];
        }

        final double bboxW = (0.8 * 900.0) / dist;
        final double bboxH = bboxW * 1.2;

        final double cx = width * 0.45;
        final double cy = height * 0.7 - (height * 0.3 * ((dist - 5.0) / 35.0));

        final Rect bbox = Rect.fromCenter(
          center: Offset(cx, cy),
          width: bboxW,
          height: bboxH,
        );

        return [
          VehicleInfo(
            trackId: 3,
            classId: 4, // motorcycle
            dx: 0.0,
            dA: -bboxW * bboxH * 0.05, // shrinking area
            ttcSec: double.infinity,
            distM: dist,
            speedKmh: speedKmh,
            speedMps: speedMps,
            cx: cx,
            approaching: false,
            retreating: true,
            direction: 'straight',
            motionAxis: 'vertical',
            bbox: bbox,
          )
        ];
    }
  }
}
