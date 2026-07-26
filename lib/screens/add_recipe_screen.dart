import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../services/app_repository.dart';
import '../services/caption_fetcher.dart';
import '../services/recipe_extractor.dart';
import '../services/video_link_fetcher.dart';
import '../services/youtube_caption.dart';
import '../theme/app_theme.dart';
import '../utils/platform_hints.dart';
import 'manual_recipe_screen.dart';
import 'pdf_recipe_screen.dart';
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
  late final CaptionFetcher _captionFetcher;
  late final VideoLinkFetcher _videoLinkFetcher;

  bool _loading = false;
  bool _fetchingCaption = false;
  bool _fetchingVideo = false;
  bool _alsoShopping = false;
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
    _captionFetcher = CaptionFetcher(extractor: widget.extractor);
    _videoLinkFetcher = VideoLinkFetcher();
    _loadKeyState();

    // Link schon da → Caption und Video automatisch versuchen zu laden.
    if (_linkController.text.trim().startsWith('http')) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (_captionController.text.trim().isEmpty) {
          await _loadCaptionFromLink(silentIfEmpty: true);
        } else if (_videoBytes == null && _supportsAutoVideoFromLink()) {
          await _loadVideoFromLink(silent: true);
        }
      });
    }
  }

  bool _supportsAutoVideoFromLink() {
    final url = _extractLinkUrl();
    if (url == null) return false;
    return _looksLikeFacebookUrl(url) || isYoutubeUrl(url);
  }

  bool _looksLikeFacebookUrl(String raw) {
    final host = Uri.tryParse(raw.trim())?.host.toLowerCase() ?? '';
    return host.contains('facebook.com') ||
        host == 'fb.watch' ||
        host == 'fb.com' ||
        host.endsWith('.facebook.com');
  }

  String? _extractLinkUrl() {
    final raw = _linkController.text.trim();
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(raw);
    final url = urlMatch?.group(0) ?? raw;
    if (!url.startsWith('http')) return null;
    return url;
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
    var shouldAutoloadCaption = false;
    var pastedUrl = false;
    setState(() {
      if (urlMatch != null) {
        _linkController.text = urlMatch.group(0)!;
        pastedUrl = true;
        final rest = text.replaceFirst(urlMatch.group(0)!, '').trim();
        if (rest.isNotEmpty) {
          _captionController.text = [
            if (_captionController.text.trim().isNotEmpty)
              _captionController.text.trim(),
            rest,
          ].join('\n\n');
        } else if (_captionController.text.trim().isEmpty) {
          shouldAutoloadCaption = true;
        }
      } else {
        _linkController.text = text;
        if (text.startsWith('http')) {
          pastedUrl = true;
          if (_captionController.text.trim().isEmpty) {
            shouldAutoloadCaption = true;
          }
        }
      }
    });
    if (shouldAutoloadCaption) {
      await _loadCaptionFromLink(silentIfEmpty: true);
    } else if (pastedUrl &&
        _videoBytes == null &&
        _supportsAutoVideoFromLink()) {
      await _loadVideoFromLink(silent: true);
    }
  }

  Future<void> _loadCaptionFromLink({bool silentIfEmpty = false}) async {
    final raw = _linkController.text.trim();
    final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(raw);
    final url = urlMatch?.group(0) ?? raw;
    if (!url.startsWith('http')) {
      setState(() {
        _error = 'Bitte zuerst einen Video-Link einfügen.';
      });
      return;
    }

    setState(() {
      _fetchingCaption = true;
      _error = null;
      _info = 'Caption wird vom Link geladen…';
    });

    try {
      final result = await _captionFetcher.fetchFromUrl(url);
      if (!mounted) return;

      if (!result.hasCaption) {
        setState(() {
          _fetchingCaption = false;
          _info = null;
          if (!silentIfEmpty) {
            _error = result.warning ??
                'Keine Caption gefunden. Bitte Text unter dem Video manuell einfügen.';
          } else {
            _info =
                'Keine Caption automatisch gefunden — bitte Text unter dem Video einfügen.';
          }
        });
        // Caption fehlgeschlagen: Video trotzdem versuchen (gesprochene Schritte).
        if (_videoBytes == null && _supportsAutoVideoFromLink()) {
          await _loadVideoFromLink(silent: true);
        }
        return;
      }

      setState(() {
        _captionController.text = result.caption;
        _captionController.selection = TextSelection.collapsed(
          offset: result.caption.length,
        );
        _fetchingCaption = false;
        _info =
            'Caption automatisch geladen'
            '${result.title.isNotEmpty ? ' (${result.title})' : ''}. '
            'Bitte kurz prüfen, dann Anleitung erstellen.';
        _error = null;
      });

      // Facebook/YouTube: Zubereitung oft gesprochen → Video vom Link nachladen.
      if (_videoBytes == null && _supportsAutoVideoFromLink()) {
        await _loadVideoFromLink(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchingCaption = false;
        _info = null;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadVideoFromLink({bool silent = false}) async {
    final url = _extractLinkUrl();
    if (url == null) {
      if (!silent) {
        setState(() {
          _error = 'Bitte zuerst einen Video-Link einfügen.';
        });
      }
      return;
    }

    setState(() {
      _fetchingVideo = true;
      _error = null;
      _info = 'Video wird vom Link geladen…';
    });

    try {
      final video = await _videoLinkFetcher.fetchFromUrl(url);
      if (!mounted) return;
      setState(() {
        _videoBytes = video.bytes;
        _videoMimeType = video.mimeType;
        _videoName = video.fileName;
        _fetchingVideo = false;
        _info =
            'Video vom Link geladen '
            '(${(video.bytes.length / 1024 / 1024).toStringAsFixed(1)} MB). '
            'KI kann Ton + Bild auswerten.';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _fetchingVideo = false;
        if (silent) {
          _info =
              'Video vom Link ging nicht automatisch — '
              'du kannst „Video vom Link laden“ nochmal tippen '
              'oder die Datei unter „Video wählen“ anhängen.';
          _error = null;
        } else {
          _info = null;
          _error = message;
        }
      });
    }
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
    final linkOrText = _linkController.text.trim();
    final caption = _captionController.text.trim();
    final needsVideoForSteps = _videoBytes == null &&
        widget.extractor.captionLooksLikeIngredientsOnly(caption);

    if (needsVideoForSteps) {
      final hasLink = _extractLinkUrl() != null;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Video für die Zubereitung'),
          content: Text(
            'In der Caption stehen meist nur die Zutaten. '
            'Die Zubereitung erklärt die Person im Video gesprochen.\n\n'
            'Ohne Video kann die KI die Schritte nicht richtig übernehmen '
            'und rät oft daneben.\n\n'
            '${hasLink ? 'Am besten: Video vom Link laden, dann nochmal erstellen.' : 'Am besten: Video anhängen (Gemini), dann nochmal erstellen.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'without'),
              child: const Text('Trotzdem ohne Video'),
            ),
            if (hasLink)
              FilledButton(
                onPressed: () => Navigator.pop(context, 'from_link'),
                child: const Text('Video vom Link'),
              )
            else
              FilledButton(
                onPressed: () => Navigator.pop(context, 'attach'),
                child: const Text('Video wählen'),
              ),
          ],
        ),
      );
      if (!mounted) return;
      if (choice == null || choice == 'cancel') return;
      if (choice == 'from_link') {
        await _loadVideoFromLink();
        return;
      }
      if (choice == 'attach') {
        await _pickVideo(ImageSource.gallery);
        return;
      }
    }

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
      } else if (_videoBytes == null &&
          recipe.notes?.toLowerCase().contains('video') == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Zutaten übernommen. Für echte Videoschritte bitte '
              'nächstes Mal das Video anhängen.',
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

  Future<void> _openPdf() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfRecipeScreen(
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
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF4FAF6),
                  Color(0xFFFFF7F3),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.seed.withValues(alpha: 0.14)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: AppTheme.accent,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'So holt die KI das meiste aus dem Video',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  webHint
                      ? '1. Video-Link einfügen.\n'
                          '2. Caption/Beschreibung wird oft automatisch geladen.\n'
                          '3. Video wird oft automatisch vom Link geladen '
                          '(wichtig für gesprochene Schritte).\n'
                          '4. Anleitung erstellen — fehlende Mengen ergänzt die KI.\n\n'
                          'Tipp: Wenn Caption leer bleibt — Text manuell kopieren. '
                          'YouTube Shorts: Titel → Beschreibung → „…mehr“.\n'
                          'Wenn Video fehlt: „Video vom Link laden“ tippen '
                          'oder Datei unter „Video wählen“ anhängen.'
                      : '1. Video teilen oder Link einfügen.\n'
                          '2. Caption vom Link laden (oder selbst einfügen).\n'
                          '3. Video wird oft automatisch vom Link geladen.\n'
                          '4. Anleitung erstellen — fehlende Infos ergänzt die KI.\n\n'
                          'Tipp: Wenn Caption leer bleibt — Text manuell kopieren. '
                          'YouTube Shorts: Titel → Beschreibung → „…mehr“.\n'
                          'Wenn Video fehlt: „Video vom Link laden“ tippen '
                          'oder Datei unter „Video wählen“ anhängen.',
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
                  label: const Text('Fotos / Screenshots'),
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
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _loading ? null : _openPdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF auswählen'),
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
            onPressed: (_loading || _fetchingCaption || _fetchingVideo)
                ? null
                : _pasteLink,
            icon: const Icon(Icons.content_paste),
            label: const Text('Link einfügen'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionController,
            minLines: 5,
            maxLines: 12,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Caption / YouTube-Beschreibung',
              hintText:
                  'Facebook: Text unter dem Video. YouTube: Beschreibung („…mehr“).',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: (_loading || _fetchingCaption || _fetchingVideo)
                ? null
                : () => _loadCaptionFromLink(),
            icon: _fetchingCaption
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(
              _fetchingCaption
                  ? 'Caption wird geladen…'
                  : 'Caption vom Link laden',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_loading || _fetchingCaption || _fetchingVideo)
                ? null
                : _pasteCaption,
            icon: const Icon(Icons.notes),
            label: const Text('Caption manuell einfügen'),
          ),
          const SizedBox(height: 16),
          Text(
            _videoBytes == null
                ? 'Video mit Ton (wichtig für die Zubereitung)'
                : 'Video mit Ton',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            _videoBytes == null
                ? 'In der Caption stehen oft nur die Zutaten. '
                    'Die Schritte erklärt die Person gesprochen im Video — '
                    'am einfachsten: Link einfügen, dann lädt die App das Video '
                    'automatisch (oder „Video vom Link laden“ tippen). '
                    'Kurz halten (unter 3 Min.).'
                : 'Video ist angehängt. Die KI wertet Ton + Bild + Caption aus.',
          ),
          if (_videoBytes == null &&
              widget.extractor.captionLooksLikeIngredientsOnly(
                _captionController.text,
              )) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.25),
                ),
              ),
              child: const Text(
                'Hinweis: Diese Caption wirkt wie eine Zutatenliste. '
                'Ohne Video werden die gesprochenen Schritte oft falsch geraten.',
              ),
            ),
          ],
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: (_loading || _fetchingCaption || _fetchingVideo)
                ? null
                : () => _loadVideoFromLink(),
            icon: _fetchingVideo
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_download),
            label: Text(
              _fetchingVideo
                  ? 'Video wird geladen…'
                  : 'Video vom Link laden',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_loading || _fetchingVideo)
                      ? null
                      : () => _pickVideo(ImageSource.gallery),
                  icon: const Icon(Icons.video_library),
                  label: const Text('Video wählen'),
                ),
              ),
              if (!kIsWeb) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_loading || _fetchingVideo)
                        ? null
                        : () => _pickVideo(ImageSource.camera),
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
            'Tipp: Zutaten stehen oft in Caption/Beschreibung — die Zubereitung '
            'wird meist gesprochen. Das Video soll automatisch vom Link kommen. '
            'Wenn nicht: „Video vom Link laden“ oder Datei anhängen (Gemini). '
            'YouTube-Beschreibung ggf. über Titel → Beschreibung → „…mehr“.',
          ),
        ],
      ),
    );
  }
}
