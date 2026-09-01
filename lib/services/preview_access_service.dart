import 'dart:convert';

import 'package:http/http.dart' as http;

class PreviewAccessService {
  static String? _token;

  static bool get isGranted => _token != null && _token!.isNotEmpty;
  static String? get token => _token;

  static Future<void> grant(String code) async {
    final response = await http
        .post(
          Uri.base.resolve('/api/preview-session'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'code': code.trim()}),
        )
        .timeout(const Duration(seconds: 12));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 || data['token'] is! String) {
      throw PreviewAccessException(
        data['message'] as String? ?? 'No se pudo validar el codigo.',
      );
    }
    _token = data['token'] as String;
  }

  static void clear() {
    _token = null;
  }
}

class PreviewAccessException implements Exception {
  final String message;
  const PreviewAccessException(this.message);
}
