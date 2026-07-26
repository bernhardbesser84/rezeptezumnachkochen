import 'package:flutter_test/flutter_test.dart';
import 'package:rezept_nachkochen/services/recipe_extractor.dart';

void main() {
  test('KI-Regeln verlangen Deutsch und metrische Einheiten', () {
    final rules = RecipeExtractor.languageAndUnitsRules;

    expect(rules, contains('Deutsche'));
    expect(rules.toLowerCase(), contains('übersetzen'));
    expect(rules, contains('g, kg, ml, l, EL, TL'));
    expect(rules, contains('cup'));
    expect(rules, contains('oz'));
    expect(rules, contains('°F'));
    expect(rules, contains('°C'));
  });
}
