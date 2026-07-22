import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class GpsService extends ChangeNotifier {
  Position? latest;
  bool _active = false;
  StreamSubscription<Position>? _sub;

  bool get active => _active;

  Future<bool> start() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return false;
    }
    if (perm == LocationPermission.deniedForever) return false;

    _active = true;
    _sub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    ).listen((p) {
      latest = p;
      notifyListeners();
    });
    notifyListeners();
    return true;
  }

  void stop() {
    _sub?.cancel();
    _active = false;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
