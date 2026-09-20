import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';

// Deployed backend (EC2 + RDS behind nginx/certbot). For the Android
// emulator against a local backend, use http://10.0.2.2:4000 instead.
const String _baseUrl = 'https://deviceiq.duckdns.org';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

// Thin wrapper around the backend's device/snapshot endpoints - see
// backend/src/routes/devices.js. Every call attaches the current
// Firebase ID token as a bearer token, per backend/src/lib/authMiddleware.js.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.instance.currentIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  dynamic _decodeOrThrow(http.Response response, {List<int> okStatuses = const [200, 201]}) {
    if (!okStatuses.contains(response.statusCode)) {
      String message = response.body;
      try {
        message = (jsonDecode(response.body) as Map)['error']?.toString() ?? message;
      } catch (_) {}
      throw ApiException(response.statusCode, message);
    }
    return jsonDecode(response.body);
  }

  Future<List<Map<String, dynamic>>> listDevices() async {
    final response = await http.get(Uri.parse('$_baseUrl/devices'), headers: await _authHeaders());
    final body = _decodeOrThrow(response) as List;
    return body.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> registerDevice({
    required String deviceType,
    required String platform,
    String? manufacturer,
    String? model,
    String? label,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/devices'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'deviceType': deviceType,
        'platform': platform,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (model != null) 'model': model,
        if (label != null) 'label': label,
      }),
    );
    return _decodeOrThrow(response) as Map<String, dynamic>;
  }

  // Claims a laptop agent's pairing QR token, creating the laptop's Device
  // row under this account. See backend/src/routes/pairing.js.
  Future<Map<String, dynamic>> claimPairing({
    required String token,
    required String deviceType,
    required String platform,
    String? manufacturer,
    String? model,
    String? label,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/devices/claim'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'token': token,
        'deviceType': deviceType,
        'platform': platform,
        if (manufacturer != null) 'manufacturer': manufacturer,
        if (model != null) 'model': model,
        if (label != null) 'label': label,
      }),
    );
    return _decodeOrThrow(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> renameDevice(String deviceId, String label) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/devices/$deviceId'),
      headers: await _authHeaders(),
      body: jsonEncode({'label': label}),
    );
    return _decodeOrThrow(response) as Map<String, dynamic>;
  }

  Future<void> deleteDevice(String deviceId) => _delete('$_baseUrl/devices/$deviceId');

  // Permanently deletes this account and all its data on the backend.
  Future<void> deleteAccount() => _delete('$_baseUrl/account');

  Future<void> _delete(String url) async {
    final response = await http.delete(Uri.parse(url), headers: await _authHeaders());
    // 204 No Content - nothing to decode, so bypass _decodeOrThrow.
    if (response.statusCode != 204) {
      String message = response.body;
      try {
        message = (jsonDecode(response.body) as Map)['error']?.toString() ?? message;
      } catch (_) {}
      throw ApiException(response.statusCode, message);
    }
  }

  Future<Map<String, dynamic>> uploadSnapshot(String deviceId, Map<String, dynamic> snapshot) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/devices/$deviceId/snapshots'),
      headers: await _authHeaders(),
      body: jsonEncode(snapshot),
    );
    return _decodeOrThrow(response) as Map<String, dynamic>;
  }

  // Returns null if the device has no snapshots yet (backend 404s in that case).
  Future<Map<String, dynamic>?> latestSnapshot(String deviceId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/devices/$deviceId/snapshots/latest'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 404) return null;
    return _decodeOrThrow(response) as Map<String, dynamic>;
  }

  // Health score and per-component breakdown, computed on request by the
  // backend - see backend/src/lib/scoring.js. Returns null if the device has
  // no recent snapshots yet (backend 404s in that case).
  Future<Map<String, dynamic>?> deviceScore(String deviceId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/devices/$deviceId/score'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 404) return null;
    return _decodeOrThrow(response) as Map<String, dynamic>;
  }

  // AI explanation of the score, cached by the backend (reused for an hour,
  // see backend/src/routes/devices.js). `refresh` forces a new one. Returns
  // null if the device has no recent snapshots yet.
  Future<Map<String, dynamic>?> deviceSummary(String deviceId, {bool refresh = false}) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/devices/$deviceId/summary${refresh ? '?refresh=true' : ''}'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 404) return null;
    return _decodeOrThrow(response) as Map<String, dynamic>;
  }
}
