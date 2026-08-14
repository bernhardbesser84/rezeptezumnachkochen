import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/models/recipe.dart';
import 'package:rezept_nachkochen/services/recipe_share.dart';
import 'package:rezept_nachkochen/services/serving_scaler.dart';

void main() {
  test('liest Portionszahl aus Text', () {
    expect(ServingScaler.parseCount('2 Portionen'), 2);
    expect(ServingScaler.parseCount('für 4 Personen'), 4);
    expect(ServingScaler.parseCount('2–4 Portionen'), 2);
    expect(ServingScaler.parseCount(null), 2);
  });

  test('rechnet Gramm-Mengen um', () {
    expect(
      ServingScaler.scaleLine('600 g Kartoffeln', 2),
      '1200 g Kartoffeln',
    );
    expect(
      ServingScaler.scaleLine('300 g Hähnchenbrust', 0.5),
      '150 g Hähnchenbrust',
    );
  });

  test('lässt Zeilen ohne Menge unverändert', () {
    expect(
      ServingScaler.scaleLine('Salz, Pfeffer nach Geschmack', 3),
      'Salz, Pfeffer nach Geschmack',
    );
  });

  test('skaliert Brüche', () {
    expect(ServingScaler.scaleLine('1/2 TL Salz', 2), '1 TL Salz');
    expect(ServingScaler.scaleLine('1 EL Öl', 0.5), '1/2 EL Öl');
  });

  test('Share-Text enthält Titel und Zutaten', () {
    final recipe = Recipe(
      id: '1',
      title: 'Dönerteller zum Abnehmen',
      ingredients: const ['600 g Kartoffeln', '300 g Hähnchenbrust'],
      steps: const ['Kartoffeln schneiden', 'Hähnchen braten'],
      sourceUrl: 'https://www.facebook.com/reel/1',
      createdAt: DateTime(2026, 1, 1),
      servings: '2 Portionen',
    );
    final text = formatRecipeShareText(recipe, portions: 4);
    expect(text, contains('Dönerteller zum Abnehmen'));
    expect(text, contains('4 Portionen'));
    expect(text, contains('1200 g Kartoffeln'));
    expect(text, contains('Video: https://www.facebook.com/reel/1'));
  });

  test('Rezept speichert imageUrl in JSON', () {
    final recipe = Recipe(
      id: '2',
      title: 'Pasta',
      ingredients: const ['200 g Nudeln'],
      steps: const ['Kochen'],
      sourceUrl: '',
      createdAt: DateTime(2026, 1, 1),
      imageUrl: 'https://example.com/pasta.jpg',
    );
    final json = recipe.toJson();
    expect(json['imageUrl'], 'https://example.com/pasta.jpg');
    expect(Recipe.fromJson(json).imageUrl, 'https://example.com/pasta.jpg');
  });
}
