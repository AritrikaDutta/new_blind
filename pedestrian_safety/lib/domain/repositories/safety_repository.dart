import '../../data/models/crossing_config.dart';
import '../../data/models/state_output.dart';
import '../../data/models/safety_report.dart';
import '../entities/vehicle.dart';

abstract class SafetyRepository {
  Future<bool> processFrame(dynamic frame, CrossingConfig config);
  Future<void> reset();
  Future<SafetyReport> getSessionReport();
  List<Vehicle> getActiveVehicles();
  List<Vehicle> getTopKThreats();
  StateOutput? getLatestState();
  double getFps();
  int getTier();
}
