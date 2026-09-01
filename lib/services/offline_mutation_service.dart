// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import '../data/cantera_data.dart';
import 'club_access_service.dart';
import 'supabase_auth_service.dart';

enum OfflineWriteStatus { synced, queued }

class OfflineWriteResult {
  final OfflineWriteStatus status;
  final String mutationId;

  const OfflineWriteResult({
    required this.status,
    required this.mutationId,
  });

  bool get synced => status == OfflineWriteStatus.synced;
}

class OfflineMutation {
  final String id;
  final String type;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final int attempts;
  final String lastError;

  const OfflineMutation({
    required this.id,
    required this.type,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError = '',
  });

  OfflineMutation copyWith({int? attempts, String? lastError}) {
    return OfflineMutation(
      id: id,
      type: type,
      payload: payload,
      createdAt: createdAt,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'payload': payload,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'lastError': lastError,
      };

  factory OfflineMutation.fromJson(Map<String, dynamic> json) {
    return OfflineMutation(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? const {}),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
              DateTime.now().toUtc(),
      attempts: json['attempts'] as int? ?? 0,
      lastError: json['lastError'] as String? ?? '',
    );
  }
}

class OfflineMutationService {
  OfflineMutationService._();

  static final instance = OfflineMutationService._();
  static const _storageKey = 'fobal_offline_mutation_queue_v1';

  final _queueController =
      StreamController<List<OfflineMutation>>.broadcast();
  StreamSubscription<html.Event>? _onlineSubscription;
  Timer? _periodicFlush;
  bool _flushing = false;

  Stream<List<OfflineMutation>> get queueStream => _queueController.stream;

  List<OfflineMutation> get queue => _readQueue();

  bool get hasPending => queue.isNotEmpty;

  void start() {
    _onlineSubscription ??=
        html.window.onOnline.listen((_) => unawaited(flush()));
    _periodicFlush ??= Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(flush()),
    );
    unawaited(flush());
  }

  void dispose() {
    _onlineSubscription?.cancel();
    _periodicFlush?.cancel();
    _queueController.close();
  }

  Future<OfflineWriteResult> saveTacticalDataOfflineFirst({
    required String type,
    required String title,
    required Map<String, dynamic> content,
    int? relatedLudTeamId,
    String? categoryId,
  }) async {
    final mutation = OfflineMutation(
      id: 'mutation-${DateTime.now().microsecondsSinceEpoch}',
      type: 'club_tactical_data.upsert',
      createdAt: DateTime.now().toUtc(),
      payload: {
        'type': type,
        'title': title,
        'content': content,
        'relatedLudTeamId': relatedLudTeamId,
        'categoryId': categoryId,
      },
    );

    if (_canAttemptRemoteWrite) {
      try {
        final saved = await _syncTacticalData(mutation);
        if (saved) {
          return OfflineWriteResult(
            status: OfflineWriteStatus.synced,
            mutationId: mutation.id,
          );
        }
      } catch (_) {
        // Falls through to the durable queue.
      }
    }

    _append(mutation);
    return OfflineWriteResult(
      status: OfflineWriteStatus.queued,
      mutationId: mutation.id,
    );
  }

  Future<void> flush() async {
    if (_flushing || !_canAttemptRemoteWrite) return;
    _flushing = true;
    try {
      final pending = _readQueue();
      if (pending.isEmpty) return;
      final remaining = <OfflineMutation>[];
      for (final mutation in pending) {
        try {
          final synced = await _sync(mutation);
          if (!synced) {
            remaining.add(mutation.copyWith(
              attempts: mutation.attempts + 1,
              lastError: 'remote_write_rejected',
            ));
          }
        } catch (error) {
          remaining.add(mutation.copyWith(
            attempts: mutation.attempts + 1,
            lastError: '$error',
          ));
        }
      }
      _writeQueue(remaining);
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _sync(OfflineMutation mutation) async {
    switch (mutation.type) {
      case 'club_tactical_data.upsert':
        return _syncTacticalData(mutation);
      default:
        return false;
    }
  }

  Future<bool> _syncTacticalData(OfflineMutation mutation) {
    final payload = mutation.payload;
    return ClubAccessService.saveTacticalData(
      type: payload['type'] as String? ?? 'note',
      title: payload['title'] as String? ?? 'Registro sin titulo',
      content: Map<String, dynamic>.from(payload['content'] as Map? ?? const {}),
      relatedLudTeamId: (payload['relatedLudTeamId'] as num?)?.toInt(),
      categoryId: payload['categoryId'] as String?,
    );
  }

  bool get _canAttemptRemoteWrite =>
      html.window.navigator.onLine == true &&
      SupabaseAuthService.isConfigured &&
      SupabaseAuthService.currentSession != null;

  void _append(OfflineMutation mutation) {
    final next = [..._readQueue(), mutation];
    _writeQueue(next);
  }

  List<OfflineMutation> _readQueue() {
    final raw = html.window.localStorage[_storageKey];
    if (raw == null || raw.isEmpty) return [];
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      return data
          .whereType<Map>()
          .map((item) => OfflineMutation.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .where((item) => item.id.isNotEmpty && item.type.isNotEmpty)
          .toList();
    } catch (_) {
      html.window.localStorage.remove(_storageKey);
      return [];
    }
  }

  void _writeQueue(List<OfflineMutation> queue) {
    html.window.localStorage[_storageKey] = jsonEncode(
      queue.map((item) => item.toJson()).toList(),
    );
    _queueController.add(queue);
  }
}
