import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HealthService extends ChangeNotifier {
  static const _ch = MethodChannel('com.bafang.ridesync/health');

  bool available = false;
  bool authorized = false;

  Future<void> init() async {
    if (!defaultTargetPlatform.toString().contains('iOS') &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      available = await _ch.invokeMethod<bool>('isAvailable') ?? false;
      if (available) await requestAuthorization();
    } catch (_) {}
  }

  Future<bool> requestAuthorization() async {
    try {
      authorized = await _ch.invokeMethod<bool>('requestAuthorization') ?? false;
      notifyListeners();
      return authorized;
    } catch (_) {
      return false;
    }
  }

  Future<void> startWorkout(DateTime startTime) async {
    if (!authorized) return;
    try {
      await _ch.invokeMethod('startWorkout', {
        'startMs': startTime.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('HealthKit startWorkout error: $e');
    }
  }

  Future<void> addSample({
    int? heartRate,
    double? distanceKm,
    double? activeCalories,
  }) async {
    if (!authorized) return;
    try {
      await _ch.invokeMethod('addSample', {
        if (heartRate != null) 'heartRate': heartRate,
        if (distanceKm != null) 'distanceKm': distanceKm,
        if (activeCalories != null) 'activeCalories': activeCalories,
      });
    } catch (_) {}
  }

  /// Returns body mass in kg from the most recent HealthKit sample, or null.
  Future<double?> fetchBodyWeightKg() async {
    if (!authorized) return null;
    try {
      final result = await _ch.invokeMethod<double>('fetchBodyWeight');
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<void> endWorkout(DateTime endTime) async {
    if (!authorized) return;
    try {
      await _ch.invokeMethod('endWorkout', {
        'endMs': endTime.millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('HealthKit endWorkout error: $e');
    }
  }
}
