import 'package:shared_preferences/shared_preferences.dart';

class AuthSession {
  const AuthSession({required this.token, required this.role, this.name});

  final String token;
  final String role;
  final String? name;
}

class AuthStorage {
  static const _tokenKey = 'ska_auth_token';
  static const _roleKey = 'ska_auth_role';
  static const _nameKey = 'ska_auth_name';

  const AuthStorage._();

  static Future<void> saveSession({required String token, required String role, String? name}) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmedName = name?.trim();
    final futures = <Future<bool>>[
      prefs.setString(_tokenKey, token),
      prefs.setString(_roleKey, role),
      if (trimmedName != null && trimmedName.isNotEmpty)
        prefs.setString(_nameKey, trimmedName)
      else
        prefs.remove(_nameKey),
    ];
    await Future.wait(futures);
  }

  static Future<AuthSession?> readSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final role = prefs.getString(_roleKey);
    final name = prefs.getString(_nameKey)?.trim();

    if (token == null || token.isEmpty || role == null || role.isEmpty) {
      return null;
    }

    return AuthSession(
      token: token,
      role: role,
      name: name != null && name.isNotEmpty ? name : null,
    );
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_tokenKey),
      prefs.remove(_roleKey),
      prefs.remove(_nameKey),
    ]);
  }
}
