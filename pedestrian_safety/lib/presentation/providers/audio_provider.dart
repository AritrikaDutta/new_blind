import 'package:flutter/material.dart';
import '../../services/tts_service.dart';

class AudioProvider with ChangeNotifier {
  final TtsService _ttsService = TtsService();

  String? _lastState;
  DateTime? _lastSpeakTime;
  double _cooldownSeconds = 8.0;

  bool _isMuted = false;
  String _lastSpokenText = '';

  bool get isMuted => _isMuted;
  String get lastSpokenText => _lastSpokenText;

  void setMuted(bool muted) {
    _isMuted = muted;
    if (_isMuted) {
      _ttsService.stop();
    }
    notifyListeners();
  }

  void setCooldown(double seconds) {
    _cooldownSeconds = seconds;
    notifyListeners();
  }

  Future<void> speakStateAlert(String stateLabel, String spokenText) async {
    if (_isMuted) return;

    final now = DateTime.now();
    final bool isStateChanged = _lastState != stateLabel;
    final bool isCooldownOver = _lastSpeakTime == null ||
        now.difference(_lastSpeakTime!).inSeconds >= _cooldownSeconds;

    if (isStateChanged || isCooldownOver) {
      _lastSpeakTime = now;
      _lastState = stateLabel;
      _lastSpokenText = spokenText;
      notifyListeners();

      await _ttsService.speak(spokenText);
    }
  }

  Future<void> speakImmediate(String text) async {
    if (_isMuted) return;
    _lastSpokenText = text;
    notifyListeners();
    await _ttsService.speak(text);
  }

  Future<void> stop() async {
    await _ttsService.stop();
  }

  @override
  void dispose() {
    _ttsService.stop();
    super.dispose();
  }
}
