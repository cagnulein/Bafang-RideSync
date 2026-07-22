import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LiveActivityService {
  static const _ch = MethodChannel('com.bafang.ridesync/live_activity');

  bool _supported = false;
  bool _active = false;

  Future<bool> init() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      _supported = await _ch.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      _supported = false;
    }
    return _supported;
  }

  Future<bool> start({required String startLabel}) async {
    if (!_supported) return false;
    try {
      final ok = await _ch.invokeMethod<bool>('start', {'startLabel': startLabel}) ?? false;
      _active = ok;
      return ok;
    } catch (e) {
      debugPrint('LiveActivity start error: $e');
      return false;
    }
  }

  Future<void> update({
    required int heartRate,
    required int pas,
    required double speedKmh,
    required int battery,
    required String zoneName,
    required String zoneColorHex,
    required int elapsedSeconds,
  }) async {
    if (!_active) return;
    try {
      await _ch.invokeMethod('update', {
        'heartRate': heartRate,
        'pas': pas,
        'speedKmh': speedKmh,
        'battery': battery,
        'zoneName': zoneName,
        'zoneColorHex': zoneColorHex,
        'elapsedSeconds': elapsedSeconds,
      });
    } catch (_) {}
  }

  Future<void> end() async {
    if (!_active) return;
    _active = false;
    try {
      await _ch.invokeMethod('end');
    } catch (_) {}
  }
}
