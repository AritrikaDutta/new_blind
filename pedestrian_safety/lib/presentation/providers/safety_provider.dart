import 'package:flutter/material.dart';
import '../../data/models/crossing_config.dart';
import '../../data/models/safety_report.dart';
import '../../data/models/state_output.dart';
import '../../data/datasources/mock_datasource.dart';
import '../../data/repositories/safety_repository_impl.dart';
import '../../domain/entities/vehicle.dart';
import '../../services/haptic_service.dart';
import './audio_provider.dart';

class SafetyProvider with ChangeNotifier {
  final SafetyRepositoryImpl _repository = SafetyRepositoryImpl();
  final HapticService _hapticService = HapticService();

  // Guard: skip incoming frames while the previous inference is still running
  bool _isProcessing = false;

  // Lifecycle: flipped to true on stop() to discard any in-flight callbacks
  bool _stopped = false;

  List<Vehicle> get activeVehicles => _repository.getActiveVehicles();
  List<Vehicle> get topKThreats => _repository.getTopKThreats();
  StateOutput? get latestState => _repository.getLatestState();
  double get fps => _repository.getFps();
  int get tier => _repository.getTier();

  MockScenario get currentScenario => _repository.currentScenario;

  Future<void> changeScenario(MockScenario scenario) async {
    _repository.setScenario(scenario);
    notifyListeners();
  }

  /// Hard-stop: cancels all in-flight work immediately.
  /// Call this BEFORE navigating away from CameraScreen.
  Future<void> stop(AudioProvider audioProvider) async {
    _stopped = true;
    _isProcessing = false;
    await audioProvider.stop();
  }

  Future<void> processFrame(
      dynamic frame, CrossingConfig config, AudioProvider audioProvider) async {
    // Drop this frame if stopped or still processing the previous one
    if (_stopped || _isProcessing) return;
    _isProcessing = true;
    try {
      await _repository.processFrame(frame, config);
      if (_stopped) return; // session ended while inference was running

      final stateOut = _repository.getLatestState();
      if (stateOut != null) {
        // Fire TTS/haptics as fire-and-forget so they never block the pipeline
        audioProvider.speakStateAlert(
          stateOut.internalState.nameString,
          stateOut.fullSpoken,
        );
        _hapticService.triggerForState(stateOut.internalState);
      }

      if (!_stopped) notifyListeners();
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> reset() async {
    _stopped = false;
    await _repository.reset();
    notifyListeners();
  }

  Future<SafetyReport> getSessionReport() async {
    return await _repository.getSessionReport();
  }
}
