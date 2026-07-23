import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'bafang_data.dart';
import 'ble_service.dart';
import 'home_screen.dart';
import 'models/heart_zone.dart';
import 'screens/onboarding_screen.dart';
import 'services/cadence_service.dart';
import 'services/gps_service.dart';
import 'services/health_service.dart';
import 'services/hr_service.dart';
import 'services/live_activity_service.dart';
import 'services/power_service.dart';
import 'services/workout_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final onboardingDone = prefs.getBool('onboarding_done') ?? false;
  runApp(BafangSimApp(showOnboarding: !onboardingDone));
}

class BafangSimApp extends StatefulWidget {
  final bool showOnboarding;
  const BafangSimApp({super.key, this.showOnboarding = false});
  @override
  State<BafangSimApp> createState() => _BafangSimAppState();
}

class _BafangSimAppState extends State<BafangSimApp> {
  late bool _showOnboarding;
  final _bikeData = BafangData();
  final _hrZones = HrZones();
  final _hrService = HrService();
  final _cadenceService = CadenceService();
  final _powerService = PowerService();
  final _gpsService = GpsService();
  final _healthService = HealthService();
  final _liveActivityService = LiveActivityService();
  late final BleService _bleService;
  late final WorkoutService _workoutService;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  @override
  void initState() {
    super.initState();
    _showOnboarding = widget.showOnboarding;
    _bleService = BleService(_bikeData);
    _workoutService = WorkoutService(
      bike: _bikeData,
      hr: _hrService,
      cadence: _cadenceService,
      power: _powerService,
      gps: _gpsService,
      zones: _hrZones,
      health: _healthService,
      liveActivity: _liveActivityService,
    );
    _healthService.init();
    _liveActivityService.init();
    // Wire PID → BleService PAS command
    _workoutService.onSetPas = (level) => _bleService.setPasLevel(level);
    // Wire BLE telemetry → WorkoutService (runs in background via bluetooth-central)
    _bleService.onTelemetry0601 = _workoutService.onBikeTelemetry;

    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _adapterSub?.cancel();
        _adapterSub = null;
        _bleService.startScan();
      }
    });
  }

  @override
  void dispose() {
    _adapterSub?.cancel();
    _bleService.dispose();
    _hrService.dispose();
    _cadenceService.dispose();
    _powerService.dispose();
    _gpsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: _bikeData),
          ChangeNotifierProvider.value(value: _hrZones),
          ChangeNotifierProvider.value(value: _hrService),
          ChangeNotifierProvider.value(value: _cadenceService),
          ChangeNotifierProvider.value(value: _powerService),
          ChangeNotifierProvider.value(value: _gpsService),
          ChangeNotifierProvider.value(value: _workoutService),
        ],
        child: MaterialApp(
          title: 'E-ERG',
          debugShowCheckedModeBanner: false,
          theme: ThemeData.dark(useMaterial3: true).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Colors.greenAccent.shade700,
              secondary: Colors.lightBlueAccent,
              surface: const Color(0xFF111111),
            ),
            scaffoldBackgroundColor: Colors.black,
          ),
          home: _showOnboarding
              ? OnboardingScreen(
                  onDone: () => setState(() => _showOnboarding = false),
                )
              : HomeScreen(bleService: _bleService),
        ),
      );
}
