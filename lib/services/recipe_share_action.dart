import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/recipe.dart';
import 'recipe_share.dart';

/// Teilt ein Rezept über das System-Menü (oder kopiert den Text).
Future<void> shareRecipeToApps(
  BuildContext context,
  Recipe recipe, {
  int? portions,
}) async {
  final text = formatRecipeShareText(recipe, portions: portions);
  try {
    await SharePlus.instance.share(
      ShareParams(text: text, subject: recipe.title),
    );
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Rezepttext wurde kopiert — du kannst ihn jetzt einfügen.'),
      ),
    );
  }
}
