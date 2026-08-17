import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Chrome on the same machine as your backend can use localhost.
  // If you later test on a physical phone, replace this with your
  // computer's local IP, e.g. "http://192.168.1.5:3000"
  static const String baseUrl = 'http://localhost:3000';

  static Future<Map<String, dynamic>> signup({
    required String name,
    required String phone,
    required String password,
    required String verifyChannel, // 'phone' or 'email'
    String? email, // required (real address) when verifyChannel is 'email'
  }) async {
    final effectiveEmail = email ?? '${phone.replaceAll('+', '')}@rideeasy.temp';

    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': effectiveEmail,
        'phone': phone,
        'password': password,
        'role': 'rider',
        'verify_channel': verifyChannel,
      }),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 201) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Signup failed'};
    }
  }

  static Future<Map<String, dynamic>> sendCode({
    required String channel,
    required String destination,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/send-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'channel': channel, 'destination': destination}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Could not send code'};
    }
  }

  static Future<Map<String, dynamic>> verifyCode({
    required String channel,
    required String destination,
    required String code,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/verify-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'channel': channel, 'destination': destination, 'code': code}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Verification failed'};
    }
  }

  static Future<List<Map<String, dynamic>>> getCountries() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/api/countries'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['countries']);
      }
    } catch (_) {
      // fall through to empty list; caller falls back to a static list
    }
    return [];
  }

  static Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'password': password}),
    );

    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return {'success': true, 'data': data};
    } else {
      return {'success': false, 'error': data['error'] ?? 'Login failed'};
    }
  }
}
