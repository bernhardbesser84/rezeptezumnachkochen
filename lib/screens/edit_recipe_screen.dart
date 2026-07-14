import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recipe.dart';
import '../services/app_repository.dart';

/// Alle Rezeptfelder nachträglich ändern und speichern.
class EditRecipeScreen extends StatefulWidget {
  const EditRecipeScreen({
    super.key,
    required this.recipe,
    required this.repository,
  });

  final Recipe recipe;
  final AppRepository repository;

  @override
  State<EditRecipeScreen> createState() => _EditRecipeScreenState();
}

class _EditRecipeScreenState extends State<EditRecipeScreen> {
  late final TextEditingController _title;
  late final TextEditingController _servings;
  late final TextEditingController _prepTime;
  late final TextEditingController _ingredients;
  late final TextEditingController _steps;
  late final TextEditingController _notes;
  late final TextEditingController _sourceUrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    _title = TextEditingController(text: r.title);
    _servings = TextEditingController(text: r.servings ?? '');
    _prepTime = TextEditingController(
      text: r.prepTimeMinutes?.toString() ?? '',
    );
    _ingredients = TextEditingController(text: r.ingredients.join('\n'));
    _steps = TextEditingController(text: r.steps.join('\n'));
    _notes = TextEditingController(text: r.notes ?? '');
    _sourceUrl = TextEditingController(text: r.sourceUrl);
  }

  @override
  void dispose() {
    _title.dispose();
    _servings.dispose();
    _prepTime.dispose();
    _ingredients.dispose();
    _steps.dispose();
    _notes.dispose();
    _sourceUrl.dispose();
    super.dispose();
  }

  List<String> _lines(String value) => value
      .split(RegExp(r'[\n\r]+'))
      .map((e) => e.replaceFirst(RegExp(r'^[-•*]\s+'), '').trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Titel eingeben.')),
      );
      return;
    }

    final ingredients = _lines(_ingredients.text);
    final steps = _lines(_steps.text);
    if (ingredients.isEmpty && steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens Zutaten oder Schritte eintragen.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final servings = _servings.text.trim();
      final notes = _notes.text.trim();
      final sourceUrl = _sourceUrl.text.trim();
      final prepRaw = _prepTime.text.trim();
      final prep = prepRaw.isEmpty ? null : int.tryParse(prepRaw);

      final updated = Recipe(
        id: widget.recipe.id,
        title: title,
        ingredients: ingredients.isEmpty
            ? ['Zutaten noch ergänzen']
            : ingredients,
        steps: steps.isEmpty ? ['Schritte noch ergänzen'] : steps,
        sourceUrl: sourceUrl,
        createdAt: widget.recipe.createdAt,
        servings: servings.isEmpty ? null : servings,
        prepTimeMinutes: prep,
        notes: notes.isEmpty ? null : notes,
      );

      await widget.repository.saveRecipe(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rezept gespeichert.')),
      );
      Navigator.pop(context, updated);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezept bearbeiten'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Speichern'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Hier kannst du alles ändern: Name, Zutaten, Schritte und mehr.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name des Gerichts',
              hintText: 'z. B. Cremige Tomaten-Pasta',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _servings,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Portionen',
              hintText: 'z. B. 4 Portionen',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _prepTime,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Zeit in Minuten',
              hintText: 'z. B. 30',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _sourceUrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Video-Link (optional)',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ingredients,
            minLines: 5,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Zutaten (eine Zeile pro Zutat)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _steps,
            minLines: 5,
            maxLines: 14,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Schritte (eine Zeile pro Schritt)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notizen (optional)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_saving ? 'Speichern…' : 'Änderungen speichern'),
          ),
        ],
      ),
    );
  }
}
