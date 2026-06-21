import 'dart:math';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/vehicle_info.dart';
import './velocity_tracker.dart';

// ─── Background isolate payload ─────────────────────────────────────────────
/// All data needed to preprocess a CameraImage on a background isolate.
class _PreprocessPayload {
  final int width;
  final int height;
  final int formatGroup; // ImageFormatGroup.index

  // Plane 0 (Y / BGRA)
  final Uint8List plane0Bytes;
  final int plane0RowStride;
  final int plane0PixelStride;

  // Plane 1 (U) — only used for YUV420
  final Uint8List? plane1Bytes;
  final int plane1RowStride;
  final int plane1PixelStride;

  // Plane 2 (V) — only used for YUV420
  final Uint8List? plane2Bytes;
  final int plane2RowStride;
  final int plane2PixelStride;

  const _PreprocessPayload({
    required this.width,
    required this.height,
    required this.formatGroup,
    required this.plane0Bytes,
    required this.plane0RowStride,
    required this.plane0PixelStride,
    this.plane1Bytes,
    required this.plane1RowStride,
    required this.plane1PixelStride,
    this.plane2Bytes,
    required this.plane2RowStride,
    required this.plane2PixelStride,
  });
}

/// Top-level function so it can be passed to [compute].
Float32List _preprocessOnIsolate(_PreprocessPayload p) {
  final Float32List buf = Float32List(640 * 640 * 3);
  final int w = p.width;
  final int h = p.height;
  final double scaleX = w / 640.0;
  final double scaleY = h / 640.0;

  // YUV420 branch
  if (p.formatGroup == ImageFormatGroup.yuv420.index) {
    final yBuf = p.plane0Bytes;
    final uBuf = p.plane1Bytes!;
    final vBuf = p.plane2Bytes!;
    final yRowStride = p.plane0RowStride;
    final uRowStride = p.plane1RowStride;
    final vRowStride = p.plane2RowStride;
    final uPixelStride = p.plane1PixelStride;
    final vPixelStride = p.plane2PixelStride;

    int idx = 0;
    for (int outY = 0; outY < 640; outY++) {
      final int srcY = (outY * scaleY).toInt().clamp(0, h - 1);
      for (int outX = 0; outX < 640; outX++) {
        final int srcX = (outX * scaleX).toInt().clamp(0, w - 1);

        final int yI = srcY * yRowStride + srcX;
        if (yI >= yBuf.length) { idx += 3; continue; }
        final int yV = yBuf[yI];

        final int uvX = srcX >> 1;
        final int uvY = srcY >> 1;
        final int uI = uvY * uRowStride + uvX * uPixelStride;
        final int vI = uvY * vRowStride + uvX * vPixelStride;
        if (uI >= uBuf.length || vI >= vBuf.length) { idx += 3; continue; }
        final int uV = uBuf[uI];
        final int vV = vBuf[vI];

        buf[idx++] = (yV + 1.402 * (vV - 128)).clamp(0, 255) / 255.0;
        buf[idx++] = (yV - 0.344136 * (uV - 128) - 0.714136 * (vV - 128)).clamp(0, 255) / 255.0;
        buf[idx++] = (yV + 1.772 * (uV - 128)).clamp(0, 255) / 255.0;
      }
    }
  } else {
    // BGRA8888 branch
    final bytes = p.plane0Bytes;
    final bytesPerRow = p.plane0RowStride;
    final bpp = p.plane0PixelStride.clamp(1, 4);

    int idx = 0;
    for (int outY = 0; outY < 640; outY++) {
      final int srcY = (outY * scaleY).toInt().clamp(0, h - 1);
      for (int outX = 0; outX < 640; outX++) {
        final int srcX = (outX * scaleX).toInt().clamp(0, w - 1);
        final int pi = srcY * bytesPerRow + srcX * bpp;
        if (pi + 2 >= bytes.length) { idx += 3; continue; }
        buf[idx++] = bytes[pi + 2] / 255.0; // R
        buf[idx++] = bytes[pi + 1] / 255.0; // G
        buf[idx++] = bytes[pi] / 255.0;     // B
      }
    }
  }
  return buf;
}

// ─── Service ─────────────────────────────────────────────────────────────────
class TfliteModelService {
  static final TfliteModelService _instance = TfliteModelService._internal();
  factory TfliteModelService() => _instance;
  TfliteModelService._internal();

  Interpreter? _interpreter;
  final VelocityTracker _tracker = VelocityTracker();
  bool _isLoading = false;

  // ── Frame-drop gate ────────────────────────────────────────────────────────
  bool _isProcessing = false;                    // true while inference is in flight
  DateTime _lastInferenceTime = DateTime(1970); // epoch sentinel
  static const Duration _minInferenceInterval =  // max ~3 inferences/sec
      Duration(milliseconds: 300);

  /// Which hardware backend is currently running inference.
  String _activeBackend = 'none';
  String get activeBackend => _activeBackend;

  Future<void> loadModel() async {
    if (_interpreter != null || _isLoading) return;
    _isLoading = true;
    try {
      // ── Tier 1: GPU Delegate ─────────────────────────────────────────────
      // Uses the phone's GPU (Adreno / Mali). Typically 3–8× faster than CPU.
      try {
        final gpuDelegate = GpuDelegateV2(
          options: GpuDelegateOptionsV2(
            isPrecisionLossAllowed: true, // FP16 — faster with tiny accuracy loss
          ),
        );
        final opts = InterpreterOptions()..addDelegate(gpuDelegate);
        _interpreter = await Interpreter.fromAsset(
          'assets/models/best.tflite',
          options: opts,
        );
        _activeBackend = 'GPU';
        debugPrint('TFLite: GPU delegate active.');
        return;
      } catch (_) {
        debugPrint('GPU delegate not available, trying NNAPI...');
      }

      // ── Tier 2: XNNPack Delegate ─────────────────────────────────────────
      // Uses highly-optimised SIMD kernels (ARM NEON on Android).
      // Typically 2–3× faster than plain multi-threaded CPU.
      try {
        final xnnDelegate = XNNPackDelegate(
          options: XNNPackDelegateOptions(numThreads: 4),
        );
        final opts = InterpreterOptions()..addDelegate(xnnDelegate);
        _interpreter = await Interpreter.fromAsset(
          'assets/models/best.tflite',
          options: opts,
        );
        _activeBackend = 'XNNPack';
        debugPrint('TFLite: XNNPack delegate active.');
        return;
      } catch (_) {
        debugPrint('XNNPack not available, falling back to CPU...');
      }

      // ── Tier 3: CPU fallback (4 threads) ─────────────────────────────────
      final opts = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        'assets/models/best.tflite',
        options: opts,
      );
      _activeBackend = 'CPU';
      debugPrint('TFLite: CPU (4 threads) active.');
    } catch (e) {
      debugPrint('Error loading TFLite model: $e');
    } finally {
      _isLoading = false;
    }
  }

  void reset() {
    _tracker.reset();
    _isProcessing = false;
    _lastInferenceTime = DateTime(1970);
  }

  Future<List<VehicleInfo>> detect(
      CameraImage image, double targetWidth, double targetHeight) async {
    // ── Frame-drop: skip if already processing or too soon ────────────────
    if (_isProcessing) return [];
    final now = DateTime.now();
    if (now.difference(_lastInferenceTime) < _minInferenceInterval) return [];

    _isProcessing = true;
    _lastInferenceTime = now;

    try {
      return await _runDetect(image, targetWidth, targetHeight);
    } finally {
      _isProcessing = false;
    }
  }

  Future<List<VehicleInfo>> _runDetect(
      CameraImage image, double targetWidth, double targetHeight) async {
    if (_interpreter == null) {
      await loadModel();
      if (_interpreter == null) return [];
    }

    // 1. Preprocess on a background isolate so the UI thread stays smooth
    final p = _PreprocessPayload(
      width: image.width,
      height: image.height,
      formatGroup: image.format.group.index,
      plane0Bytes: image.planes[0].bytes,
      plane0RowStride: image.planes[0].bytesPerRow,
      plane0PixelStride: image.planes[0].bytesPerPixel ?? 1,
      plane1Bytes: image.planes.length > 1 ? image.planes[1].bytes : null,
      plane1RowStride: image.planes.length > 1 ? image.planes[1].bytesPerRow : 0,
      plane1PixelStride: image.planes.length > 1 ? (image.planes[1].bytesPerPixel ?? 1) : 1,
      plane2Bytes: image.planes.length > 2 ? image.planes[2].bytes : null,
      plane2RowStride: image.planes.length > 2 ? image.planes[2].bytesPerRow : 0,
      plane2PixelStride: image.planes.length > 2 ? (image.planes[2].bytesPerPixel ?? 1) : 1,
    );

    final Float32List inputBuffer = await compute(_preprocessOnIsolate, p);

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

      // Confidence threshold — raised to 0.35 to prune weak candidates early
      if (maxScore > 0.35) {
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

  // _preprocessCameraImage removed — preprocessing is now handled by the
  // top-level _preprocessOnIsolate() function via compute().

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
