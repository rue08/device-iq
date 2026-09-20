import 'package:flutter/material.dart';

import 'api_client.dart';
import 'auth_service.dart';
import 'device_detail_screen.dart';
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

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _confirmSignOut() async {
    final ok = await _confirm(
      title: 'Log out?',
      message: 'You can sign back in with Google any time. Your devices and data are kept.',
      action: 'Log out',
    );
    if (ok) await AuthService.instance.signOut();
  }

  Future<void> _confirmDeleteAccount() async {
    final ok = await _confirm(
      title: 'Delete your account?',
      message: 'This permanently deletes your account, every linked device and all snapshots. '
          'It cannot be undone.',
      action: 'Delete account',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ApiClient.instance.deleteAccount();
      await AuthService.instance.signOut();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _rename(Map<String, dynamic> device) async {
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialName: _deviceTitle(device)),
    );
    if (newName == null) return;
    try {
      await ApiClient.instance.renameDevice(device['id'] as String, newName);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _unlink(_DeviceEntry entry) async {
    final name = _deviceTitle(entry.device);
    final confirmed = await _confirm(
      title: 'Unlink $name?',
      message: 'This removes the device and all of its snapshots from your account.',
      action: 'Unlink',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ApiClient.instance.deleteDevice(entry.device['id'] as String);
      await _load();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String _deviceTitle(Map<String, dynamic> device) {
    final isPhone = device['deviceType'] == 'phone';
    return (device['label'] ?? device['model'] ?? (isPhone ? 'Phone' : 'Laptop')) as String;
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
            tooltip: 'Log out',
            onPressed: _confirmSignOut,
          ),
          IconButton(
            icon: Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
            tooltip: 'Delete account',
            onPressed: _confirmDeleteAccount,
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
    final details = [device['manufacturer'], device['model']].whereType<String>().join(' ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeviceDetailScreen(title: _deviceTitle(device), device: device),
          ),
        ),
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isPhone ? Icons.smartphone : Icons.laptop),
                const SizedBox(width: 8),
                Flexible(child: Text(_deviceTitle(device), style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  tooltip: 'Rename',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _rename(device),
                ),
                const Spacer(),
                Text(_platformName(device['platform'])),
                if (!isPhone)
                  IconButton(
                    icon: const Icon(Icons.link_off),
                    tooltip: 'Unlink',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _unlink(entry),
                  ),
              ],
            ),
            if (details.isNotEmpty) Text(details, style: Theme.of(context).textTheme.bodySmall),
            Text('Tap for health score',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 8),
            if (snapshot == null)
              const Text('No snapshot yet - it will appear after the first sync.')
            else ...[
              Text('Updated ${formatIst(snapshot['capturedAt'])}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              ..._snapshotRows(snapshot),
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
      ),
    );
  }

  // Every snapshot field the backend stores, skipping ones the platform
  // doesn't report (null). `raw` entries are appended at the end.
  List<Widget> _snapshotRows(Map<String, dynamic> s) {
    String? text(dynamic v) => v == null ? null : '$v';
    final rows = <String, String?>{
      'Battery': s['batteryLevelPercent'] == null
          ? null
          : '${s['batteryLevelPercent']}%${s['isCharging'] == true ? ' (charging)' : ''}',
      'Charging': s['isCharging'] == null ? null : (s['isCharging'] == true ? 'Yes' : 'No'),
      'Voltage': s['voltageMv'] == null ? null : '${s['voltageMv']} mV',
      'Temperature': s['temperatureTenthsC'] == null ? null : '${(s['temperatureTenthsC'] as num) / 10}°C',
      'Battery status': s['healthEnum'] == null ? null : _healthName(s['healthEnum']),
      'Battery health': _capacityPercent(s) == null ? null : '${_capacityPercent(s)}%',
      'Design capacity': s['designCapacityMah'] == null ? null : '${s['designCapacityMah']} mAh',
      'Full-charge capacity': s['fullChargeCapacityMah'] == null ? null : '${s['fullChargeCapacityMah']} mAh',
      'Cycle count': text(s['cycleCount']),
      'Storage free': s['storageFreeBytes'] == null ? null : _gb(s['storageFreeBytes']),
      'Storage total': s['storageTotalBytes'] == null ? null : _gb(s['storageTotalBytes']),
      'RAM free': s['ramFreeBytes'] == null ? null : _gb(s['ramFreeBytes']),
      'RAM total': s['ramTotalBytes'] == null ? null : _gb(s['ramTotalBytes']),
      'Thermal': text(s['thermalStatus']),
    };
    final raw = s['raw'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        if (entry.value != null) rows[_prettyKey('${entry.key}')] = '${entry.value}';
      }
    }
    return [
      for (final entry in rows.entries)
        if (entry.value != null) _row(entry.key, entry.value!),
    ];
  }

  // Android's BatteryManager.EXTRA_HEALTH values.
  String _healthName(dynamic value) => switch (value) {
        2 => 'Good',
        3 => 'Overheat',
        4 => 'Dead',
        5 => 'Over voltage',
        6 => 'Failure',
        7 => 'Cold',
        _ => 'Unknown ($value)',
      };

  // camelCase -> "Camel case" for raw keys we don't have a label for.
  String _prettyKey(String key) {
    final spaced = key.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]!.toLowerCase()}');
    return spaced[0].toUpperCase() + spaced.substring(1);
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

// Edit-name dialog. Save is faded until the text differs from the current
// name (and isn't blank); Cancel or the back button discards the edit.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialName});
  final String initialName;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final name = _controller.text.trim();
        final changed = name.isNotEmpty && name != widget.initialName;
        return AlertDialog(
          title: const Text('Rename device'),
          content: TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 60,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            // Null onPressed renders the button faded/disabled.
            FilledButton(
              onPressed: changed ? () => Navigator.pop(context, name) : null,
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}
