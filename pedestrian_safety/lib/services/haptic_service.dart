import 'package:flutter/services.dart';
import '../domain/entities/safety_state.dart';

class HapticService {
  Future<void> triggerForState(SafetyState state) async {
    switch (state) {
      case SafetyState.safe:
        // A single light buzz for reassurance
        await HapticFeedback.lightImpact();
        break;
      case SafetyState.walkFast:
        // Double medium impact
        await HapticFeedback.mediumImpact();
        await Future.delayed(const Duration(milliseconds: 150));
        await HapticFeedback.mediumImpact();
        break;
      case SafetyState.wait:
      case SafetyState.uncertain:
        // Dual heavy impact
        await HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 150));
        await HapticFeedback.heavyImpact();
        break;
      case SafetyState.stop:
        // Intense long vibration
        await HapticFeedback.vibrate();
        await Future.delayed(const Duration(milliseconds: 250));
        await HapticFeedback.vibrate();
        break;
    }
  }
}
