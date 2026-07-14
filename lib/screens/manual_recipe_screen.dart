import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../services/recipe_extractor.dart';

/// Rezept komplett selbst eintippen — funktioniert immer ohne API-Schlüssel.
class ManualRecipeScreen extends StatefulWidget {
  const ManualRecipeScreen({
    super.key,
    required this.repository,
    required this.extractor,
  });

  final AppRepository repository;
  final RecipeExtractor extractor;

  @override
  State<ManualRecipeScreen> createState() => _ManualRecipeScreenState();
}

class _ManualRecipeScreenState extends State<ManualRecipeScreen> {
  final _title = TextEditingController();
  final _ingredients = TextEditingController();
  final _steps = TextEditingController();
  final _servings = TextEditingController();
  bool _alsoShopping = true;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _ingredients.dispose();
    _steps.dispose();
    _servings.dispose();
    super.dispose();
  }

  List<String> _lines(String value) => value
      .split(RegExp(r'[\n\r]+'))
      .map((e) => e.replaceFirst(RegExp(r'^[-•*\d.)\s]+'), '').trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (_title.text.trim().isEmpty &&
        _ingredients.text.trim().isEmpty &&
        _steps.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens Titel, Zutaten oder Schritte eingeben.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final recipe = widget.extractor.buildManualRecipe(
        title: _title.text,
        ingredients: _lines(_ingredients.text),
        steps: _lines(_steps.text),
        servings: _servings.text,
      );
      await widget.repository.saveRecipe(recipe);
      if (_alsoShopping) {
        await widget.repository.addRecipeToShopping(recipe);
      }
      if (!mounted) return;
      Navigator.pop(context, recipe);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rezept selbst tippen')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Hier brauchst du keinen API-Schlüssel. '
            'Einfach eintippen und speichern.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Titel',
              hintText: 'z. B. Omas Apfelkuchen',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _servings,
            decoration: const InputDecoration(
              labelText: 'Portionen (optional)',
              hintText: 'z. B. 4 Portionen',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ingredients,
            minLines: 5,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Zutaten (eine Zeile pro Zutat)',
              alignLabelWithHint: true,
              hintText: '300 g Mehl\n2 Eier\n100 g Zucker',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _steps,
            minLines: 5,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Schritte (eine Zeile pro Schritt)',
              alignLabelWithHint: true,
              hintText: 'Mehl sieben.\nEier unterrühren.\nBacken.',
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zutaten gleich auf die Einkaufsliste'),
            value: _alsoShopping,
            onChanged: _saving
                ? null
                : (value) => setState(() => _alsoShopping = value),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Speichern…' : 'Rezept speichern'),
          ),
        ],
      ),
    );
  }
}
