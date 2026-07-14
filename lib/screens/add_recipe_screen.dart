import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_repository.dart';
import '../services/recipe_extractor.dart';
import '../theme/app_theme.dart';
import '../utils/platform_hints.dart';
import 'manual_recipe_screen.dart';
import 'photo_recipe_screen.dart';

class AddRecipeScreen extends StatefulWidget {
  const AddRecipeScreen({
    super.key,
    required this.repository,
    required this.extractor,
    this.initialSharedText,
  });

  final AppRepository repository;
  final RecipeExtractor extractor;
  final String? initialSharedText;

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  late final TextEditingController _controller;
  bool _loading = false;
  bool _alsoShopping = true;
  bool _useAi = true;
  bool _hasApiKey = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialSharedText ?? '');
    _loadKeyState();
  }

  Future<void> _loadKeyState() async {
    final key = await widget.repository.storage.getApiKey();
    if (!mounted) return;
    setState(() {
      _hasApiKey = key != null && key.trim().isNotEmpty;
      // Ohne Schlüssel: immer ohne KI erstellen.
      _useAi = _hasApiKey;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zwischenablage ist leer.')),
      );
      return;
    }
    setState(() {
      _controller.text = text;
      _controller.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  Future<void> _createRecipe() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });

    try {
      final provider = await widget.repository.storage.getAiProvider();
      final apiKey = await widget.repository.storage.getApiKey();
      final text = _controller.text.trim();
      final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
      final url = urlMatch?.group(0);

      final recipe = await widget.extractor.extractRecipe(
        sourceText: text,
        sourceUrl: url,
        apiKey: apiKey,
        provider: provider,
        useAi: _useAi,
      );

      await widget.repository.saveRecipe(recipe);
      if (_alsoShopping) {
        await widget.repository.addRecipeToShopping(recipe);
      }
      if (!mounted) return;

      final usedFallback = recipe.notes?.contains('KI war gerade nicht nutzbar') ==
          true;
      if (usedFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'KI nicht erreichbar — Rezept trotzdem ohne KI angelegt. '
              'Du kannst es danach ergänzen.',
            ),
          ),
        );
      }
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

  Future<void> _openManual() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManualRecipeScreen(
          repository: widget.repository,
          extractor: widget.extractor,
        ),
      ),
    );
    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  Future<void> _openPhoto() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoRecipeScreen(
          repository: widget.repository,
          extractor: widget.extractor,
        ),
      ),
    );
    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final webHint = PlatformHints.isWeb;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'So geht’s ganz einfach',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  webHint
                      ? 'Am iPhone:\n'
                          '1. Rezeptvideo öffnen und den Link kopieren.\n'
                          '2. Hier auf „Link einfügen“ tippen.\n'
                          '3. Anleitung erstellen – auch ohne API-Schlüssel.\n'
                          'Oder: Papier-Rezept fotografieren / selbst tippen.'
                      : '1. Am iPhone ein Rezeptvideo öffnen.\n'
                          '2. Auf Teilen tippen und „Rezept Nachkochen“ wählen '
                          '(oder Link hier einfügen).\n'
                          '3. Anleitung erstellen – auch ohne API-Schlüssel.\n'
                          'Oder: Papier-Rezept fotografieren / selbst tippen.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _openPhoto,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Fotografieren'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _openManual,
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Selbst tippen'),
                ),
              ),
            ],
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
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pasteFromClipboard,
            icon: const Icon(Icons.content_paste),
            label: const Text('Link aus Zwischenablage einfügen'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zutaten gleich auf die Einkaufsliste'),
            value: _alsoShopping,
            onChanged: _loading
                ? null
                : (value) => setState(() => _alsoShopping = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('KI verwenden (falls Schlüssel da)'),
            subtitle: Text(
              _hasApiKey
                  ? 'Wenn die KI nicht geht, wird trotzdem ohne KI gespeichert.'
                  : 'Kein Schlüssel hinterlegt — es wird ohne KI erstellt.',
            ),
            value: _useAi && _hasApiKey,
            onChanged: (!_hasApiKey || _loading)
                ? null
                : (value) => setState(() => _useAi = value),
          ),
          const SizedBox(height: 8),
          if (_info != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_info!),
            ),
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
            'Tipp: Ohne KI-Schlüssel funktioniert die App trotzdem. '
            'Mit Schlüssel (OpenAI, Gemini oder Claude) werden Zutaten und '
            'Schritte oft besser — und Fotos lassen sich automatisch auslesen.',
          ),
        ],
      ),
    );
  }
}
