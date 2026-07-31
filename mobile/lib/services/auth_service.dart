import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = 'http://localhost:3000';
  static const _tokenKey = 'leadflow_token';
  static const _tenantKey = 'leadflow_tenant_id';
  static const _userNameKey = 'leadflow_user_name';

  // In-memory cache so the current session keeps working even if the
  // SharedPreferences plugin is slow or unresponsive on a given device —
  // login and session checks never hang the UI. Persistence to disk below
  // is best-effort and timeout-bounded so it can only ever be a bonus,
  // never a blocker.
  static String? _cachedToken;
  static String? _cachedTenantId;
  static String? _cachedUserName;

  Future<Map<String, dynamic>> login({
    required String tenantId,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'tenant_id': tenantId, 'email': email, 'password': password}),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 200) {
      throw Exception(data['error'] ?? 'Login failed');
    }
    await _saveSession(data);
    return data;
  }

  Future<Map<String, dynamic>> register({
    required String tenantId,
    required String email,
    required String password,
    required String fullName,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'tenant_id': tenantId,
        'email': email,
        'password': password,
        'full_name': fullName,
      }),
    );
    final data = jsonDecode(res.body);
    if (res.statusCode != 201) {
      throw Exception(data['error'] ?? 'Registration failed');
    }
    await _saveSession(data);
    return data;
  }

  Future<void> _saveSession(Map<String, dynamic> data) async {
    // Update the in-memory cache first and immediately — this is what the
    // rest of the app reads, so login always "takes" for this app run even
    // if the disk write below is slow.
    _cachedToken = data['token'] as String?;
    _cachedTenantId = data['user']['tenant_id'] as String?;
    _cachedUserName = data['user']['full_name'] as String?;

    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      await prefs.setString(_tokenKey, _cachedToken ?? '');
      await prefs.setString(_tenantKey, _cachedTenantId ?? '');
      await prefs.setString(_userNameKey, _cachedUserName ?? '');
    } catch (_) {
      // Session still works for this app run via the in-memory cache above;
      // it just won't survive a full app restart on this device.
    }
  }

  Future<String?> getToken() async {
    if (_cachedToken != null) return _cachedToken;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      _cachedToken = prefs.getString(_tokenKey);
      return _cachedToken;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getUserName() async {
    if (_cachedUserName != null) return _cachedUserName;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      _cachedUserName = prefs.getString(_userNameKey);
      return _cachedUserName;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  Future<void> logout() async {
    _cachedToken = null;
    _cachedTenantId = null;
    _cachedUserName = null;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(const Duration(seconds: 5));
      await prefs.remove(_tokenKey);
      await prefs.remove(_tenantKey);
      await prefs.remove(_userNameKey);
    } catch (_) {}
  }
}
