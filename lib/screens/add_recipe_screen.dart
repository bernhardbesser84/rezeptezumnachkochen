import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_repository.dart';
import '../services/caption_fetcher.dart';
import '../services/recipe_extractor.dart';
import '../theme/app_theme.dart';
import '../utils/platform_hints.dart';
import 'manual_recipe_screen.dart';
import 'photo_recipe_screen.dart';

/// Neuer einfacher Weg: Caption (Text) → Rezept.
/// Video-Link nur zum Anschauen — kein Auto-Download, keine Video-KI.
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
  // Alte Parameter bleiben akzeptiert (Home/Share), werden aber ignoriert.
  final Uint8List? initialVideoBytes;
  final String? initialVideoMimeType;
  final String? initialVideoName;

  @override
  State<AddRecipeScreen> createState() => _AddRecipeScreenState();
}

class _AddRecipeScreenState extends State<AddRecipeScreen> {
  late final TextEditingController _linkController;
  late final TextEditingController _captionController;
  late final CaptionFetcher _captionFetcher;

  bool _loading = false;
  bool _fetchingCaption = false;
  bool _alsoShopping = true;
  bool _useAi = true;
  bool _hasApiKey = false;
  String? _error;
  String? _info;

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
    _captionFetcher = CaptionFetcher(extractor: widget.extractor);
    _loadKeyState();

    if (_linkController.text.trim().startsWith('http') &&
        _captionController.text.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadCaptionFromLink(silentIfEmpty: true);
      });
    }
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
    var shouldAutoload = false;
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
        } else if (_captionController.text.trim().isEmpty) {
          shouldAutoload = true;
        }
      } else {
        _linkController.text = text;
        if (text.startsWith('http') && _captionController.text.trim().isEmpty) {
          shouldAutoload = true;
        }
      }
    });
    if (shouldAutoload) {
      await _loadCaptionFromLink(silentIfEmpty: true);
    }
  }

  Future<void> _loadCaptionFromLink({bool silentIfEmpty = false}) async {
    final url = _extractLinkUrl();
    if (url == null) {
      setState(() {
        _error = 'Bitte zuerst einen Video-Link einfügen.';
      });
      return;
    }

    setState(() {
      _fetchingCaption = true;
      _error = null;
      _info = 'Text vom Link wird geladen…';
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
                'Kein Text gefunden. Bitte Caption unter dem Video kopieren.';
          } else {
            _info =
                'Kein Text automatisch gefunden — bitte Caption unter dem '
                'Video kopieren und hier einfügen.';
          }
        });
        return;
      }

      setState(() {
        _captionController.text = result.caption;
        _captionController.selection = TextSelection.collapsed(
          offset: result.caption.length,
        );
        _fetchingCaption = false;
        _info =
            'Text geladen'
            '${result.title.isNotEmpty ? ' (${result.title})' : ''}. '
            'Bitte prüfen, dann „Anleitung erstellen“.';
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchingCaption = false;
        _info = null;
        _error = e.toString().replaceFirst('Exception: ', '');
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
      _error = null;
      _info = 'Caption eingefügt. Jetzt „Anleitung erstellen“ tippen.';
    });
  }

  Future<void> _openVideoLink() async {
    final url = _extractLinkUrl();
    if (url == null) {
      setState(() {
        _error = 'Kein Video-Link vorhanden.';
      });
      return;
    }
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() {
        _error = 'Video konnte nicht geöffnet werden.';
      });
    }
  }

  Future<void> _createRecipe() async {
    final linkOrText = _linkController.text.trim();
    final caption = _captionController.text.trim();

    if (caption.isEmpty && linkOrText.isEmpty) {
      setState(() {
        _error =
            'Bitte den Text unter dem Video (Caption) einfügen — '
            'daraus wird das Rezept gebaut.';
      });
      return;
    }

    if (caption.isEmpty) {
      setState(() {
        _error =
            'Ohne Caption klappt es nicht zuverlässig. '
            'Im Facebook-Video: Text unter dem Video kopieren → hier einfügen.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _info = 'Rezept wird aus dem Text erstellt…';
    });

    try {
      final provider = await widget.repository.storage.getAiProvider();
      final apiKey = await widget.repository.storage.getApiKey();
      final urlMatch = RegExp(r'https?://[^\s]+').firstMatch(linkOrText);
      final url = urlMatch?.group(0);

      // Nur Text an die KI — kein Video-Upload (klein, Free-Tier-tauglich).
      final recipe = await widget.extractor.extractRecipe(
        sourceText: linkOrText,
        sourceUrl: url,
        captionText: caption,
        apiKey: apiKey,
        provider: provider,
        useAi: _useAi,
        skipPagePreview: true,
      );

      await widget.repository.saveRecipe(recipe);
      if (_alsoShopping) {
        await widget.repository.addRecipeToShopping(recipe);
      }
      if (!mounted) return;

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
    final webHint = PlatformHints.looksLikeAppleMobileWeb;

    return Scaffold(
      appBar: AppBar(title: const Text('Rezept hinzufügen')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Neuer, einfacher Weg',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  webHint
                      ? '1. Video-Link einfügen (nur zum Anschauen).\n'
                          '2. Text unter dem Video kopieren und hier einfügen.\n'
                          '3. „Anleitung erstellen“ — die KI strukturiert den Text.\n\n'
                          'Kein Video-Download mehr. Das war zu unzuverlässig.'
                      : '1. Video teilen oder Link einfügen.\n'
                          '2. Caption (Text unter dem Video) einfügen.\n'
                          '3. Anleitung erstellen.\n\n'
                          'Tipp: Zubereitungsschritte oft mit in die Caption kopieren, '
                          'wenn sie im Video als Text stehen — oder selbst tippen.',
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
              labelText: 'Video-Link (zum Anschauen)',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (_loading || _fetchingCaption) ? null : _pasteLink,
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Link einfügen'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _openVideoLink,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Video öffnen'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionController,
            minLines: 8,
            maxLines: 16,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Text unter dem Video (Caption) — wichtig',
              hintText:
                  'Gerichtname, Zutaten, Mengen — und wenn möglich die Schritte',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: (_loading || _fetchingCaption)
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
                  ? 'Text wird geladen…'
                  : 'Text vom Link laden (optional)',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_loading || _fetchingCaption) ? null : _pasteCaption,
            icon: const Icon(Icons.notes),
            label: const Text('Caption manuell einfügen'),
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
                  ? 'Nur Text → Rezept (kleine Anfrage, kein Video-Upload).'
                  : 'Ohne Schlüssel: einfache lokale Auswertung.',
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
            'Tipp: Stehen die Schritte nur gesprochen im Video, tippe sie '
            'kurz unter die Caption — oder nutze „Selbst tippen“ / '
            '„Fotografieren“. Das ist zuverlässiger als Auto-Download.',
          ),
          if (kIsWeb) const SizedBox(height: 8),
        ],
      ),
    );
  }
}
