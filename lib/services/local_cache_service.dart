// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;

class LocalCacheEntry<T> {
  final T value;
  final DateTime storedAt;

  const LocalCacheEntry({
    required this.value,
    required this.storedAt,
  });
}

class LocalCacheService {
  LocalCacheService._();

  static final instance = LocalCacheService._();
  static const _prefix = 'fobal_cache_v1_';

  LocalCacheEntry<Map<String, dynamic>>? readMap(String key) {
    final raw = html.window.localStorage['$_prefix$key'];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final storedAt = DateTime.tryParse(
            decoded['storedAt'] as String? ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final value = Map<String, dynamic>.from(
        decoded['value'] as Map? ?? const {},
      );
      return LocalCacheEntry(value: value, storedAt: storedAt);
    } catch (_) {
      html.window.localStorage.remove('$_prefix$key');
      return null;
    }
  }

  LocalCacheEntry<List<dynamic>>? readList(String key) {
    final raw = html.window.localStorage['$_prefix$key'];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final storedAt = DateTime.tryParse(
            decoded['storedAt'] as String? ?? '',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final value = List<dynamic>.from(decoded['value'] as List? ?? const []);
      return LocalCacheEntry(value: value, storedAt: storedAt);
    } catch (_) {
      html.window.localStorage.remove('$_prefix$key');
      return null;
    }
  }

  void write(String key, Object? value) {
    html.window.localStorage['$_prefix$key'] = jsonEncode({
      'storedAt': DateTime.now().toUtc().toIso8601String(),
      'value': value,
    });
  }
}
