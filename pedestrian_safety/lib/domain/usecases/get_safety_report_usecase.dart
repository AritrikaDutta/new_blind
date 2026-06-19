import '../../data/models/safety_report.dart';
import '../repositories/safety_repository.dart';

class GetSafetyReportUseCase {
  final SafetyRepository repository;

  const GetSafetyReportUseCase(this.repository);

  Future<SafetyReport> call() async {
    return await repository.getSessionReport();
  }
}
