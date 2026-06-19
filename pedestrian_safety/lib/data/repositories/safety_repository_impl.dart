import 'dart:math';
import 'package:flutter/foundation.dart';
import '../../core/constants/safety_constants.dart';
import '../../domain/entities/safety_state.dart';
import '../../domain/entities/vehicle.dart';
import '../../domain/entities/zone.dart';
import '../../domain/repositories/safety_repository.dart';
import '../../domain/usecases/state_machine.dart';
import '../../domain/usecases/risk_scorer.dart';
import '../datasources/mock_datasource.dart';
import '../models/crossing_config.dart';
import '../models/safety_report.dart';
import '../models/state_output.dart';
import '../models/vehicle_info.dart';

class SafetyRepositoryImpl implements SafetyRepository {
  final MockDatasource _mockDatasource = MockDatasource();
  final SafetyStateMachine _stateMachine = SafetyStateMachine();

  // State caches
  List<Vehicle> _activeVehicles = [];
  List<Vehicle> _topKThreats = [];
  StateOutput? _latestState;
  
  // Metrics
  double _fps = 30.0;
  int _tier = 1;
  int _frameCount = 0;
  DateTime? _lastFrameTime;
  final List<double> _fpsHistory = [];

  // Report metrics
  int _falseSafeCount = 0;
  int _stateSwitches = 0;
  SafetyState? _lastCommittedState;
  final List<double> _riskHistory = [];

  MockScenario _scenario = MockScenario.clearRoad;

  void setScenario(MockScenario scenario) {
    _scenario = scenario;
    _mockDatasource.setScenario(scenario);
    reset();
  }

  MockScenario get currentScenario => _scenario;

  @override
  Future<void> processFrame(dynamic frame, CrossingConfig config) async {
    _frameCount++;

    // Calculate FPS and performance tier
    final now = DateTime.now();
    if (_lastFrameTime != null) {
      final double instFps = 1000.0 / now.difference(_lastFrameTime!).inMilliseconds.clamp(1, 100000);
      _fpsHistory.add(instFps);
      if (_fpsHistory.length > 30) {
        _fpsHistory.removeAt(0);
      }
      _fps = _fpsHistory.reduce((a, b) => a + b) / _fpsHistory.length;
    }
    _lastFrameTime = now;

    if (_fps >= SafetyConstants.tier1Fps) {
      _tier = 1;
    } else if (_fps >= SafetyConstants.tier3Fps) {
      _tier = 2;
    } else {
      _tier = 3;
    }

    // Get frame dimensions (mock default: 640x480)
    final double width = 640.0;
    final double height = 480.0;

    // Define zones
    final Map<String, Zone> zones = Zone.defineZones(width, height);
    final Zone? crossingZone = zones['CROSSING'];

    // 1. Get raw/mock detections
    final List<VehicleInfo> vehicleInfos = _mockDatasource.getNextFrameDetections(width, height, fps: _fps);

    // 2. Rank threats
    final List<VehicleInfo> topKInfos = RiskScorer.rankThreats(vehicleInfos, crossingZone, k: config.threatRankK);

    // 3. Compute risk and propose state
    final (double riskScore, double confidence, String secondaryCue, SafetyState proposedState) = 
      RiskScorer.computeRisk(
        topKInfos,
        crossingZone,
        zones,
        width,
        config,
        crossingProgress: 0.0, // Simplification or ego displacement integrated
      );

    _riskHistory.add(riskScore);
    if (_riskHistory.length > 500) {
      _riskHistory.removeAt(0);
    }

    // ── Immediate SAFE override if no vehicles are present or all retreating
    StateOutput stateOut;
    if (vehicleInfos.isEmpty || topKInfos.every((v) => v.retreating)) {
      _stateMachine.reset();
      stateOut = StateOutput(
        internalState: SafetyState.safe,
        spokenText: 'Cross now',
        audioStem: 'walk_normal',
        confidence: 1.0,
        riskScore: 0.0,
        secondaryCue: '',
      );
    } else {
      // 4. Update state machine
      stateOut = _stateMachine.update(
        proposedState: proposedState,
        confidence: confidence,
        riskScore: riskScore,
        secondaryCue: secondaryCue,
      );
    }

    // Track state switches
    if (_lastCommittedState != null && _lastCommittedState != stateOut.internalState) {
      _stateSwitches++;
    }
    _lastCommittedState = stateOut.internalState;

    // Track False-Safe events
    // (Cross now warning emitted, but a vehicle has TTC < safe_ttc)
    if (stateOut.internalState == SafetyState.safe && vehicleInfos.isNotEmpty) {
      final double safeTtc = (config.roadWidthM / max(0.1, config.walkSpeedMps)) + config.safetyMarginSec;
      final bool hasThreat = vehicleInfos.any((v) => v.approaching && v.ttcSec < safeTtc);
      if (hasThreat) {
        _falseSafeCount++;
      }
    }

    // Map model snapshots to entities
    _activeVehicles = vehicleInfos.map((v) => v.toEntity()).toList();
    _topKThreats = topKInfos.map((v) => v.toEntity()).toList();
    _latestState = stateOut;
  }

  @override
  Future<void> reset() async {
    _frameCount = 0;
    _lastFrameTime = null;
    _fpsHistory.clear();
    _fps = 30.0;
    _tier = 1;
    _falseSafeCount = 0;
    _stateSwitches = 0;
    _lastCommittedState = null;
    _riskHistory.clear();
    _activeVehicles.clear();
    _topKThreats.clear();
    _latestState = null;
    _stateMachine.reset();
    _mockDatasource.reset();
  }

  @override
  Future<SafetyReport> getSessionReport() async {
    final double totalFrames = max(1.0, _riskHistory.length.toDouble());
    final double falseSafeRate = _falseSafeCount / totalFrames;

    return SafetyReport(
      falseSafeCount: _falseSafeCount,
      falseSafeRate: falseSafeRate,
      stateSwitches: _stateSwitches,
      logPath: 'session_log.json',
      riskHistory: List.from(_riskHistory),
    );
  }

  @override
  List<Vehicle> getActiveVehicles() => _activeVehicles;

  @override
  List<Vehicle> getTopKThreats() => _topKThreats;

  @override
  StateOutput? getLatestState() => _latestState;

  @override
  double getFps() => _fps;

  @override
  int getTier() => _tier;
}
