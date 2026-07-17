import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _bleService = BleService(context.read<BafangData>());
    // Auto-start BLE scan on launch; comment out if you only want sim mode
    Future.microtask(_bleService.startScan);
  }

  @override
  void dispose() {
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
