import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/recipe_extractor.dart';
import '../services/recipe_storage.dart';
import '../theme/app_theme.dart';

class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({
    super.key,
    required this.storage,
    required this.extractor,
    this.initialSharedText,
  });

  final RecipeStorage storage;
  final RecipeExtractor extractor;
  final String? initialSharedText;

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  late final TextEditingController _controller;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialSharedText ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _createRecipe() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final apiKey = await widget.storage.getApiKey();
      final text = _controller.text.trim();
      final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
      final url = urlMatch?.group(0);

      final recipe = await widget.extractor.extractRecipe(
        sourceText: text,
        sourceUrl: url,
        apiKey: apiKey,
      );

      await widget.storage.upsertRecipe(recipe);
      if (!mounted) return;
      Navigator.pop(context, recipe);
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rezept hinzufügen')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.seed.withValues(alpha: 0.12)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'So geht’s ganz einfach',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  '1. Öffne ein Rezeptvideo bei Facebook, Instagram, TikTok '
                  'oder YouTube.\n'
                  '2. Tippe auf Teilen und wähle „Rezept Nachkochen“.\n'
                  '3. Oder kopiere den Link / die Videobeschreibung und füge '
                  'sie hier ein.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Link oder Rezepttext',
              hintText:
                  'https://... oder Beschreibung aus dem Video einfügen',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          FilledButton.icon(
            onPressed: _loading ? null : _createRecipe,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _loading ? 'Rezept wird erstellt…' : 'Anleitung erstellen',
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tipp: Mit einem OpenAI API-Schlüssel in den Einstellungen '
            'werden Zutaten und Schritte deutlich besser erkannt.',
          ),
        ],
      ),
    );
  }
}

/// Rückgabewert bleibt Recipe, damit die Home-Seite direkt öffnen kann.
typedef AddedRecipe = Recipe;
