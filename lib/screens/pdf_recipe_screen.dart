import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../services/pdf_text_reader.dart';
import '../services/recipe_extractor.dart';
import '../theme/app_theme.dart';

/// Rezept aus einer PDF-Datei erstellen (z. B. gespeicherte Web-Rezepte).
class PdfRecipeScreen extends StatefulWidget {
  const PdfRecipeScreen({
    super.key,
    required this.repository,
    required this.extractor,
  });

  final AppRepository repository;
  final RecipeExtractor extractor;

  @override
  State<PdfRecipeScreen> createState() => _PdfRecipeScreenState();
}

class _PdfRecipeScreenState extends State<PdfRecipeScreen> {
  final _title = TextEditingController();
  final _ingredients = TextEditingController();
  final _steps = TextEditingController();

  Uint8List? _pdfBytes;
  String? _fileName;
  String? _previewText;
  bool _alsoShopping = false;
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

  List<String> _lines(String value) => value
      .split(RegExp(r'[\n\r]+'))
      .map((e) => e.replaceFirst(RegExp(r'^[-•*\d.)\s]+'), '').trim())
      .where((e) => e.isNotEmpty)
      .toList();

  Future<void> _pickPdf() async {
    setState(() {
      _error = null;
      _status = null;
    });
    try {
      const typeGroup = XTypeGroup(
        label: 'PDF',
        extensions: <String>['pdf'],
        mimeTypes: <String>['application/pdf'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() {
          _error =
              'PDF konnte nicht geladen werden. Bitte eine andere Datei wählen.';
        });
        return;
      }
      if (bytes.length > PdfTextReader.maxBytes) {
        setState(() {
          _error = 'Die PDF ist zu groß (max. 15 MB).';
        });
        return;
      }

      String? preview;
      try {
        final text = PdfTextReader.extractText(bytes);
        if (text.trim().isNotEmpty) {
          preview = text.length > 400 ? '${text.substring(0, 400)}…' : text;
        }
      } catch (_) {
        preview = null;
      }

      setState(() {
        _pdfBytes = bytes;
        _fileName = file.name;
        _previewText = preview;
        _status = preview == null
            ? 'PDF gewählt (kaum Text erkannt — KI versucht es trotzdem).'
            : 'PDF gewählt. Jetzt auslesen tippen.';
      });
    } catch (e) {
      setState(() {
        _error =
            'PDF-Auswahl fehlgeschlagen. Bitte Dateizugriff erlauben '
            'und erneut versuchen.';
      });
    }
  }

  Future<void> _autoRead() async {
    if (_pdfBytes == null) {
      setState(() => _error = 'Bitte zuerst eine PDF wählen.');
      return;
    }

    final apiKey = await widget.repository.storage.getApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      setState(() {
        _error =
            'Fürs automatische Auslesen brauchst du einen KI-Schlüssel '
            '(z. B. Gemini) unter Einstellungen.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _status = 'PDF wird ausgelesen…';
    });

    try {
      final provider = await widget.repository.storage.getAiProvider();
      final recipe = await widget.extractor.extractRecipeFromPdf(
        pdfBytes: _pdfBytes!,
        apiKey: apiKey.trim(),
        provider: provider,
        fileName: _fileName,
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
        _status = 'Auslesen hat nicht geklappt — bitte Text prüfen.';
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
            ? 'Rezept aus PDF'
            : _title.text,
        ingredients: _lines(_ingredients.text),
        steps: _lines(_steps.text),
        notes: _fileName == null
            ? 'Aus PDF erfasst.'
            : 'Aus PDF erfasst ($_fileName).',
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
      appBar: AppBar(title: const Text('PDF → Rezept')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _hasApiKey
                ? 'PDF mit Rezept wählen (z. B. gespeicherte Seite von '
                    'Golden Grace Kitchen). Die KI liest Text aus und '
                    'macht daraus ein deutsches Rezept mit metrischen Mengen.'
                : 'PDF wählen und den Text unten selbst eintragen. '
                    'Mit KI-Schlüssel unter Einstellungen geht automatisches '
                    'Auslesen.',
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: _busy ? null : _pickPdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: Text(
              _pdfBytes == null ? 'PDF auswählen' : 'Andere PDF wählen',
            ),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.accentSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.picture_as_pdf, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _fileName!,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  if (_previewText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _previewText!,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _autoRead,
              icon: const Icon(Icons.document_scanner),
              label: const Text('PDF auslesen'),
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
              hintText: 'z. B. Marry-Me-Lachs',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ingredients,
            enabled: !_busy,
            minLines: 4,
            maxLines: 12,
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
            maxLines: 14,
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
