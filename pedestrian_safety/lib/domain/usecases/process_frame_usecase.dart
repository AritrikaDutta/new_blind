import '../../data/models/crossing_config.dart';
import '../repositories/safety_repository.dart';

class ProcessFrameUseCase {
  final SafetyRepository repository;

  const ProcessFrameUseCase(this.repository);

  Future<void> call(dynamic frame, CrossingConfig config) async {
    await repository.processFrame(frame, config);
  }
}
