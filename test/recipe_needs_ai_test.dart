import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/models/recipe.dart';

void main() {
  test('Placeholder-Schritte und KI-Fehler-Notizen brauchen Nachholen', () {
    final failed = Recipe(
      id: '1',
      title: 'Test',
      ingredients: const ['Mehl'],
      steps: const [
        'Öffne das Originalvideo und schaue die Zubereitung noch einmal an.',
        'Trage danach die Schritte manuell nach.',
      ],
      sourceUrl: 'https://example.com',
      createdAt: DateTime(2026, 1, 1),
      notes:
          'KI war gerade nicht nutzbar (Gemini-Guthaben / Kontingent ist leer (429)).',
    );
    expect(failed.needsAiEnrichment, isTrue);

    final ok = Recipe(
      id: '2',
      title: 'Pasta',
      ingredients: const ['Nudeln', 'Sauce'],
      steps: const ['Wasser kochen', 'Nudeln garen', 'Sauce mischen'],
      sourceUrl: '',
      createdAt: DateTime(2026, 1, 1),
    );
    expect(ok.needsAiEnrichment, isFalse);
  });
}
