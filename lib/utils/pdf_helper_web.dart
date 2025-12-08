// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

void downloadPdfWeb(Uint8List bytes, String filename) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..target = 'blank'
    ..download = filename;
  anchor.click();
  html.Url.revokeObjectUrl(url);
}
