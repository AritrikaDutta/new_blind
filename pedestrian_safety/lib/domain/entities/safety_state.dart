enum SafetyState {
  safe,
  walkFast,
  wait,
  uncertain,
  stop;

  String get nameString {
    switch (this) {
      case SafetyState.safe:
        return 'SAFE';
      case SafetyState.walkFast:
        return 'WALK_FAST';
      case SafetyState.wait:
        return 'WAIT';
      case SafetyState.uncertain:
        return 'UNCERTAIN';
      case SafetyState.stop:
        return 'STOP';
    }
  }

  static SafetyState fromString(String stateStr) {
    switch (stateStr.toUpperCase()) {
      case 'SAFE':
        return SafetyState.safe;
      case 'WALK_FAST':
        return SafetyState.walkFast;
      case 'WAIT':
        return SafetyState.wait;
      case 'UNCERTAIN':
        return SafetyState.uncertain;
      case 'STOP':
        return SafetyState.stop;
      default:
        return SafetyState.uncertain;
    }
  }
}
