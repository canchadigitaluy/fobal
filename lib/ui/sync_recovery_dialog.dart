import 'dart:convert';

import 'package:flutter/material.dart';

import '../data/cantera_data.dart';
import '../services/club_sync_service.dart';
import '../services/export_download_service.dart';
import '../services/sync_conflict_service.dart';
import 'ui_kit.dart';

const _amber = Color(0xFFD99A16);
const _muted = Color(0xFF68746F);
const _faint = Color(0xFF8D9893);

BoxDecoration _recoveryPanel() => BoxDecoration(
  color: const Color(0xFFF8FAF9),
  borderRadius: BorderRadius.circular(12),
  border: Border.all(color: _amber.withValues(alpha: .55)),
);

Future<bool?> showSyncRecoveryDialog(
  BuildContext context, {
  required CanteraClub currentClub,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _SyncRecoveryDialog(currentClub: currentClub),
  );
}

class _SyncRecoveryDialog extends StatefulWidget {
  final CanteraClub currentClub;
  const _SyncRecoveryDialog({required this.currentClub});

  @override
  State<_SyncRecoveryDialog> createState() => _SyncRecoveryDialogState();
}

class _SyncRecoveryDialogState extends State<_SyncRecoveryDialog> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final conflicts = ClubSyncService.conflicts(widget.currentClub.id);
    final error = ClubSyncService.syncError(widget.currentClub.id);
    return AlertDialog(
      title: const Text('Revisar sincronización'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: _recoveryPanel(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(error),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => ExportDownloadService.downloadText(
                          'fobal-${widget.currentClub.id}-copia-local.json',
                          jsonEncode(widget.currentClub.toJson()),
                        ),
                        icon: const Icon(Icons.download_outlined, size: 17),
                        label: const Text('Descargar copia local'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (conflicts.isEmpty && error == null)
                const EmptyStatePanel(
                  icon: Icons.cloud_done_outlined,
                  title: 'No hay cambios pendientes de revisión',
                  message:
                      'La copia local y la versión guardada están alineadas.',
                ),
              for (final snapshot in conflicts) ...[
                _ConflictCard(
                  snapshot: snapshot,
                  currentClub: widget.currentClub,
                  busy: _busy,
                  onDiscard: () {
                    ClubSyncService.discardConflict(
                      widget.currentClub.id,
                      snapshot.id,
                    );
                    setState(() {});
                  },
                  onDownload: () => ExportDownloadService.downloadText(
                    'fobal-${widget.currentClub.id}-${snapshot.id}.json',
                    snapshot.rawClub,
                  ),
                  onRestore: () async {
                    setState(() => _busy = true);
                    final ok = await ClubSyncService.restoreConflict(snapshot);
                    if (!mounted) return;
                    setState(() => _busy = false);
                    if (ok) Navigator.pop(context, true);
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No se pudo restaurar todavía. Tu copia sigue guardada.',
                          ),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final SyncConflictSnapshot snapshot;
  final CanteraClub currentClub;
  final bool busy;
  final VoidCallback onDiscard;
  final VoidCallback onDownload;
  final VoidCallback onRestore;

  const _ConflictCard({
    required this.snapshot,
    required this.currentClub,
    required this.busy,
    required this.onDiscard,
    required this.onDownload,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final local = snapshot.parseClub();
    final diff = local == null
        ? null
        : summarizeClubDifferences(local, currentClub);
    final created = DateTime.tryParse(snapshot.createdAt)?.toLocal();
    final when = created == null
        ? 'Fecha desconocida'
        : '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')} '
              '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _recoveryPanel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Copia local · $when',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            diff == null
                ? 'La copia no se pudo comparar, pero puede descargarse.'
                : '${diff.players} jugadores · ${diff.sessions} sesiones · '
                      '${diff.results} resultados · ${diff.attendanceRecords} asistencias difieren',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onDownload,
                icon: const Icon(Icons.download_outlined, size: 17),
                label: const Text('Descargar copia'),
              ),
              TextButton(
                onPressed: busy ? null : onDiscard,
                child: const Text('Conservar versión actual'),
              ),
              FilledButton.icon(
                onPressed: busy || local == null ? null : onRestore,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore, size: 17),
                label: const Text('Reemplazar con mi copia'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Reemplazar conserva esta copia completa y sustituye la versión actual del club.',
            style: TextStyle(color: _faint, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}
