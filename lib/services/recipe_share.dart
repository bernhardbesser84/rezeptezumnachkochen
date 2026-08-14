import '../models/recipe.dart';
import 'serving_scaler.dart';

/// Baut einen einfachen Text zum Teilen eines Rezepts.
String formatRecipeShareText(
  Recipe recipe, {
  int? portions,
}) {
  final base = ServingScaler.parseCount(recipe.servings);
  final wanted = portions ?? base;
  final ingredients = ServingScaler.scaleAll(
    recipe.ingredients,
    fromServings: base,
    toServings: wanted,
  );

  final buffer = StringBuffer()
    ..writeln(recipe.title)
    ..writeln(ServingScaler.formatServings(wanted));
  if (recipe.prepTimeMinutes != null) {
    buffer.writeln('${recipe.prepTimeMinutes} Minuten');
  }
  buffer
    ..writeln()
    ..writeln('Zutaten:')
    ..writeln(ingredients.map((e) => '• $e').join('\n'))
    ..writeln()
    ..writeln('Zubereitung:');
  for (var i = 0; i < recipe.steps.length; i++) {
    buffer.writeln('${i + 1}. ${recipe.steps[i]}');
  }
  if (recipe.sourceUrl.trim().isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('Video: ${recipe.sourceUrl.trim()}');
  }
  buffer
    ..writeln()
    ..writeln('Geteilt aus Rezept Nachkochen');
  return buffer.toString().trim();
}
