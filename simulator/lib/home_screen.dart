import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'bafang_data.dart';
import 'ble_service.dart';

class HomeScreen extends StatefulWidget {
  final BleService bleService;
  const HomeScreen({super.key, required this.bleService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  final _hexController = TextEditingController();

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BafangData>(builder: (context, data, _) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: _buildAppBar(data),
        body: IndexedStack(
          index: _tab,
          children: [
            _DataTab(data: data),
            _HexTab(data: data, controller: _hexController),
            _LogTab(bleService: widget.bleService),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xFF111111),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.speed),       label: 'Data'),
            NavigationDestination(icon: Icon(Icons.terminal),    label: 'Hex inject'),
            NavigationDestination(icon: Icon(Icons.article),     label: 'BLE log'),
          ],
        ),
      );
    });
  }

  AppBar _buildAppBar(BafangData data) {
    final statusColor = switch (data.bleStatus) {
      'OK'   => Colors.greenAccent,
      'SIM'  => Colors.amber,
      'INIT' => Colors.lightBlueAccent,
      'ERR'  => Colors.redAccent,
      _      => Colors.white54,
    };

    return AppBar(
      backgroundColor: Colors.black,
      title: RichText(
        text: TextSpan(
          style: const TextStyle(fontFamily: 'Courier', fontSize: 16),
          children: [
            const TextSpan(text: 'BafangRideSync  ',
                style: TextStyle(color: Colors.white)),
            TextSpan(text: '[${data.bleStatus}]',
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.science_outlined, color: Colors.amber),
          tooltip: 'Inject sim frames',
          onPressed: data.injectSimFrames,
        ),
        if (data.bleStatus == 'SCAN' || data.bleStatus == 'ERR' || data.bleStatus == 'IDLE')
          IconButton(
            icon: const Icon(Icons.bluetooth_searching, color: Colors.lightBlueAccent),
            tooltip: 'Start scan',
            onPressed: widget.bleService.startScan,
          ),
        if (data.bleStatus == 'SCAN')
          IconButton(
            icon: const Icon(Icons.bluetooth_disabled, color: Colors.white54),
            tooltip: 'Stop scan',
            onPressed: widget.bleService.stopScan,
          ),
      ],
    );
  }
}

// ── Data tab ──────────────────────────────────────────────────────────────────

class _DataTab extends StatelessWidget {
  final BafangData data;
  const _DataTab({required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('MODEL', data.model),
        const SizedBox(height: 12),
        _metric('BATTERY',  _pct(data.battery), Colors.greenAccent),
        _metric('PAS',      data.pas?.toString() ?? '--', Colors.lightBlueAccent),
        _metric('SPEED',    _kmh(data.speedKmh),   Colors.white),
        _metric('TRIP',     _km(data.tripKm),       Colors.white70),
        _metric('ODO',      _km(data.odometerKm),   Colors.white70),
        const Divider(color: Colors.white12, height: 32),
        _label('TICK',  data.tickCounter?.toString() ?? '--'),
        _label('WHEEL CFG', data.wheelCfg != null ? '${data.wheelCfg} mm?' : '--'),
        const Divider(color: Colors.white12, height: 32),
        if (data.raw0601 != null) _hexBlock('06 01 DATA', data.raw0601!),
        if (data.raw0609 != null) _hexBlock('06 09 DATA', data.raw0609!),
      ]),
    );
  }

  String _pct(int? v)    => v != null ? '$v %' : '--';
  String _kmh(double? v) => v != null ? '${v.toStringAsFixed(1)} km/h' : '--';
  String _km(double? v)  => v != null ? '${v.toStringAsFixed(2)} km'   : '--';

  Widget _metric(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white38, fontFamily: 'Courier', fontSize: 13)),
        Text(value,
            style: TextStyle(color: color, fontFamily: 'Courier',
                fontSize: 26, fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _label(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [
      Text('$k  ', style: const TextStyle(color: Colors.white38, fontFamily: 'Courier', fontSize: 12)),
      Expanded(child: Text(v, style: const TextStyle(color: Colors.white60, fontFamily: 'Courier', fontSize: 12))),
    ]),
  );

  Widget _hexBlock(String title, Uint8List bytes) {
    final rows = <String>[];
    for (int i = 0; i < bytes.length; i += 8) {
      final end  = (i + 8).clamp(0, bytes.length);
      final hex  = bytes.sublist(i, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      final idxs = List.generate(end - i, (j) => '[${i + j}]'.padLeft(4)).join(' ');
      rows.add('  $hex');
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: Colors.white38, fontFamily: 'Courier', fontSize: 11)),
        Text(rows.join('\n'),
            style: const TextStyle(color: Colors.white24, fontFamily: 'Courier', fontSize: 11)),
      ]),
    );
  }
}

// ── Hex inject tab ────────────────────────────────────────────────────────────

class _HexTab extends StatefulWidget {
  final BafangData data;
  final TextEditingController controller;
  const _HexTab({required this.data, required this.controller});

  @override
  State<_HexTab> createState() => _HexTabState();
}

class _HexTabState extends State<_HexTab> {
  String _result = '';

  void _inject() {
    final ok = widget.data.injectHex(widget.controller.text);
    setState(() => _result = ok ? '✓ Injected' : '✗ Parse failed');
  }

  void _preset(String hex) {
    widget.controller.text = hex;
    _inject();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Paste a full frame (55 aa …) or raw DATA bytes:',
            style: TextStyle(color: Colors.white54, fontFamily: 'Courier', fontSize: 12)),
        const SizedBox(height: 8),
        TextField(
          controller: widget.controller,
          maxLines: 4,
          style: const TextStyle(color: Colors.greenAccent, fontFamily: 'Courier', fontSize: 13),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1a1a1a),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: Colors.white24)),
            hintText: 'e.g.  55 aa 15 10 11 06 01 00 00 00 01 …',
            hintStyle: const TextStyle(color: Colors.white24, fontFamily: 'Courier', fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: ElevatedButton(
            onPressed: _inject,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003300)),
            child: const Text('Inject', style: TextStyle(fontFamily: 'Courier')),
          )),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () { widget.controller.clear(); setState(() => _result = ''); },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF330000)),
            child: const Text('Clear', style: TextStyle(fontFamily: 'Courier')),
          ),
        ]),
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_result, style: TextStyle(
              color: _result.startsWith('✓') ? Colors.greenAccent : Colors.redAccent,
              fontFamily: 'Courier', fontSize: 13)),
        ],
        const Divider(color: Colors.white12, height: 32),
        const Text('Presets:', style: TextStyle(color: Colors.white38, fontFamily: 'Courier', fontSize: 12)),
        const SizedBox(height: 8),
        _presetBtn('Sim 06 01 (battery=81%, PAS=1, speed=41.27)',
            '55 aa 15 10 11 06 01 '
            '00 00 00 01 00 01 09 51 '
            '00 1f 10 3c 2d 00 00 3a 6e 00 00 00 00 '
            'XX XX'),   // user should fill checksum or use raw DATA below
        const SizedBox(height: 4),
        _presetBtn('Raw 06 01 DATA (21 bytes)',
            '00 00 00 01 00 01 09 51 '
            '00 1f 10 3c 2d 00 00 3a 6e 00 00 00 00'),
        const SizedBox(height: 4),
        _presetBtn('Raw 06 09 DATA (16 bytes)',
            'fd 51 00 00 c1 07 5a 11 18 01 de 03 55 00 01 05'),
        const SizedBox(height: 16),
        const Text(
          'Tip: copy payload bytes from ekd01_payloads.txt / ekd01_0104_verbose_hex.txt '
          'and paste here. Full frames are checksummed; raw DATA bytes are injected directly.',
          style: TextStyle(color: Colors.white24, fontFamily: 'Courier', fontSize: 11),
        ),
      ]),
    );
  }

  Widget _presetBtn(String label, String hex) => OutlinedButton(
    onPressed: () => _preset(hex),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Colors.white24),
      alignment: Alignment.centerLeft,
    ),
    child: Text(label,
        style: const TextStyle(color: Colors.white54, fontFamily: 'Courier', fontSize: 11)),
  );
}

// ── BLE log tab ───────────────────────────────────────────────────────────────

class _LogTab extends StatelessWidget {
  final BleService bleService;
  const _LogTab({required this.bleService});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 14, color: Colors.white38),
            label: const Text('Copy', style: TextStyle(color: Colors.white38, fontSize: 12)),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bleService.log.reversed.join('\n')));
            },
          ),
        ]),
      ),
      Expanded(
        child: StatefulBuilder(builder: (ctx, refresh) {
          return ListView.builder(
            reverse: true,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: bleService.log.length,
            itemBuilder: (_, i) => Text(
              bleService.log[i],
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 11,
                color: bleService.log[i].contains('TX') ? Colors.lightBlueAccent
                     : bleService.log[i].contains('RX') ? Colors.greenAccent
                     : Colors.white38,
              ),
            ),
          );
        }),
      ),
    ]);
  }
}
