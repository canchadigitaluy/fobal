import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';

/// Preview-before-you-share dialog reused by every text export (citación,
/// sesión, asistencia): shows the generated text, lets the coach copy it or
/// download it as .txt. No dart:html here — [onDownload] is the caller's own
/// download call, so this widget stays platform-agnostic.
Future<void> showExportPreviewDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String fileName,
  required void Function(String fileName, String content) onDownload,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ExportPreviewDialog(
      title: title,
      content: content,
      fileName: fileName,
      onDownload: onDownload,
    ),
  );
}

class _ExportPreviewDialog extends StatelessWidget {
  final String title;
  final String content;
  final String fileName;
  final void Function(String fileName, String content) onDownload;

  const _ExportPreviewDialog({
    required this.title,
    required this.content,
    required this.fileName,
    required this.onDownload,
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Texto copiado al portapapeles.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Revisá el texto antes de compartirlo o descargarlo.',
              style: TextStyle(color: CX.muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 360),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CX.panel2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: CX.line),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  content,
                  style: const TextStyle(fontSize: 12.5, height: 1.45),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        OutlinedButton.icon(
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: const Text('Copiar texto'),
        ),
        FilledButton.icon(
          onPressed: () {
            onDownload(fileName, content);
            Navigator.pop(context);
          },
          icon: const Icon(Icons.download_outlined, size: 16),
          label: const Text('Descargar .txt'),
        ),
      ],
    );
  }
}
