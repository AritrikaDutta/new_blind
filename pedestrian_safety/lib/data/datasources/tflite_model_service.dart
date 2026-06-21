import 'dart:math';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/vehicle_info.dart';
import './velocity_tracker.dart';

class TfliteModelService {
  static final TfliteModelService _instance = TfliteModelService._internal();
  factory TfliteModelService() => _instance;
  TfliteModelService._internal();

  Interpreter? _interpreter;
  final VelocityTracker _tracker = VelocityTracker();
  bool _isLoading = false;

  Future<void> loadModel() async {
    if (_interpreter != null || _isLoading) return;
    _isLoading = true;
    try {
      // Loading model from assets/models/best.tflite
      _interpreter = await Interpreter.fromAsset('assets/models/best.tflite');
      debugPrint('TFLite model loaded successfully.');
    } catch (e) {
      debugPrint('Error loading TFLite model: $e');
    } finally {
      _isLoading = false;
    }
  }

  void reset() {
    _tracker.reset();
  }

  Future<List<VehicleInfo>> detect(
      CameraImage image, double targetWidth, double targetHeight) async {
    if (_interpreter == null) {
      await loadModel();
      if (_interpreter == null) return [];
    }

    // 1. Preprocess CameraImage to flat Float32List normalized to [0, 1]
    final Float32List inputBuffer = _preprocessCameraImage(image);

    // 2. Reshape input to [1, 640, 640, 3]
    final List<dynamic> input = inputBuffer.reshape([1, 640, 640, 3]);

    // 3. Allocate output tensor: [1, 12, 8400]
    final List<dynamic> output = List.generate(
      1,
      (_) => List.generate(
        12,
        (_) => List.filled(8400, 0.0),
      ),
    );

    // 4. Run inference
    try {
      _interpreter!.run(input, output);
    } catch (e) {
      debugPrint('Error running TFLite inference: $e');
      return [];
    }

    // 5. Decode outputs: [1, 12, 8400]
    // Out shape is:
    // row 0-3: cx, cy, w, h (in 640x640 coordinate space)
    // row 4-11: scores for 8 classes (bicycle, bus, car, dog, motorcycle, person, scooty, toto)
    final List<(int classId, double confidence, Rect bbox)> candidates = [];

    // Grab outputs from nested list
    final List<List<double>> modelOutput =
        (output[0] as List).map((e) => (e as List).cast<double>()).toList();

    for (int i = 0; i < 8400; i++) {
      // Find class with max score
      int maxClassId = -1;
      double maxScore = -1.0;
      for (int c = 0; c < 8; c++) {
        final double score = modelOutput[4 + c][i];
        if (score > maxScore) {
          maxScore = score;
          maxClassId = c;
        }
      }

      // Confidence threshold
      if (maxScore > 0.25) {
        final double cx = modelOutput[0][i];
        final double cy = modelOutput[1][i];
        final double w = modelOutput[2][i];
        final double h = modelOutput[3][i];

        // Convert center coordinates to bounding box LTWH
        final double left = cx - w / 2.0;
        final double top = cy - h / 2.0;

        candidates.add((
          maxClassId,
          maxScore,
          Rect.fromLTWH(left, top, w, h),
        ));
      }
    }

    // 6. Run Non-Maximum Suppression (NMS)
    final List<(int classId, double confidence, Rect bbox)> nmsDetections =
        _runNMS(candidates, 0.45);

    // 7. Rescale NMS bounding boxes to target dimensions (targetWidth x targetHeight)
    // The original model coordinates are in 640x640 space.
    final List<(int classId, double confidence, Rect bbox)> rescaledDetections =
        nmsDetections.map((det) {
      final int classId = det.$1;
      final double confidence = det.$2;
      final Rect bbox = det.$3;

      // Rescale from 640x640 to targetWidth x targetHeight
      final double scaleX = targetWidth / 640.0;
      final double scaleY = targetHeight / 640.0;

      final Rect scaledBbox = Rect.fromLTRB(
        bbox.left * scaleX,
        bbox.top * scaleY,
        bbox.right * scaleX,
        bbox.bottom * scaleY,
      );

      return (classId, confidence, scaledBbox);
    }).toList();

    // 8. Update Velocity Tracker and get tracking estimates
    final List<TrackedVehicleEstimate> estimates =
        _tracker.update(rescaledDetections);

    // 9. Map estimates to VehicleInfo entities
    final List<VehicleInfo> vehicleInfos = estimates.map((est) {
      return VehicleInfo(
        trackId: est.trackId,
        classId: est.classId,
        dx: est.approaching
            ? 1.0
            : (est.retreating ? -1.0 : 0.0), // simplified frame delta
        dA: est.approaching ? 1.0 : (est.retreating ? -1.0 : 0.0),
        ttcSec: est.ttcSec,
        distM: est.distM,
        speedKmh: est.speedKmh,
        speedMps: est.speedMps,
        cx: est.bbox.center.dx,
        approaching: est.approaching,
        retreating: est.retreating,
        direction: est.direction,
        motionAxis: est.motionAxis,
        bbox: est.bbox,
      );
    }).toList();

    return vehicleInfos;
  }

  Float32List _preprocessCameraImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final Float32List inputBuffer = Float32List(640 * 640 * 3);

    // Check format group
    if (image.format.group == ImageFormatGroup.yuv420) {
      final yPlane = image.planes[0];
      final uPlane = image.planes[1];
      final vPlane = image.planes[2];

      final yBuffer = yPlane.bytes;
      final uBuffer = uPlane.bytes;
      final vBuffer = vPlane.bytes;

      final int yRowStride = yPlane.bytesPerRow;
      final int uRowStride = uPlane.bytesPerRow;
      final int vRowStride = vPlane.bytesPerRow;

      final int? uPixelStride = uPlane.bytesPerPixel;
      final int? vPixelStride = vPlane.bytesPerPixel;

      final double scaleX = width / 640.0;
      final double scaleY = height / 640.0;

      int bufferIdx = 0;
      for (int outY = 0; outY < 640; outY++) {
        final int srcY = (outY * scaleY).toInt().clamp(0, height - 1);
        for (int outX = 0; outX < 640; outX++) {
          final int srcX = (outX * scaleX).toInt().clamp(0, width - 1);

          final int yIndex = srcY * yRowStride + srcX;
          if (yIndex >= yBuffer.length) continue;
          final int yValue = yBuffer[yIndex];

          final int uvSrcX = srcX >> 1;
          final int uvSrcY = srcY >> 1;

          final int uIndex = uvSrcY * uRowStride + uvSrcX * (uPixelStride ?? 1);
          final int vIndex = uvSrcY * vRowStride + uvSrcX * (vPixelStride ?? 1);

          if (uIndex >= uBuffer.length || vIndex >= vBuffer.length) continue;
          final int uValue = uBuffer[uIndex];
          final int vValue = vBuffer[vIndex];

          // YUV to RGB conversion (SDTV/BT.601)
          final double r = (yValue + 1.402 * (vValue - 128)).clamp(0.0, 255.0);
          final double g =
              (yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128))
                  .clamp(0.0, 255.0);
          final double b = (yValue + 1.772 * (uValue - 128)).clamp(0.0, 255.0);

          inputBuffer[bufferIdx++] = r / 255.0;
          inputBuffer[bufferIdx++] = g / 255.0;
          inputBuffer[bufferIdx++] = b / 255.0;
        }
      }
    } else {
      // Default / BGRA8888
      final plane = image.planes[0];
      final bytes = plane.bytes;
      final int bytesPerRow = plane.bytesPerRow;
      final int? bytesPerPixel = plane.bytesPerPixel;
      final int bpp = bytesPerPixel ?? 4;

      final double scaleX = width / 640.0;
      final double scaleY = height / 640.0;

      int bufferIdx = 0;
      for (int outY = 0; outY < 640; outY++) {
        final int srcY = (outY * scaleY).toInt().clamp(0, height - 1);
        for (int outX = 0; outX < 640; outX++) {
          final int srcX = (outX * scaleX).toInt().clamp(0, width - 1);

          final int pixelIndex = srcY * bytesPerRow + srcX * bpp;
          if (pixelIndex + 2 >= bytes.length) continue;

          final double b = bytes[pixelIndex].toDouble();
          final double g = bytes[pixelIndex + 1].toDouble();
          final double r = bytes[pixelIndex + 2].toDouble();

          inputBuffer[bufferIdx++] = r / 255.0;
          inputBuffer[bufferIdx++] = g / 255.0;
          inputBuffer[bufferIdx++] = b / 255.0;
        }
      }
    }
    return inputBuffer;
  }

  List<(int classId, double confidence, Rect bbox)> _runNMS(
    List<(int classId, double confidence, Rect bbox)> candidates,
    double iouThreshold,
  ) {
    candidates.sort((a, b) => b.$2.compareTo(a.$2));

    final List<(int classId, double confidence, Rect bbox)> selected = [];
    final List<bool> suppressed = List.filled(candidates.length, false);

    for (int i = 0; i < candidates.length; i++) {
      if (suppressed[i]) continue;

      final current = candidates[i];
      selected.add(current);

      for (int j = i + 1; j < candidates.length; j++) {
        if (suppressed[j]) continue;

        if (current.$1 == candidates[j].$1) {
          final double iou = _calculateIoU(current.$3, candidates[j].$3);
          if (iou > iouThreshold) {
            suppressed[j] = true;
          }
        }
      }
    }

    return selected;
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
