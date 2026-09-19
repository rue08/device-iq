import 'package:flutter/material.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'link_laptop_screen.dart';
import 'telemetry_service.dart';
import 'time_format.dart';

// One account device plus its most recent snapshot (null if none yet).
class _DeviceEntry {
  _DeviceEntry(this.device, this.snapshot);
  final Map<String, dynamic> device;
  final Map<String, dynamic>? snapshot;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _phoneDeviceId;
  List<_DeviceEntry> _entries = [];
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // Loads every device on the account with its latest snapshot, self-
  // registering this phone first if this is the first launch - see
  // backend/src/routes/devices.js. No local persistence needed: the backend
  // is the source of truth.
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var devices = await ApiClient.instance.listDevices();
      if (!devices.any((d) => d['deviceType'] == 'phone')) {
        await ApiClient.instance.registerDevice(
          deviceType: 'phone',
          platform: 'android',
          label: 'Android phone',
        );
        devices = await ApiClient.instance.listDevices();
      }
      final entries = await Future.wait(devices.map((device) async {
        final snapshot = await ApiClient.instance.latestSnapshot(device['id'] as String);
        return _DeviceEntry(device, snapshot);
      }));
      // Phone first, then laptops in creation order.
      entries.sort((a, b) {
        final aPhone = a.device['deviceType'] == 'phone' ? 0 : 1;
        final bPhone = b.device['deviceType'] == 'phone' ? 0 : 1;
        return aPhone.compareTo(bPhone);
      });
      setState(() {
        _entries = entries;
        _phoneDeviceId = entries
            .where((e) => e.device['deviceType'] == 'phone')
            .map((e) => e.device['id'] as String)
            .firstOrNull;
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _takeSnapshot() async {
    final deviceId = _phoneDeviceId;
    if (deviceId == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final telemetry = await TelemetryService.instance.collect();
      await ApiClient.instance.uploadSnapshot(deviceId, {
        'batteryLevelPercent': telemetry['batteryLevelPercent'],
        'isCharging': telemetry['isCharging'],
        'voltageMv': telemetry['voltageMv'],
        'healthEnum': telemetry['healthEnum'],
        'temperatureTenthsC': telemetry['temperatureTenthsC'],
        'storageTotalBytes': telemetry['storageTotalBytes'],
        'storageFreeBytes': telemetry['storageFreeBytes'],
        'ramTotalBytes': telemetry['ramTotalBytes'],
        'ramFreeBytes': telemetry['ramFreeBytes'],
        'thermalStatus': telemetry['thermalStatus'],
        'raw': telemetry['raw'],
      });
      await _load();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('DeviceIQ'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Link a laptop',
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LinkLaptopScreen()),
              );
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService.instance.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Signed in as ${user?.email ?? 'unknown'}'),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
            ],
            if (_busy) const LinearProgressIndicator(),
            for (final entry in _entries) ...[
              _deviceCard(entry),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Widget _deviceCard(_DeviceEntry entry) {
    final device = entry.device;
    final snapshot = entry.snapshot;
    final isPhone = device['deviceType'] == 'phone';
    final title = (device['label'] ?? device['model'] ?? (isPhone ? 'Phone' : 'Laptop')) as String;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isPhone ? Icons.smartphone : Icons.laptop),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
                Text(_platformName(device['platform'])),
              ],
            ),
            const SizedBox(height: 8),
            if (snapshot == null)
              const Text('No snapshot yet - it will appear after the first sync.')
            else ...[
              Text('Updated ${formatIst(snapshot['capturedAt'])}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              _row('Battery', '${snapshot['batteryLevelPercent'] ?? 'unknown'}%'
                  '${snapshot['isCharging'] == true ? ' (charging)' : ''}'),
              if (snapshot['voltageMv'] != null) _row('Voltage', '${snapshot['voltageMv']} mV'),
              if (snapshot['temperatureTenthsC'] != null)
                _row('Temperature', '${(snapshot['temperatureTenthsC'] as num) / 10}°C'),
              if (snapshot['healthEnum'] != null) _row('Health enum', '${snapshot['healthEnum']}'),
              if (snapshot['cycleCount'] != null) _row('Cycle count', '${snapshot['cycleCount']}'),
              if (_capacityPercent(snapshot) != null)
                _row('Battery capacity', '${_capacityPercent(snapshot)}% of design'),
              _row('Storage free', '${_gb(snapshot['storageFreeBytes'])} of ${_gb(snapshot['storageTotalBytes'])}'),
              _row('RAM free', '${_gb(snapshot['ramFreeBytes'])} of ${_gb(snapshot['ramTotalBytes'])}'),
              if (snapshot['thermalStatus'] != null) _row('Thermal', '${snapshot['thermalStatus']}'),
            ],
            if (isPhone) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: (_busy || _phoneDeviceId == null) ? null : _takeSnapshot,
                child: const Text('Take snapshot now'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value)],
        ),
      );

  String _platformName(dynamic platform) => switch (platform) {
        'android' => 'Android',
        'ios' => 'iOS',
        'macos' => 'macOS',
        'windows' => 'Windows',
        _ => '$platform',
      };

  int? _capacityPercent(Map<String, dynamic> snapshot) {
    final full = snapshot['fullChargeCapacityMah'];
    final design = snapshot['designCapacityMah'];
    if (full is! num || design is! num || design == 0) return null;
    return (full / design * 100).round();
  }

  String _gb(dynamic bytes) {
    if (bytes == null) return 'unknown';
    final value = bytes is String ? int.parse(bytes) : (bytes as num).toInt();
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
