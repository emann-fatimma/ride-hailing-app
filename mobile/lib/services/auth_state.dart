import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// Session for the current app run, persisted to disk so a restart doesn't
// log the user out. Call `AuthState.load()` once (from the splash screen)
// before relying on `token`/`user`.
class AuthState {
  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  static String? token;
  static Map<String, dynamic>? user;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);
    user = userJson != null ? jsonDecode(userJson) as Map<String, dynamic> : null;
  }

  static Future<void> set(String newToken, Map<String, dynamic> newUser) async {
    token = newToken;
    user = newUser;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, newToken);
    await prefs.setString(_userKey, jsonEncode(newUser));
  }

  static bool get isLoggedIn => token != null;

  static Future<void> clear() async {
    token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
