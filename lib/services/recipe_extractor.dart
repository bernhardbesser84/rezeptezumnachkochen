import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/ai_provider.dart';
import '../models/recipe.dart';

class PagePreview {
  PagePreview({
    required this.url,
    required this.title,
    required this.description,
  });

  final String url;
  final String title;
  final String description;
}

class RecipeExtractor {
  RecipeExtractor({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final _uuid = const Uuid();

  /// Zieht Titel und Beschreibung aus einem Link (z. B. Facebook/Instagram).
  Future<PagePreview> fetchPagePreview(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw Exception('Das sieht nicht nach einem gültigen Link aus.');
    }

    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                  '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
          'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 400) {
        return PagePreview(
          url: url,
          title: _guessTitleFromUrl(url),
          description: '',
        );
      }

      final html = response.body;
      final title = _firstNonEmpty([
        _metaContent(html, 'og:title'),
        _metaName(html, 'title'),
        _tagText(html, 'title'),
        _guessTitleFromUrl(url),
      ]);
      final description = _firstNonEmpty([
        _metaContent(html, 'og:description'),
        _metaName(html, 'description'),
        _metaName(html, 'twitter:description'),
      ]);

      return PagePreview(url: url, title: title, description: description);
    } catch (_) {
      return PagePreview(
        url: url,
        title: _guessTitleFromUrl(url),
        description: '',
      );
    }
  }

  /// Erstellt ein Rezept aus Link + optionalem Freitext.
  /// Mit API-Schlüssel: bessere KI-Auswertung. Ohne: lokale Auswertung.
  Future<Recipe> extractRecipe({
    required String sourceText,
    String? sourceUrl,
    String? apiKey,
    AiProvider provider = AiProvider.openai,
  }) async {
    final trimmed = sourceText.trim();
    if (trimmed.isEmpty && (sourceUrl == null || sourceUrl.trim().isEmpty)) {
      throw Exception('Bitte einen Link oder Text einfügen.');
    }

    var url = sourceUrl?.trim() ?? '';
    var preview = PagePreview(url: url, title: '', description: '');

    if (url.isEmpty) {
      final found = _extractFirstUrl(trimmed);
      if (found != null) {
        url = found;
      }
    }

    if (url.isNotEmpty) {
      preview = await fetchPagePreview(url);
    }

    final combined = [
      if (preview.title.isNotEmpty) 'Titel: ${preview.title}',
      if (preview.description.isNotEmpty)
        'Beschreibung: ${preview.description}',
      if (trimmed.isNotEmpty) 'Zusätzlicher Text: $trimmed',
      if (url.isNotEmpty) 'Quelle: $url',
    ].join('\n');

    if (apiKey != null && apiKey.trim().isNotEmpty) {
      return _extractWithAi(
        provider: provider,
        combinedText: combined,
        sourceUrl: url,
        apiKey: apiKey.trim(),
      );
    }

    return _extractLocally(
      combinedText: combined,
      titleHint: preview.title,
      sourceUrl: url,
    );
  }

  static const _systemPrompt =
      'Du hilfst beim Nachkochen von Rezeptvideos. '
      'Antworte NUR als JSON mit den Feldern: '
      'title (string), servings (string|null), '
      'prepTimeMinutes (number|null), '
      'ingredients (string[]), steps (string[]), '
      'notes (string|null). '
      'Sprache: Deutsch. '
      'Schätze fehlende Mengen sinnvoll. '
      'Schreibe klare, kurze Kochschritte.';

  Future<Recipe> _extractWithAi({
    required AiProvider provider,
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
  }) async {
    final userPrompt =
        'Erstelle daraus ein nachkochbares Rezept:\n$combinedText';

    switch (provider) {
      case AiProvider.openai:
        return _extractWithOpenAi(
          combinedText: userPrompt,
          sourceUrl: sourceUrl,
          apiKey: apiKey,
        );
      case AiProvider.gemini:
        return _extractWithGemini(
          combinedText: userPrompt,
          sourceUrl: sourceUrl,
          apiKey: apiKey,
        );
      case AiProvider.claude:
        return _extractWithClaude(
          combinedText: userPrompt,
          sourceUrl: sourceUrl,
          apiKey: apiKey,
        );
    }
  }

  Future<Recipe> _extractWithOpenAi({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
  }) async {
    final response = await _client
        .post(
          Uri.parse('https://api.openai.com/v1/chat/completions'),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'gpt-4o-mini',
            'temperature': 0.2,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': _systemPrompt},
              {'role': 'user', 'content': combinedText},
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _aiErrorMessage(AiProvider.openai, response.statusCode, response.body),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content =
        (body['choices'] as List).first['message']['content'] as String;
    return _recipeFromAiJson(content, sourceUrl);
  }

  Future<Recipe> _extractWithGemini({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-3.5-flash:generateContent',
    );
    final response = await _client
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
          },
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': _systemPrompt},
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': combinedText},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.2,
              'responseMimeType': 'application/json',
            },
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _aiErrorMessage(AiProvider.gemini, response.statusCode, response.body),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('Gemini hat keine Antwort geliefert. Bitte erneut versuchen.');
    }
    final parts =
        (candidates.first as Map<String, dynamic>)['content']?['parts'] as List?;
    final text = parts
            ?.map((p) => (p as Map<String, dynamic>)['text']?.toString() ?? '')
            .join()
            .trim() ??
        '';
    if (text.isEmpty) {
      throw Exception('Gemini-Antwort war leer. Bitte erneut versuchen.');
    }
    return _recipeFromAiJson(text, sourceUrl);
  }

  Future<Recipe> _extractWithClaude({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
  }) async {
    final response = await _client
        .post(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': 'claude-haiku-4-5',
            'max_tokens': 2048,
            'temperature': 0.2,
            'system': _systemPrompt,
            'messages': [
              {'role': 'user', 'content': combinedText},
            ],
          }),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _aiErrorMessage(AiProvider.claude, response.statusCode, response.body),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['content'] as List?;
    if (content == null || content.isEmpty) {
      throw Exception('Claude hat keine Antwort geliefert. Bitte erneut versuchen.');
    }
    final text = content
        .whereType<Map>()
        .map((part) => part['text']?.toString() ?? '')
        .join()
        .trim();
    if (text.isEmpty) {
      throw Exception('Claude-Antwort war leer. Bitte erneut versuchen.');
    }
    return _recipeFromAiJson(text, sourceUrl);
  }

  Recipe _recipeFromAiJson(String raw, String sourceUrl) {
    final cleaned = raw
        .trim()
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```$'), '');
    final parsed = jsonDecode(cleaned) as Map<String, dynamic>;

    return Recipe(
      id: _uuid.v4(),
      title: (parsed['title'] as String?)?.trim().isNotEmpty == true
          ? parsed['title'] as String
          : 'Unbenanntes Rezept',
      ingredients: _asStringList(parsed['ingredients']),
      steps: _asStringList(parsed['steps']),
      sourceUrl: sourceUrl,
      createdAt: DateTime.now(),
      servings: parsed['servings'] as String?,
      prepTimeMinutes: parsed['prepTimeMinutes'] is int
          ? parsed['prepTimeMinutes'] as int
          : int.tryParse('${parsed['prepTimeMinutes']}'),
      notes: parsed['notes'] as String?,
    );
  }

  Recipe _extractLocally({
    required String combinedText,
    required String titleHint,
    required String sourceUrl,
  }) {
    final lines = combinedText
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final ingredients = <String>[];
    final steps = <String>[];
    var mode = 'none';

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('zutat')) {
        mode = 'ingredients';
        continue;
      }
      if (lower.contains('zubereitung') ||
          lower.contains('anleitung') ||
          lower.contains('schritt')) {
        mode = 'steps';
        continue;
      }

      final cleaned = line
          .replaceFirst(RegExp(r'^(zutat(en)?|beschreibung|titel)\s*:\s*',
              caseSensitive: false), '')
          .trim();

      if (mode == 'ingredients' || _looksLikeIngredient(cleaned)) {
        ingredients.add(_stripBullet(cleaned));
        if (mode == 'none') mode = 'ingredients';
        continue;
      }
      if (mode == 'steps' || _looksLikeStep(cleaned)) {
        steps.add(_stripBullet(cleaned));
        if (mode == 'none') mode = 'steps';
      }
    }

    final title = titleHint.trim().isNotEmpty
        ? _cleanTitle(titleHint)
        : _guessTitleFromText(combinedText);

    if (ingredients.isEmpty && steps.isEmpty) {
      return _buildFallbackRecipe(title: title, sourceUrl: sourceUrl);
    }

    return Recipe(
      id: _uuid.v4(),
      title: title,
      ingredients: ingredients.isEmpty
          ? [
              'Zutaten waren im Video-Text nicht klar erkennbar.',
              'Tipp: Füge den Rezepttext aus dem Video ein oder hinterlege '
                  'einen KI-Schlüssel (OpenAI, Gemini oder Claude) in den Einstellungen.',
            ]
          : ingredients,
      steps: steps.isEmpty
          ? [
              'Öffne das Originalvideo und schaue die Zubereitung noch einmal an.',
              'Trage danach die Schritte manuell nach oder nutze die KI '
                  'mit API-Schlüssel für eine automatische Anleitung.',
            ]
          : steps,
      sourceUrl: sourceUrl,
      createdAt: DateTime.now(),
      notes:
          'Erstellt ohne KI-Schlüssel (lokale Auswertung). Für bessere '
          'Ergebnisse hinterlege unter Einstellungen einen KI-Schlüssel '
          '(OpenAI, Gemini oder Claude).',
    );
  }

  Recipe _buildFallbackRecipe({
    required String title,
    required String sourceUrl,
  }) {
    return Recipe(
      id: _uuid.v4(),
      title: title,
      ingredients: const [
        'Zutaten aus dem Video (noch ergänzen)',
        'Salz & Pfeffer nach Geschmack',
        'Öl oder Butter zum Anbraten',
      ],
      steps: const [
        'Alle Zutaten bereitstellen.',
        'Wie im Video vorbereiten und portionieren.',
        'Nach und nach zubereiten – bei Unsicherheit kurz das Video pausieren.',
        'Abschmecken und servieren.',
      ],
      sourceUrl: sourceUrl,
      createdAt: DateTime.now(),
      servings: '2–4 Portionen',
      prepTimeMinutes: 30,
      notes:
          'Platzhalter-Rezept: Viele Social-Media-Seiten liefern wenig Text. '
          'Am besten den Beschreibungstext aus dem Video einfügen oder einen '
          'KI-Schlüssel (OpenAI, Gemini oder Claude) in den Einstellungen '
          'hinterlegen.',
    );
  }

  Recipe buildDemoRecipe() {
    return Recipe(
      id: _uuid.v4(),
      title: 'Cremige Tomaten-Pasta (Beispiel)',
      ingredients: const [
        '300 g Spaghetti',
        '1 Dose Tomaten (stückig)',
        '1 Zwiebel',
        '2 Knoblauchzehen',
        '150 ml Sahne oder Kochsahne',
        '2 EL Olivenöl',
        'Salz, Pfeffer, italienische Kräuter',
        'Parmesan zum Bestreuen',
      ],
      steps: const [
        'Wasser salzen und Spaghetti nach Packungsangabe al dente kochen.',
        'Zwiebel und Knoblauch fein würfeln, in Olivenöl glasig anbraten.',
        'Tomaten hinzugeben, 5–8 Minuten köcheln lassen.',
        'Sahne einrühren, mit Salz, Pfeffer und Kräutern abschmecken.',
        'Abgegossene Pasta untermengen und mit Parmesan servieren.',
      ],
      sourceUrl: '',
      createdAt: DateTime.now(),
      servings: '2 Portionen',
      prepTimeMinutes: 25,
      notes: 'Beispielrezept zum Ausprobieren der App.',
    );
  }

  /// Verständliche Meldung für KI-API-Fehlercodes.
  String _aiErrorMessage(AiProvider provider, int statusCode, String body) {
    final name = provider.label;
    final lower = body.toLowerCase();
    final quotaEmpty = lower.contains('insufficient_quota') ||
        lower.contains('billing') ||
        lower.contains('exceeded your current quota') ||
        lower.contains('credit') ||
        lower.contains('resource_exhausted');
    final rateLimited = lower.contains('rate_limit') ||
        lower.contains('rate limit') ||
        lower.contains('too many');

    switch (statusCode) {
      case 401:
      case 403:
        return '$name-Schlüssel ungültig oder ohne Berechtigung. '
            'Bitte unter Einstellungen prüfen und neu speichern.';
      case 429:
        if (quotaEmpty) {
          return '$name-Guthaben / Kontingent ist leer (429). '
              'Im $name-Konto Guthaben bzw. Limits prüfen — '
              'der Schlüssel selbst kann stimmen.';
        }
        if (rateLimited) {
          return 'Zu viele Anfragen bei $name (429). '
              'Bitte 1–2 Minuten warten und erneut versuchen.';
        }
        return '$name meldet Limit erreicht (429). '
            'Meist: Guthaben leer oder zu viele Anfragen. '
            'Nicht zwingend der API-Schlüssel.';
      case 500:
      case 502:
      case 503:
        return '$name ist gerade gestört ($statusCode). '
            'Bitte später nochmal versuchen.';
      default:
        return 'KI-Anfrage bei $name fehlgeschlagen ($statusCode). '
            'Falls der Schlüssel neu ist: unter Einstellungen prüfen. '
            'Sonst später erneut versuchen.';
    }
  }

  List<String> _asStringList(dynamic value) {
    if (value is! List) return [];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  String? _extractFirstUrl(String text) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(text);
    return match?.group(0)?.replaceAll(RegExp(r'[),.;]+$'), '');
  }

  String _guessTitleFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Geteiltes Rezeptvideo';
    final host = uri.host.replaceFirst(RegExp(r'^www\.'), '');
    return 'Rezept von $host';
  }

  String _guessTitleFromText(String text) {
    final first = text
        .split(RegExp(r'[\n\r]+'))
        .map((e) => e.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => 'Neues Rezept');
    return _cleanTitle(first.replaceFirst(RegExp(r'^Titel:\s*'), ''));
  }

  String _cleanTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\|.*$'), '')
        .trim();
  }

  bool _looksLikeIngredient(String line) {
    if (line.length < 3 || line.length > 120) return false;
    return RegExp(
      r'^(\d+[.,]?\d*\s*(g|kg|ml|l|el|tl|prise|stück)|[-•*])',
      caseSensitive: false,
    ).hasMatch(line);
  }

  bool _looksLikeStep(String line) {
    if (line.length < 12) return false;
    return RegExp(r'^(\d+[.)]\s+|schritt\s*\d+)', caseSensitive: false)
            .hasMatch(line) ||
        RegExp(r'\b(braten|kochen|mischen|rühren|backen|würzen|servieren)\b',
                caseSensitive: false)
            .hasMatch(line);
  }

  String _stripBullet(String line) {
    return line
        .replaceFirst(RegExp(r'^(\d+[.)]\s+|[-•*]\s+|schritt\s*\d+:\s*)',
            caseSensitive: false), '')
        .trim();
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      final t = value.trim();
      if (t.isNotEmpty) return t;
    }
    return '';
  }

  String _metaContent(String html, String property) {
    final patterns = [
      RegExp(
        'property=["\']$property["\'][^>]*content=["\']([^"\']+)["\']',
        caseSensitive: false,
      ),
      RegExp(
        'content=["\']([^"\']+)["\'][^>]*property=["\']$property["\']',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return _decodeHtml(match.group(1)!);
    }
    return '';
  }

  String _metaName(String html, String name) {
    final patterns = [
      RegExp(
        'name=["\']$name["\'][^>]*content=["\']([^"\']+)["\']',
        caseSensitive: false,
      ),
      RegExp(
        'content=["\']([^"\']+)["\'][^>]*name=["\']$name["\']',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) return _decodeHtml(match.group(1)!);
    }
    return '';
  }

  String _tagText(String html, String tag) {
    final match = RegExp(
      '<$tag[^>]*>([^<]*)</$tag>',
      caseSensitive: false,
    ).firstMatch(html);
    return match == null ? '' : _decodeHtml(match.group(1)!);
  }

  String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          return code == null ? m.group(0)! : String.fromCharCode(code);
        });
  }
}
