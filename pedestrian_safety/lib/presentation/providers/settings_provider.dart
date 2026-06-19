import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/models/crossing_config.dart';

class SettingsProvider with ChangeNotifier {
  CrossingConfig _config = CrossingConfig.defaultConfig();
  bool _isLoading = true;

  CrossingConfig get config => _config;
  bool get isLoading => _isLoading;

  double get roadWidthM => _config.roadWidthM;
  double get walkSpeedMps => _config.walkSpeedMps;
  bool get useAiDepth => _config.useAiDepth;
  bool get useEgoMotion => _config.useEgoMotion;
  int get threatRankK => _config.threatRankK;
  int get smoothingFrames => _config.smoothingFrames;
  double get minConfidenceThreshold => _config.minConfidenceThreshold;
  double get safetyMarginSec => _config.safetyMarginSec;

  // Derived getters
  double get crossingTimeSec => _config.roadWidthM / (_config.walkSpeedMps > 0 ? _config.walkSpeedMps : 0.8);
  double get safeTtcLimitSec => crossingTimeSec + _config.safetyMarginSec;

  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final configJsonStr = prefs.getString('crossing_config');
      if (configJsonStr != null) {
        final Map<String, dynamic> configMap = jsonDecode(configJsonStr);
        _config = CrossingConfig.fromJson(configMap);
      }
    } catch (e) {
      // Fallback to default config on error
      _config = CrossingConfig.defaultConfig();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSettings(CrossingConfig newConfig) async {
    _config = newConfig;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('crossing_config', jsonEncode(_config.toJson()));
    } catch (e) {
      // Handle error or log
    }
  }

  Future<void> updateRoadWidth(double width) async {
    await updateSettings(_config.copyWith(roadWidthM: width));
  }

  Future<void> updateWalkSpeed(double speed) async {
    await updateSettings(_config.copyWith(walkSpeedMps: speed));
  }

  Future<void> updateSafetyMargin(double margin) async {
    await updateSettings(_config.copyWith(safetyMarginSec: margin));
  }

  Future<void> updateMinConfidence(double conf) async {
    await updateSettings(_config.copyWith(minConfidenceThreshold: conf));
  }

  Future<void> toggleAiDepth(bool enabled) async {
    await updateSettings(_config.copyWith(useAiDepth: enabled));
  }

  Future<void> toggleEgoMotion(bool enabled) async {
    await updateSettings(_config.copyWith(useEgoMotion: enabled));
  }
}
