// In-memory session for the current app run only (not persisted across restarts —
// add a storage layer like shared_preferences if that's needed later).
class AuthState {
  static String? token;
  static Map<String, dynamic>? user;

  static void set(String newToken, Map<String, dynamic> newUser) {
    token = newToken;
    user = newUser;
  }

  static void clear() {
    token = null;
    user = null;
  }
}
