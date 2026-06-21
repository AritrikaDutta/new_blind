import '../../data/models/state_output.dart';
import '../entities/safety_state.dart';

class SafetyStateMachine {
  final int smoothingFrames;
  final double minConfidence;

  SafetyState _currentState = SafetyState.uncertain;
  SafetyState _pendingState = SafetyState.uncertain;
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

  int _threatLevel(SafetyState state) {
    switch (state) {
      case SafetyState.safe:
        return 0;
      case SafetyState.walkFast:
        return 1;
      case SafetyState.wait:
        return 2;
      case SafetyState.uncertain:
        return 3;
      case SafetyState.stop:
        return 4;
    }
  }

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

    // Immediate threat escalation (safety-first, bypass smoothing)
    if (_threatLevel(proposedState) > _threatLevel(_currentState)) {
      _currentState = proposedState;
      _pendingState = proposedState;
      _pendingCount = 0;
    }
    // Same as current — reset pending accumulator
    else if (proposedState == _currentState) {
      _pendingState = proposedState;
      _pendingCount = 0;
    }
    // Continuing to accumulate the same pending state (de-escalation smoothing)
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
    _currentState = SafetyState.uncertain;
    _pendingState = SafetyState.uncertain;
    _pendingCount = 0;
  }
}
