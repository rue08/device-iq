import 'package:flutter/services.dart';

// Talks to the native probe in MainActivity.kt (ported from the validated
// Kotlin spike - see PROJECT.md §1) to read battery/storage/RAM/thermal
// values that Dart has no direct access to.
class TelemetryService {
  TelemetryService._();
  static final TelemetryService instance = TelemetryService._();

  static const _channel = MethodChannel('com.deviceiq.device_iq/telemetry');

  Future<Map<String, dynamic>> collect() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('collect');
    if (result == null) {
      throw StateError('Native telemetry channel returned no data');
    }
    return result;
  }
}
