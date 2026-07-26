import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Liest sichtbaren Text aus einer PDF-Datei.
class PdfTextReader {
  static const maxBytes = 15000000; // 15 MB

  /// Extrahiert den Text aller Seiten.
  static String extractText(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw Exception('Die PDF-Datei ist leer.');
    }
    if (bytes.length > maxBytes) {
      throw Exception(
        'Die PDF ist zu groß (max. 15 MB). '
        'Bitte eine kleinere Datei wählen.',
      );
    }

    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final text = PdfTextExtractor(document).extractText().trim();
      return text;
    } catch (e) {
      throw Exception(
        'PDF-Text konnte nicht gelesen werden. '
        'Die Datei ist evtl. nur ein Scan ohne Text '
        'oder beschädigt.',
      );
    } finally {
      document?.dispose();
    }
  }
}
