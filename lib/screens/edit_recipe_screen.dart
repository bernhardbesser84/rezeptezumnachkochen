import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recipe.dart';
import '../services/app_repository.dart';
import '../services/recipe_category_service.dart';
import '../services/recipe_extractor.dart';
import '../services/video_link_fetcher.dart';
import '../theme/app_theme.dart';
import '../widgets/recipe_category_picker.dart';

/// Alle Rezeptfelder nachträglich ändern und speichern.
class EditRecipeScreen extends StatefulWidget {
  const EditRecipeScreen({
    super.key,
    required this.recipe,
    required this.repository,
    required this.extractor,
    this.autoStartAiRetry = false,
  });

  final Recipe recipe;
  final AppRepository repository;
  final RecipeExtractor extractor;
  final bool autoStartAiRetry;

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
  List<String> _categories = const [];
  bool _saving = false;
  bool _retryingAi = false;
  String? _aiStatus;

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
    _categories = List<String>.from(r.categories);
    if (widget.autoStartAiRetry) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _retryAiEnrichment();
      });
    }
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

  Recipe _recipeFromForm() {
    final title = _title.text.trim();
    final ingredients = _lines(_ingredients.text);
    final steps = _lines(_steps.text);
    final servings = _servings.text.trim();
    final notes = _notes.text.trim();
    final sourceUrl = _sourceUrl.text.trim();
    final prepRaw = _prepTime.text.trim();
    final prep = prepRaw.isEmpty ? null : int.tryParse(prepRaw);

    return Recipe(
      id: widget.recipe.id,
      title: title.isEmpty ? widget.recipe.title : title,
      ingredients: ingredients.isEmpty
          ? ['Zutaten noch ergänzen']
          : ingredients,
      steps: steps.isEmpty ? ['Schritte noch ergänzen'] : steps,
      sourceUrl: sourceUrl,
      createdAt: widget.recipe.createdAt,
      servings: servings.isEmpty ? null : servings,
      prepTimeMinutes: prep,
      notes: notes.isEmpty ? null : notes,
      categories: _categories,
    );
  }

  Future<void> _pickCategories() async {
    final existingRecipes =
        await widget.repository.loadRecipes(pullRemote: false);
    if (!mounted) return;
    final selected = await showRecipeCategoryPicker(
      context: context,
      title: 'Kategorien bearbeiten',
      initialSelection: _categories,
      suggestedCategories: RecipeCategoryService.suggestForRecipe(
        _recipeFromForm(),
      ),
      existingCategories: RecipeCategoryService.collectFromRecipes(
        existingRecipes,
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _categories = selected);
  }

  Future<void> _save({Recipe? recipe, String successMessage = 'Rezept gespeichert.'}) async {
    final draft = recipe ?? _recipeFromForm();
    if (draft.title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen Titel eingeben.')),
      );
      return;
    }
    if (draft.ingredients.isEmpty && draft.steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte mindestens Zutaten oder Schritte eintragen.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.repository.saveRecipe(draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      Navigator.pop(context, draft);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Speichern fehlgeschlagen: $message')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _retryAiEnrichment() async {
    final url = _sourceUrl.text.trim().isNotEmpty
        ? _sourceUrl.text.trim()
        : widget.recipe.sourceUrl.trim();

    if (url.isEmpty &&
        _ingredients.text.trim().isEmpty &&
        _notes.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte zuerst einen Video-Link eintragen, '
            'dann „KI-Auswertung nachholen“ tippen.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _retryingAi = true;
      _aiStatus = 'KI wertet erneut aus…';
    });

    try {
      final provider = await widget.repository.storage.getAiProvider();
      final apiKey = await widget.repository.storage.getApiKey();
      if (apiKey == null || apiKey.trim().isEmpty) {
        throw Exception(
          'Kein KI-Schlüssel gefunden. '
          'Bitte unter Einstellungen prüfen.',
        );
      }

      Uint8List? videoBytes;
      String? videoMimeType;
      String? videoFileName;
      if (url.isNotEmpty) {
        setState(() => _aiStatus = 'Video vom Link laden…');
        try {
          final fetched = await VideoLinkFetcher().fetchFromUrl(url);
          videoBytes = fetched.bytes;
          videoMimeType = fetched.mimeType;
          videoFileName = fetched.fileName;
          setState(() => _aiStatus = 'Video geladen — KI wertet aus…');
        } catch (_) {
          setState(
            () => _aiStatus =
                'Video nicht ladbar — KI nutzt Link/Text…',
          );
        }
      }

      final sourceText = [
        if (url.isNotEmpty) url,
        if (_title.text.trim().isNotEmpty) 'Titel: ${_title.text.trim()}',
        if (_ingredients.text.trim().isNotEmpty)
          'Bisherige Zutaten:\n${_ingredients.text.trim()}',
        if (_notes.text.trim().isNotEmpty) _notes.text.trim(),
      ].join('\n\n');

      final result = await widget.extractor.extractRecipe(
        sourceText: sourceText,
        sourceUrl: url.isEmpty ? null : url,
        apiKey: apiKey,
        provider: provider,
        useAi: true,
        videoBytes: videoBytes,
        videoMimeType: videoMimeType,
        videoFileName: videoFileName,
      );

      if (result.notes?.contains('KI war gerade nicht nutzbar') == true) {
        final reason = result.notes!
            .split('\n')
            .first
            .replaceFirst('KI war gerade nicht nutzbar (', '')
            .replaceFirst(').', '');
        throw Exception(reason);
      }

      final enriched = result.copyWith(
        id: widget.recipe.id,
        createdAt: widget.recipe.createdAt,
        sourceUrl: url.isNotEmpty ? url : result.sourceUrl,
      );

      setState(() {
        _title.text = enriched.title;
        _servings.text = enriched.servings ?? '';
        _prepTime.text = enriched.prepTimeMinutes?.toString() ?? '';
        _ingredients.text = enriched.ingredients.join('\n');
        _steps.text = enriched.steps.join('\n');
        _notes.text = enriched.notes ?? '';
        if (enriched.sourceUrl.isNotEmpty) {
          _sourceUrl.text = enriched.sourceUrl;
        }
        _aiStatus = 'KI-Auswertung fertig — speichern…';
      });

      await _save(
        recipe: enriched,
        successMessage: 'KI-Auswertung nachgeholt und gespeichert.',
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() => _aiStatus = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nachholen fehlgeschlagen: $message')),
      );
    } finally {
      if (mounted) setState(() => _retryingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || _retryingAi;
    final showRetryHint = widget.recipe.needsAiEnrichment;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rezept bearbeiten'),
        actions: [
          TextButton(
            onPressed: busy ? null : () => _save(),
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
          if (showRetryHint) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.3),
                ),
              ),
              child: const Text(
                'Die Zubereitung fehlt noch oder die KI war beim Anlegen '
                'nicht erreichbar (z. B. Kontingent leer). '
                'Du kannst die Auswertung jetzt nachholen.',
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: busy ? null : _retryAiEnrichment,
            icon: _retryingAi
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(
              _retryingAi
                  ? 'KI wertet aus…'
                  : 'KI-Auswertung nachholen',
            ),
          ),
          if (_aiStatus != null) ...[
            const SizedBox(height: 8),
            Text(_aiStatus!),
          ],
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
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Kategorien'),
            subtitle: _categories.isEmpty
                ? const Text('Noch keine Kategorie gewählt')
                : Text(_categories.join(' · ')),
            trailing: const Icon(Icons.edit_outlined),
            onTap: busy ? null : _pickCategories,
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
            onPressed: busy ? null : () => _save(),
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
