import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseAuthService {
  static String url = '';
  static String anonKey = '';
  static String? configurationError;

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await _loadRuntimeConfig();
    if (!isConfigured) return;
    await Supabase.initialize(url: url, publishableKey: anonKey);
  }

  static Future<void> _loadRuntimeConfig() async {
    url = '';
    anonKey = '';
    configurationError = null;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await http
            .get(Uri.base.resolve('/api/public-config'))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) {
          configurationError = 'HTTP ${response.statusCode}';
        } else {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          url = data['supabaseUrl'] as String? ?? '';
          anonKey = data['supabaseAnonKey'] as String? ?? '';
          if (isConfigured) return;
          configurationError = 'La configuracion publica llego incompleta.';
        }
      } catch (error) {
        configurationError = error.toString();
      }
      if (attempt < 2) {
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
  }

  static Session? get currentSession {
    if (!isConfigured) return null;
    return client.auth.currentSession;
  }

  static String? get currentEmail {
    if (!isConfigured) return null;
    return client.auth.currentUser?.email;
  }

  static String? get currentUserId {
    if (!isConfigured) return null;
    return client.auth.currentUser?.id;
  }

  static Future<void> signInWithGoogle({
    bool localMode = false,
    String? redirectTo,
  }) async {
    if (!isConfigured) {
      throw const AuthConfigException();
    }

    final resolvedRedirect =
        redirectTo ??
        (localMode
            ? '${Uri.base.origin}/#/auth-local'
            : '${Uri.base.origin}/#/auth-lud');
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: resolvedRedirect,
    );
    if (!launched) {
      throw const AuthInputException(
        'No se pudo abrir Google. Vuelve a intentar.',
      );
    }
  }

  static Future<void> sendMagicLink(String email) async {
    if (!isConfigured) {
      throw const AuthConfigException();
    }

    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthInputException('Ingresa un email valido.');
    }

    final redirectTo = '${Uri.base.origin}/#/login';
    await client.auth.signInWithOtp(
      email: normalizedEmail,
      emailRedirectTo: redirectTo,
    );
  }

  static Future<void> signInWithPassword(String email, String password) async {
    if (!isConfigured) {
      throw const AuthConfigException();
    }
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthInputException('Ingresa un email valido.');
    }
    if (password.length < 6) {
      throw const AuthInputException('La contraseña debe tener al menos 6 caracteres.');
    }
    await client.auth.signInWithPassword(
      email: normalizedEmail,
      password: password,
    );
  }

  static Future<bool> signUpWithPassword({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    if (!isConfigured) {
      throw const AuthConfigException();
    }
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw const AuthInputException('Ingresa un email valido.');
    }
    if (password.length < 6) {
      throw const AuthInputException('La contraseña debe tener al menos 6 caracteres.');
    }
    final response = await client.auth.signUp(
      email: normalizedEmail,
      password: password,
      data: {
        'first_name': firstName.trim(),
        'last_name': lastName.trim(),
      },
      emailRedirectTo: '${Uri.base.origin}/#/login',
    );
    return response.session != null;
  }

  static Future<void> signOut() async {
    if (!isConfigured) return;
    await client.auth.signOut();
  }
}

class AuthConfigException implements Exception {
  const AuthConfigException();
}

class AuthInputException implements Exception {
  final String message;
  const AuthInputException(this.message);
}
