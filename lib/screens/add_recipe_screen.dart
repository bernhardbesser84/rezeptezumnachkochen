import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

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
    this.initialVideoBytes,
    this.initialVideoMimeType,
    this.initialVideoName,
  });

  final AppRepository repository;
  final RecipeExtractor extractor;
  final String? initialSharedText;
  final Uint8List? initialVideoBytes;
  final String? initialVideoMimeType;
  final String? initialVideoName;

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  late final TextEditingController _linkController;
  late final TextEditingController _captionController;
  final _picker = ImagePicker();

  bool _loading = false;
  bool _alsoShopping = true;
  bool _useAi = true;
  bool _hasApiKey = false;
  String? _error;
  String? _info;

  Uint8List? _videoBytes;
  String? _videoMimeType;
  String? _videoName;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSharedText ?? '';
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(initial);
    final url = urlMatch?.group(0) ?? '';
    final rest = url.isEmpty
        ? initial
        : initial.replaceFirst(url, '').trim();

    if (url.isNotEmpty) {
      _linkController = TextEditingController(text: url);
      _captionController = TextEditingController(text: rest);
    } else {
      _linkController = TextEditingController();
      _captionController = TextEditingController(text: initial);
    }
    _videoBytes = widget.initialVideoBytes;
    _videoMimeType = widget.initialVideoMimeType;
    _videoName = widget.initialVideoName;
    _loadKeyState();
  }

  Future<void> _loadKeyState() async {
    final key = await widget.repository.storage.getApiKey();
    if (!mounted) return;
    setState(() {
      _hasApiKey = key != null && key.trim().isNotEmpty;
      _useAi = _hasApiKey;
    });
  }

  @override
  void dispose() {
    _linkController.dispose();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pasteLink() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zwischenablage ist leer.')),
      );
      return;
    }
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(text);
    setState(() {
      if (urlMatch != null) {
        _linkController.text = urlMatch.group(0)!;
        final rest = text.replaceFirst(urlMatch.group(0)!, '').trim();
        if (rest.isNotEmpty) {
          _captionController.text = [
            if (_captionController.text.trim().isNotEmpty)
              _captionController.text.trim(),
            rest,
          ].join('\n\n');
        }
      } else {
        _linkController.text = text;
      }
    });
  }

  Future<void> _pasteCaption() async {
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
      _captionController.text = text;
      _captionController.selection =
          TextSelection.collapsed(offset: text.length);
    });
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 3),
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      // Zu große Videos überlasten die KI — praktische Grenze ~18 MB.
      if (bytes.length > 18 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Video ist zu groß (max. ca. 18 MB). '
              'Kürzeres Video wählen oder nur Caption + Link nutzen.',
            ),
          ),
        );
        return;
      }
      setState(() {
        _videoBytes = bytes;
        _videoMimeType = file.mimeType ?? 'video/mp4';
        _videoName = file.name;
        _info = 'Video angehängt (${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
            'KI nutzt Ton + Bild + Caption.';
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error =
            'Video konnte nicht geladen werden. Bitte Zugriff erlauben '
            'oder die Videodatei teilen.';
      });
    }
  }

  Future<void> _createRecipe() async {
    setState(() {
      _loading = true;
      _error = null;
      _info = _videoBytes != null
          ? 'Video, Ton und Text werden ausgewertet…'
          : 'Rezept wird erstellt…';
    });

    try {
      final provider = await widget.repository.storage.getAiProvider();
      final apiKey = await widget.repository.storage.getApiKey();
      final linkOrText = _linkController.text.trim();
      final caption = _captionController.text.trim();
      final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(linkOrText);
      final url = urlMatch?.group(0);

      final recipe = await widget.extractor.extractRecipe(
        sourceText: linkOrText,
        sourceUrl: url,
        captionText: caption,
        apiKey: apiKey,
        provider: provider,
        useAi: _useAi,
        videoBytes: _videoBytes,
        videoMimeType: _videoMimeType,
        videoFileName: _videoName,
      );

      await widget.repository.saveRecipe(recipe);
      if (_alsoShopping) {
        await widget.repository.addRecipeToShopping(recipe);
      }
      if (!mounted) return;

      final usedFallback =
          recipe.notes?.contains('KI war gerade nicht nutzbar') == true;
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
        _info = null;
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
                  'So holt die KI das meiste aus dem Video',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  webHint
                      ? '1. Video-Link einfügen.\n'
                          '2. Den kompletten Text unter dem Video '
                          '(Caption) kopieren und hier einfügen.\n'
                          '3. Optional: Video-Datei anhängen '
                          '(Ton + Bild).\n'
                          '4. Anleitung erstellen — fehlende Mengen '
                          'ergänzt die KI.'
                      : '1. Video teilen oder Link einfügen.\n'
                          '2. Caption / Text unter dem Video mitnehmen.\n'
                          '3. Optional Video anhängen für Ton + Bild.\n'
                          '4. Anleitung erstellen — fehlende Infos '
                          'ergänzt die KI.',
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
            controller: _linkController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Video-Link',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pasteLink,
            icon: const Icon(Icons.content_paste),
            label: const Text('Link einfügen'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionController,
            minLines: 5,
            maxLines: 12,
            decoration: const InputDecoration(
              labelText: 'Text unter dem Video (Caption)',
              hintText:
                  'Komplette Beschreibung / Zutatenliste aus dem Video '
                  'hier einfügen',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _loading ? null : _pasteCaption,
            icon: const Icon(Icons.notes),
            label: const Text('Caption / Beschreibung einfügen'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Video mit Ton (optional)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Damit die KI auch das Gehörte auswertet. '
            'Am besten mit Gemini-Schlüssel. Kurz halten (unter 3 Min.).',
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed:
                      _loading ? null : () => _pickVideo(ImageSource.gallery),
                  icon: const Icon(Icons.video_library),
                  label: const Text('Video wählen'),
                ),
              ),
              if (!kIsWeb) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _loading ? null : () => _pickVideo(ImageSource.camera),
                    icon: const Icon(Icons.videocam),
                    label: const Text('Aufnehmen'),
                  ),
                ),
              ],
            ],
          ),
          if (_videoBytes != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _videoName ??
                        'Video bereit (${(_videoBytes!.length / 1024 / 1024).toStringAsFixed(1)} MB)',
                  ),
                ),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _videoBytes = null;
                            _videoMimeType = null;
                            _videoName = null;
                            _info = null;
                          }),
                  child: const Text('Entfernen'),
                ),
              ],
            ),
          ],
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
                  ? 'Nutzt Caption + Ton/Untertitel und ergänzt Fehlendes.'
                  : 'Ohne Schlüssel: einfache Auswertung ohne Video-Ton.',
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
            'Tipp: Bei YouTube werden Untertitel oft automatisch geladen. '
            'Bei Instagram/TikTok Caption unbedingt mitkopieren — '
            'dort ist der Text unter dem Video die wichtigste Quelle.',
          ),
        ],
      ),
    );
  }
}
