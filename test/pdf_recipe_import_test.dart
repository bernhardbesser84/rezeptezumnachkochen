import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/services/pdf_text_normalizer.dart';
import 'package:rezept_nachkochen/services/pdf_text_reader.dart';
import 'package:rezept_nachkochen/services/recipe_extractor.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Syncfusion-Ausgabe ähnlich der Marry-Me-PDF (Zahlen/Einheiten auf Extra-Zeilen).
const _fragmentedPdfText = '''
Ingredients
Salmon
1.5
lbs
Salmon select cuts
3
tablespoon
sun-dried tomato oil
2
tablespoon
olive oil
½
tablespoon
smoked paprika
¾
teaspoon
salt
1
teaspoon
Old Bay
12
oz
gluten free penne pasta
Instructions
1. Sear salmon.
''';

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
  test('PdfTextNormalizer fügt zerstückelte Mengen zusammen', () {
    final normalized = PdfTextNormalizer.normalize(_fragmentedPdfText);
    expect(normalized, contains('1.5 lbs Salmon select cuts'));
    expect(normalized, contains('1/2 tablespoon smoked paprika'));
    expect(normalized, contains('3/4 teaspoon salt'));
    expect(normalized, contains('12 oz gluten free penne pasta'));
  });

  test('PdfTextNormalizer extrahiert Zutaten-Block', () {
    final normalized = PdfTextNormalizer.normalize(_fragmentedPdfText);
    final block = PdfTextNormalizer.extractIngredientsSection(normalized);
    expect(block, isNotNull);
    expect(block!.toLowerCase(), contains('salmon select cuts'));
    expect(block.toLowerCase(), isNot(contains('sear salmon')));
  });

  test('IngredientQuantityNormalizer repariert /2 und /4', () {
    expect(
      IngredientQuantityNormalizer.normalize('/2 EL geräuchertes Paprikapulver'),
      '1/2 EL geräuchertes Paprikapulver',
    );
    expect(
      IngredientQuantityNormalizer.normalize('/4 TL Salz'),
      '1/4 TL Salz',
    );
    expect(
      IngredientQuantityNormalizer.normalize('680g Lachsfilet'),
      '680 g Lachsfilet',
    );
  });

  test('KI-JSON: Zutaten-Mengen werden nachbearbeitet', () {
    final extractor = RecipeExtractor();
    final recipe = extractor.parseAiRecipeJson('''
{
  "title": "Lachs mit Pasta",
  "ingredients": [
    "/2 EL Paprika",
    "g Lachsfilet",
    "EL Butter"
  ],
  "steps": ["Kochen"]
}
''');
    expect(recipe.ingredients.first, '1/2 EL Paprika');
  });

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

  test('Marry Me PDF: bereinigter Text enthält zusammengefügte Mengen', () {
    final path =
        '/home/ubuntu/.cursor/projects/workspace/uploads/Marry_Me_Salmon_-_Golden_Grace_Kitchen_8a88.pdf';
    if (!File(path).existsSync()) return;

    final raw = PdfTextReader.extractText(
      Uint8List.fromList(File(path).readAsBytesSync()),
    );
    final normalized = PdfTextNormalizer.normalize(raw);
    expect(normalized, contains('1.5 lbs Salmon select cuts'));
    expect(normalized, contains('1/2 tablespoon smoked paprika'));
    expect(normalized, contains('2 tablespoon butter'));
    expect(normalized, contains('1 cup parmesan cheese'));

    final block = PdfTextNormalizer.extractIngredientsSection(normalized);
    expect(block, isNotNull);
    expect(block!.toLowerCase(), contains('chicken broth'));
    expect(block.toLowerCase(), contains('1.5 lbs salmon'));
    expect(block.toLowerCase(), isNot(contains('refrigerate leftovers')));
    expect(block.toLowerCase(), isNot(contains('coat the salmon')));
  });
}
