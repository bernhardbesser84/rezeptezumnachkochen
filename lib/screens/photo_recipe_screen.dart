import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_repository.dart';
import '../services/recipe_category_service.dart';
import '../services/recipe_extractor.dart';
import '../widgets/recipe_category_picker.dart';

/// Rezept aus einem oder mehreren Fotos/Screenshots erstellen.
///
/// - Mit KI-Schlüssel: Text in den Bildern wird automatisch ausgelesen.
/// - Ohne Schlüssel: Fotos ansehen und Text selbst eintippen (immer möglich).
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
  static const _maxImages = 12;

  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _ingredients = TextEditingController();
  final _steps = TextEditingController();

  final List<RecipeImageInput> _images = [];
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

  String _mimeFor(XFile file) {
    final mime = file.mimeType;
    if (mime != null && mime.startsWith('image/')) return mime;
    final path = file.path.toLowerCase();
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _addCameraPhoto() async {
    setState(() {
      _error = null;
      _status = null;
    });
    if (_images.length >= _maxImages) {
      setState(() {
        _error = 'Maximal $_maxImages Bilder. Bitte erst eines entfernen.';
      });
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _images.add(RecipeImageInput(bytes: bytes, mimeType: _mimeFor(file)));
      });
    } catch (_) {
      setState(() {
        _error =
            'Foto konnte nicht geladen werden. Bitte Kamerazugriff erlauben '
            'oder Bilder aus der Galerie wählen.';
      });
    }
  }

  Future<void> _addFromGallery() async {
    setState(() {
      _error = null;
      _status = null;
    });
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) {
      setState(() {
        _error = 'Maximal $_maxImages Bilder. Bitte erst eines entfernen.';
      });
      return;
    }
    try {
      final files = await _picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
        limit: remaining,
      );
      if (files.isEmpty) return;
      final added = <RecipeImageInput>[];
      for (final file in files.take(remaining)) {
        final bytes = await file.readAsBytes();
        added.add(RecipeImageInput(bytes: bytes, mimeType: _mimeFor(file)));
      }
      setState(() => _images.addAll(added));
    } catch (_) {
      // Fallback: einzelnes Bild, falls Multi auf dem Gerät nicht geht.
      try {
        final file = await _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1600,
        );
        if (file == null) return;
        final bytes = await file.readAsBytes();
        setState(() {
          _images.add(
            RecipeImageInput(bytes: bytes, mimeType: _mimeFor(file)),
          );
        });
      } catch (_) {
        setState(() {
          _error =
              'Bilder konnten nicht geladen werden. Bitte Galerie-Zugriff '
              'erlauben und erneut versuchen.';
        });
      }
    }
  }

  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  List<String> _lines(String value) => value
      .split(RegExp(r'[\n\r]+'))
      .map((e) => e.replaceFirst(RegExp(r'^[-•*\d.)\s]+'), '').trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _autoRead() async {
    if (_images.isEmpty) {
      setState(() => _error = 'Bitte zuerst Fotos aufnehmen oder wählen.');
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
      _status = _images.length == 1
          ? 'Foto wird ausgelesen…'
          : '${_images.length} Bilder werden ausgelesen…';
    });

    try {
      final provider = await widget.repository.storage.getAiProvider();
      final recipe = await widget.extractor.extractRecipeFromImages(
        images: List<RecipeImageInput>.from(_images),
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
      var recipe = widget.extractor.buildManualRecipe(
        title: _title.text.trim().isEmpty
            ? 'Rezept aus Fotos'
            : _title.text,
        ingredients: _lines(_ingredients.text),
        steps: _lines(_steps.text),
        notes: _images.length <= 1
            ? 'Aus Foto erfasst.'
            : 'Aus ${_images.length} Fotos/Screenshots erfasst.',
      );
      final existingRecipes =
          await widget.repository.loadRecipes(pullRemote: false);
      if (!mounted) return;
      final selectedCategories = await showRecipeCategoryPicker(
        context: context,
        title: 'Kategorien für dieses Rezept',
        initialSelection: recipe.categories,
        suggestedCategories: RecipeCategoryService.suggestForRecipe(recipe),
        existingCategories: RecipeCategoryService.collectFromRecipes(
          existingRecipes,
        ),
      );
      if (!mounted) return;
      if (selectedCategories == null) return;
      recipe = recipe.copyWith(
        categories: selectedCategories,
        imageUrl: _coverFromFirstPhoto(),
      );
      final cloudWarning = await widget.repository.saveRecipe(recipe);
      if (_alsoShopping) {
        await widget.repository.addRecipeToShopping(recipe);
      }
      if (!mounted) return;
      if (cloudWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cloudWarning),
            duration: const Duration(seconds: 8),
          ),
        );
      }
      Navigator.pop(context, recipe);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _coverFromFirstPhoto() {
    if (_images.isEmpty) return null;
    final first = _images.first;
    if (first.bytes.isEmpty || first.bytes.length > 180000) return null;
    return 'data:${first.mimeType};base64,${base64Encode(first.bytes)}';
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
                ? 'Ein Foto oder mehrere Screenshots/Bilder wählen '
                    '(z. B. Schritt-für-Schritt mit Text im Bild). '
                    'Danach automatisch auslesen oder selbst tippen.'
                : 'Fotos wählen und den Text selbst eintippen. '
                    'Mit KI-Schlüssel (z. B. Gemini) unter Einstellungen geht '
                    'auch automatisches Auslesen mehrerer Bilder.',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _addCameraPhoto,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Kamera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _addFromGallery,
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galerie'),
                ),
              ),
            ],
          ),
          if (_images.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '${_images.length} Bild${_images.length == 1 ? '' : 'er'} '
              '(Reihenfolge = Schritte)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final image = _images[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          image.bytes,
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        left: 6,
                        top: 6,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.black54,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          tooltip: 'Entfernen',
                          onPressed: _busy ? null : () => _removeImage(index),
                          icon: const Icon(Icons.cancel, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black45,
                            padding: const EdgeInsets.all(4),
                            minimumSize: const Size(28, 28),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _autoRead,
              icon: const Icon(Icons.document_scanner),
              label: Text(
                _images.length == 1
                    ? 'Automatisch auslesen'
                    : 'Alle ${_images.length} Bilder auslesen',
              ),
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
              hintText: 'z. B. Wassermelonen-Feta-Salat',
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
            maxLines: 12,
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
