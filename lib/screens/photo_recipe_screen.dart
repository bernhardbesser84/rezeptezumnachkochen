import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_repository.dart';
import '../services/recipe_extractor.dart';

/// Papier-Rezept abfotografieren und daraus ein Rezept machen.
///
/// - Mit KI-Schlüssel: Text wird automatisch ausgelesen.
/// - Ohne Schlüssel: Foto ansehen und Text selbst eintippen (immer möglich).
class PhotoRecipeScreen extends StatefulWidget {
  const PhotoRecipeScreen({
    super.key,
    required this.repository,
    required this.extractor,
  });

  final AppRepository repository;
  final RecipeExtractor extractor;

  @override
  State<PhotoRecipeScreen> createState() => _PhotoRecipeScreenState();
}

class _PhotoRecipeScreenState extends State<PhotoRecipeScreen> {
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _ingredients = TextEditingController();
  final _steps = TextEditingController();

  Uint8List? _imageBytes;
  String _mimeType = 'image/jpeg';
  bool _alsoShopping = true;
  bool _busy = false;
  String? _status;
  String? _error;
  bool _hasApiKey = false;

  @override
  void initState() {
    super.initState();
    _checkApiKey();
  }

  Future<void> _checkApiKey() async {
    final key = await widget.repository.storage.getApiKey();
    if (!mounted) return;
    setState(() => _hasApiKey = key != null && key.trim().isNotEmpty);
  }

  @override
  void dispose() {
    _title.dispose();
    _ingredients.dispose();
    _steps.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    setState(() {
      _error = null;
      _status = null;
    });
    try {
      final file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2000,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ??
          (file.path.toLowerCase().endsWith('.png')
              ? 'image/png'
              : 'image/jpeg');
      setState(() {
        _imageBytes = bytes;
        _mimeType = mime;
      });
    } catch (e) {
      setState(() {
        _error =
            'Foto konnte nicht geladen werden. Bitte Kamerazugriff erlauben '
            'oder ein Bild aus der Galerie wählen.';
      });
    }
  }

  List<String> _lines(String value) => value
      .split(RegExp(r'[\n\r]+'))
      .map((e) => e.replaceFirst(RegExp(r'^[-•*\d.)\s]+'), '').trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _autoRead() async {
    if (_imageBytes == null) {
      setState(() => _error = 'Bitte zuerst ein Foto aufnehmen oder wählen.');
      return;
    }

    final apiKey = await widget.repository.storage.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      setState(() {
        _error =
            'Fürs automatische Auslesen brauchst du einmal einen KI-Schlüssel '
            '(z. B. Gemini) unter Einstellungen. '
            'Ohne Schlüssel: Text unten selbst eintippen — das geht immer.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'Foto wird ausgelesen…';
    });

    try {
      final provider = await widget.repository.storage.getAiProvider();
      final recipe = await widget.extractor.extractRecipeFromImage(
        imageBytes: _imageBytes!,
        mimeType: _mimeType,
        apiKey: apiKey.trim(),
        provider: provider,
      );
      if (!mounted) return;
      setState(() {
        _title.text = recipe.title;
        _ingredients.text = recipe.ingredients.join('\n');
        _steps.text = recipe.steps.join('\n');
        _status = 'Ausgelesen. Bitte kurz prüfen und speichern.';
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _status =
            'Automatisches Lesen hat nicht geklappt — bitte Text selbst tippen.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty &&
        _ingredients.text.trim().isEmpty &&
        _steps.text.trim().isEmpty) {
      setState(() {
        _error =
            'Bitte Titel, Zutaten oder Schritte ausfüllen '
            '(per Auto-Auslesen oder selbst tippen).';
      });
      return;
    }

    setState(() => _busy = true);
    try {
      final recipe = widget.extractor.buildManualRecipe(
        title: _title.text.trim().isEmpty
            ? 'Abfotografiertes Rezept'
            : _title.text,
        ingredients: _lines(_ingredients.text),
        steps: _lines(_steps.text),
        notes: 'Aus Foto erfasst.',
      );
      await widget.repository.saveRecipe(recipe);
      if (_alsoShopping) {
        await widget.repository.addRecipeToShopping(recipe);
      }
      if (!mounted) return;
      Navigator.pop(context, recipe);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rezept fotografieren')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _hasApiKey
                ? 'Foto vom Papier-Rezept machen. Danach kannst du es '
                    'automatisch auslesen lassen oder selbst tippen.'
                : 'Foto vom Papier-Rezept machen und den Text selbst eintippen. '
                    'Mit KI-Schlüssel (z. B. Gemini) unter Einstellungen geht '
                    'auch automatisches Auslesen.',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Kamera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galerie'),
                ),
              ),
            ],
          ),
          if (_imageBytes != null) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(
                _imageBytes!,
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _autoRead,
              icon: const Icon(Icons.document_scanner),
              label: const Text('Automatisch auslesen'),
            ),
          ],
          if (_status != null) ...[
            const SizedBox(height: 10),
            Text(_status!),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Titel',
              hintText: 'z. B. Omas Apfelkuchen',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ingredients,
            enabled: !_busy,
            minLines: 4,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Zutaten (eine Zeile pro Zutat)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _steps,
            enabled: !_busy,
            minLines: 4,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Schritte (eine Zeile pro Schritt)',
              alignLabelWithHint: true,
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zutaten gleich auf die Einkaufsliste'),
            value: _alsoShopping,
            onChanged:
                _busy ? null : (value) => setState(() => _alsoShopping = value),
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: Text(_busy ? 'Bitte warten…' : 'Rezept speichern'),
          ),
        ],
      ),
    );
  }
}
