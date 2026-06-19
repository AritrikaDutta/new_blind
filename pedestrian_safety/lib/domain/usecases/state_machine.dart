import '../../data/models/state_output.dart';
import '../entities/safety_state.dart';

class SafetyStateMachine {
  final int smoothingFrames;
  final double minConfidence;

  SafetyState _currentState = SafetyState.safe;
  SafetyState _pendingState = SafetyState.safe;
  int _pendingCount = 0;

  SafetyStateMachine({
    this.smoothingFrames = 3,
    this.minConfidence = 0.65,
  });

  SafetyState get currentState => _currentState;

  static final Map<SafetyState, (String, String)> _spokenMap = {
    SafetyState.stop: ('Stop', 'stop'),
    SafetyState.uncertain: ('Please wait', 'stop'),
    SafetyState.wait: ('Please wait', 'stop'),
    SafetyState.safe: ('Cross now', 'walk_normal'),
    SafetyState.walkFast: ('Walk faster', 'walk_fast'),
  };

  StateOutput update({
    required SafetyState proposedState,
    required double confidence,
    double riskScore = 0.0,
    String secondaryCue = '',
  }) {
    // Low confidence -> UNCERTAIN immediately (safety-first, no gate)
    if (confidence < minConfidence) {
      _currentState = SafetyState.uncertain;
      _pendingState = SafetyState.uncertain;
      _pendingCount = 0;
      final mapData = _spokenMap[SafetyState.uncertain]!;
      return StateOutput(
        internalState: SafetyState.uncertain,
        spokenText: mapData.$1,
        audioStem: mapData.$2,
        confidence: confidence,
        riskScore: riskScore,
        secondaryCue: '',
      );
    }

    // Same as current — reset pending accumulator
    if (proposedState == _currentState) {
      _pendingState = proposedState;
      _pendingCount = 0;
    }
    // Continuing to accumulate the same pending state
    else if (proposedState == _pendingState) {
      _pendingCount++;
      if (_pendingCount >= smoothingFrames) {
        _currentState = proposedState;
        _pendingCount = 0;
      }
    }
    // New candidate state — restart accumulation
    else {
      _pendingState = proposedState;
      _pendingCount = 1;
    }

    final mapData = _spokenMap[_currentState]!;
    final cue = confidence >= minConfidence ? secondaryCue : '';

    return StateOutput(
      internalState: _currentState,
      spokenText: mapData.$1,
      audioStem: mapData.$2,
      confidence: confidence,
      riskScore: riskScore,
      secondaryCue: cue,
    );
  }

  void reset() {
    _currentState = SafetyState.safe;
    _pendingState = SafetyState.safe;
    _pendingCount = 0;
  }
}
