import '../../domain/entities/safety_state.dart';

class StateOutput {
  final SafetyState internalState;
  final String spokenText;
  final String audioStem;
  final double confidence;
  final double riskScore;
  final String secondaryCue;

  StateOutput({
    required this.internalState,
    required this.spokenText,
    required this.audioStem,
    required this.confidence,
    this.riskScore = 0.0,
    this.secondaryCue = '',
  });

  String get fullSpoken {
    if (secondaryCue.isNotEmpty) {
      return '$spokenText. $secondaryCue';
    }
    return spokenText;
  }
}
