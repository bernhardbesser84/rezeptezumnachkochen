import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/services/pdf_text_reader.dart';
import 'package:rezept_nachkochen/services/recipe_extractor.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

Uint8List _buildSamplePdf() {
  final document = PdfDocument();
  final page = document.pages.add();
  page.graphics.drawString(
    'Marry Me Salmon\n\n'
    'Ingredients:\n'
    '1.5 lbs Salmon\n'
    '2 tablespoon olive oil\n'
    '1 cup cream\n\n'
    'Instructions:\n'
    '1. Season the salmon.\n'
    '2. Sear in a hot pan.\n'
    '3. Add creamy tomato sauce.',
    PdfStandardFont(PdfFontFamily.helvetica, 12),
    bounds: const Rect.fromLTWH(20, 20, 500, 700),
  );
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

void main() {
  test('PdfTextReader liest Text aus einer Text-PDF', () {
    final text = PdfTextReader.extractText(_buildSamplePdf());
    expect(text.toLowerCase(), contains('salmon'));
    expect(text.toLowerCase(), contains('ingredients'));
  });

  test('extractRecipeFromPdf ohne Bytes wirft Fehler', () async {
    final extractor = RecipeExtractor();
    expect(
      () => extractor.extractRecipeFromPdf(
        pdfBytes: Uint8List(0),
        apiKey: 'test',
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('PDF'),
        ),
      ),
    );
  });
}
