import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import './safety_provider.dart';
import './settings_provider.dart';
import './audio_provider.dart';

class CameraProvider with ChangeNotifier {
  CameraController? _controller;
  bool _isInitializing = false;
  bool _hasPermission = false;
  String _errorMessage = '';

  CameraController? get controller => _controller;
  bool get isInitializing => _isInitializing;
  bool get hasPermission => _hasPermission;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  String get errorMessage => _errorMessage;

  Future<void> initialize() async {
    if (_isInitializing) return;
    _isInitializing = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        _hasPermission = false;
        _errorMessage = 'Camera permission denied.';
        _isInitializing = false;
        notifyListeners();
        return;
      }
      _hasPermission = true;

      final List<CameraDescription> cameras = await availableCameras();
      if (cameras.isEmpty) {
        _errorMessage = 'No camera available on device.';
        _isInitializing = false;
        notifyListeners();
        return;
      }

      // Select the rear camera
      final CameraDescription rearCamera = cameras.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        rearCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();
    } catch (e) {
      _errorMessage = 'Failed to initialize camera: $e';
    } finally {
      _isInitializing = false;
      notifyListeners();
    }
  }

  void startStreaming(SafetyProvider safetyProvider, SettingsProvider settingsProvider, AudioProvider audioProvider) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isStreamingImages) return;

    _controller!.startImageStream((CameraImage image) {
      // In standalone/mock mode, we pass the image metadata (or just tick the frame)
      // to process simulated vehicles.
      safetyProvider.processFrame(image, settingsProvider.config, audioProvider);
    });
  }

  void stopStreaming() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_controller!.value.isStreamingImages) return;
    _controller!.stopImageStream();
  }

  Future<void> disposeCamera() async {
    if (_controller != null) {
      stopStreaming();
      await _controller!.dispose();
      _controller = null;
      notifyListeners();
    }
  }
}
