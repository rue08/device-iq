import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api_client.dart';

// Scans the QR a laptop agent shows (the QR payload is the bare pairing
// token) and claims it. The token carries no device info, so the user picks
// the laptop's OS here - see the backend's claimPairingSchema.
class LinkLaptopScreen extends StatefulWidget {
  const LinkLaptopScreen({super.key});

  @override
  State<LinkLaptopScreen> createState() => _LinkLaptopScreenState();
}

class _LinkLaptopScreenState extends State<LinkLaptopScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handling = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final token = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
    if (token == null || token.isEmpty) return;

    _handling = true;
    final choice = await showModalBottomSheet<_LaptopChoice>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ConfirmSheet(),
    );
    if (choice == null) {
      _handling = false; // dismissed - let the user scan again
      return;
    }

    try {
      await ApiClient.instance.claimPairing(
        token: token,
        deviceType: 'laptop',
        platform: choice.platform,
        manufacturer: choice.manufacturer,
        label: choice.label,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Laptop linked. It will finish setup in a few seconds.')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      _showError(switch (e.statusCode) {
        404 => 'That code expired. Reopen "Link This Device" on the laptop and scan again.',
        409 => 'That code was already used.',
        _ => e.message,
      });
    } catch (e) {
      _showError(e.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    _handling = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Link a laptop')),
      body: Column(
        children: [
          Expanded(child: MobileScanner(controller: _controller, onDetect: _onDetect)),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Open the DeviceIQ agent on your laptop, choose "Link This Device", and point the camera at the QR code.'),
          ),
        ],
      ),
    );
  }
}

class _LaptopChoice {
  const _LaptopChoice(this.platform, this.manufacturer, this.label);
  final String platform;
  final String? manufacturer;
  final String label;
}

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet();

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  String _platform = 'macos';
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What kind of laptop is this?', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'macos', label: Text('Mac'), icon: Icon(Icons.laptop_mac)),
              ButtonSegment(value: 'windows', label: Text('Windows'), icon: Icon(Icons.laptop_windows)),
            ],
            selected: {_platform},
            onSelectionChanged: (s) => setState(() => _platform = s.first),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                // Renamed later from the pencil icon on the device's card.
                Navigator.of(context).pop(_LaptopChoice(
                  _platform,
                  _platform == 'macos' ? 'Apple' : null,
                  _platform == 'macos' ? 'Mac laptop' : 'Windows laptop',
                ));
              },
              child: const Text('Link this laptop'),
            ),
          ),
        ],
      ),
    );
  }
}
