import 'package:flutter/material.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'link_laptop_screen.dart';
import 'telemetry_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _deviceId;
  Map<String, dynamic>? _latestSnapshot;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  // Finds this account's phone device, self-registering one if this is the
  // first launch - see backend/src/routes/devices.js's self-registration
  // endpoint. No local persistence needed: the backend is the source of
  // truth for "do I have a device yet".
  Future<void> _bootstrap() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await ApiClient.instance.listDevices();
      Map<String, dynamic>? phone;
      for (final device in devices) {
        if (device['deviceType'] == 'phone') {
          phone = device;
          break;
        }
      }
      phone ??= await ApiClient.instance.registerDevice(
        deviceType: 'phone',
        platform: 'android',
        label: 'Android phone',
      );
      _deviceId = phone['id'] as String;
      await _refreshSnapshot();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _refreshSnapshot() async {
    final snapshot = await ApiClient.instance.latestSnapshot(_deviceId!);
    setState(() => _latestSnapshot = snapshot);
  }

  Future<void> _takeSnapshot() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final telemetry = await TelemetryService.instance.collect();
      await ApiClient.instance.uploadSnapshot(_deviceId!, {
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
      await _refreshSnapshot();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    final snapshot = _latestSnapshot;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Health Copilot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AuthService.instance.signOut(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _deviceId == null ? _bootstrap() : _refreshSnapshot(),
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
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: snapshot == null
                    ? const Text('No snapshot yet - tap "Take snapshot now" below.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Last snapshot: ${snapshot['capturedAt']}'),
                          const SizedBox(height: 8),
                          _snapshotRow('Battery', '${snapshot['batteryLevelPercent']}%'
                              '${snapshot['isCharging'] == true ? ' (charging)' : ''}'),
                          _snapshotRow('Voltage', '${snapshot['voltageMv']} mV'),
                          _snapshotRow('Temperature', _tenthsToC(snapshot['temperatureTenthsC'])),
                          _snapshotRow('Health enum', '${snapshot['healthEnum']}'),
                          _snapshotRow('Storage free', _bytesToGb(snapshot['storageFreeBytes'])),
                          _snapshotRow('Storage total', _bytesToGb(snapshot['storageTotalBytes'])),
                          _snapshotRow('RAM free', _bytesToGb(snapshot['ramFreeBytes'])),
                          _snapshotRow('RAM total', _bytesToGb(snapshot['ramTotalBytes'])),
                          _snapshotRow('Thermal status', '${snapshot['thermalStatus']}'),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: (_busy || _deviceId == null) ? null : _takeSnapshot,
              child: const Text('Take snapshot now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Link a laptop'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LinkLaptopScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _snapshotRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text(value)],
        ),
      );

  String _tenthsToC(dynamic tenths) {
    if (tenths == null) return 'unknown';
    return '${(tenths as num) / 10}°C';
  }

  String _bytesToGb(dynamic bytes) {
    if (bytes == null) return 'unknown';
    final value = bytes is String ? int.parse(bytes) : (bytes as num).toInt();
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
