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

  Future<void> processFrame(dynamic frame, CrossingConfig config, AudioProvider audioProvider) async {
    await _repository.processFrame(frame, config);
    
    final stateOut = _repository.getLatestState();
    if (stateOut != null) {
      // Trigger voice alert (with cooldown de-duplication handled by AudioProvider)
      await audioProvider.speakStateAlert(
        stateOut.internalState.nameString,
        stateOut.fullSpoken,
      );

      // Trigger tactile haptics
      await _hapticService.triggerForState(stateOut.internalState);
    }
    
    notifyListeners();
  }

  Future<void> reset() async {
    await _repository.reset();
    notifyListeners();
  }

  Future<SafetyReport> getSessionReport() async {
    return await _repository.getSessionReport();
  }
}
