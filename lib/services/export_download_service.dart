// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Triggers a browser download for text content generated with
/// `export_text_service.dart`. Kept tiny and separate from the pure
/// formatters so those stay unit-testable without a web/dart:html import.
class ExportDownloadService {
  const ExportDownloadService._();

  static void downloadText(String fileName, String content) {
    final blob = html.Blob([content], 'text/plain;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..download = fileName
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}
