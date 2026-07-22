import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/services/recipe_extractor.dart';

void main() {
  test('extractRecipeFromImages ohne Bilder wirft verständlichen Fehler', () async {
    final extractor = RecipeExtractor();
    expect(
      () => extractor.extractRecipeFromImages(
        images: const [],
        apiKey: 'test',
      ),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('mindestens ein Foto'),
        ),
      ),
    );
  });

  test('RecipeImageInput speichert Bytes und Mime', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    const mime = 'image/jpeg';
    final image = RecipeImageInput(bytes: bytes, mimeType: mime);
    expect(image.bytes, bytes);
    expect(image.mimeType, mime);
  });
}
