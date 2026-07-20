import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'bafang_data.dart';
import 'ble_service.dart';
import 'home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => BafangData(),
      child: const BafangSimApp(),
    ),
  );
}

class BafangSimApp extends StatefulWidget {
  const BafangSimApp({super.key});
  @override
  State<BafangSimApp> createState() => _BafangSimAppState();
}

class _BafangSimAppState extends State<BafangSimApp> {
  late final BleService _bleService;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  @override
  void initState() {
    super.initState();
    _bleService = BleService(context.read<BafangData>());
    // Wait for adapter to be poweredOn before scanning (needed on macOS for
    // the permission dialog to appear and CoreBluetooth to initialise).
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BafangRideSync Sim',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.dark(
        primary:   Colors.greenAccent.shade700,
        secondary: Colors.lightBlueAccent,
        surface:   const Color(0xFF111111),
      ),
      scaffoldBackgroundColor: Colors.black,
    ),
    home: HomeScreen(bleService: _bleService),
  );
}
