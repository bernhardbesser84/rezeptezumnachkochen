import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/services/recipe_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rezept_nachkochen/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App startet und zeigt Starttitel', (tester) async {
    await tester.pumpWidget(const RezeptNachkochenApp());
    // Speicher und Demo-Rezept laden
    await tester.pumpAndSettle();

    expect(find.text('Rezept Nachkochen'), findsWidgets);
    expect(find.textContaining('Einkaufsliste'), findsWidgets);
  });

  test('Lokale Auswertung erkennt Zutaten und Schritte', () async {
    final extractor = RecipeExtractor();
    final recipe = await extractor.extractRecipe(
      sourceText: '''
Titel: Schnelle Rührei-Bowl
Zutaten:
- 3 Eier
- 1 Handvoll Spinat
- 1 EL Butter
Zubereitung:
1. Butter in der Pfanne erhitzen.
2. Eier verquirlen und braten.
3. Spinat unterheben und servieren.
''',
    );

    expect(recipe.title.toLowerCase(), contains('rührei'));
    expect(recipe.ingredients.length, greaterThanOrEqualTo(2));
    expect(recipe.steps.length, greaterThanOrEqualTo(2));
  });

  test('Beispielrezept ist vollständig', () {
    final demo = RecipeExtractor().buildDemoRecipe();
    expect(demo.title, isNotEmpty);
    expect(demo.ingredients, isNotEmpty);
    expect(demo.steps, isNotEmpty);
  });
}
