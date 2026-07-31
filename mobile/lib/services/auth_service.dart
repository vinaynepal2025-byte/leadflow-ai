import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = 'http://localhost:3000';
  static const _tokenKey = 'leadflow_token';
  static const _tenantKey = 'leadflow_tenant_id';
  static const _userNameKey = 'leadflow_user_name';

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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, data['token']);
    await prefs.setString(_tenantKey, data['user']['tenant_id']);
    await prefs.setString(_userNameKey, data['user']['full_name']);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_tenantKey);
    await prefs.remove(_userNameKey);
  }
}
