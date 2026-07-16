import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/ai_provider.dart';
import '../models/recipe.dart';
import 'media_transcript.dart';

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
  RecipeExtractor({
    http.Client? client,
    MediaTranscriptService? transcripts,
  })  : _client = client ?? http.Client(),
        _transcripts = transcripts ?? MediaTranscriptService(client: client);

  final http.Client _client;
  final MediaTranscriptService _transcripts;
  final _uuid = const Uuid();

  /// Zieht Titel und Beschreibung aus einem Link (z. B. Facebook/Instagram).
  Future<PagePreview> fetchPagePreview(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw Exception('Das sieht nicht nach einem gültigen Link aus.');
    }

    final host = uri.host.replaceFirst('www.', '').toLowerCase();
    final isFacebook =
        host.contains('facebook.com') || host == 'fb.watch' || host == 'fb.com';

    // Facebook liefert Meta-Daten oft nur an Crawler-User-Agents.
    final userAgents = <String>[
      if (isFacebook)
        'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)',
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    ];

    for (final userAgent in userAgents) {
      try {
        final response = await _client
            .get(
              uri,
              headers: {
                'User-Agent': userAgent,
                'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
                'Accept': 'text/html,application/xhtml+xml',
              },
            )
            .timeout(const Duration(seconds: 18));

        if (response.statusCode < 200 || response.statusCode >= 400) {
          continue;
        }

        final html = response.body;
        if (html.contains('Error Facebook') &&
            !html.contains('og:title')) {
          continue;
        }

        final title = _firstNonEmpty([
          _metaContent(html, 'og:title'),
          _metaName(html, 'title'),
          _tagText(html, 'title'),
        ]);
        // Facebook: og:description ist oft mit „…“ abgeschnitten —
        // og:title / og:image:alt enthalten den vollen Text.
        final description = isFacebook
            ? _bestFacebookCaption(html)
            : _firstNonEmpty([
                _metaContent(html, 'og:description'),
                _metaName(html, 'description'),
                _metaName(html, 'twitter:description'),
              ]);
        final canonical = _firstNonEmpty([
          _metaContent(html, 'og:url'),
          url,
        ]);

        if (title.isEmpty && description.isEmpty) continue;

        return PagePreview(
          url: canonical.isNotEmpty ? canonical : url,
          title: title,
          description: description,
        );
      } catch (_) {
        // Nächsten User-Agent versuchen.
      }
    }

    return PagePreview(
      url: url,
      title: _guessTitleFromUrl(url),
      description: '',
    );
  }

  /// Erstellt ein Rezept aus Link, Caption-Text, optional Video/Ton.
  /// Mit API-Schlüssel: KI nutzt alle Quellen und ergänzt fehlende Infos.
  Future<Recipe> extractRecipe({
    required String sourceText,
    String? sourceUrl,
    String? captionText,
    String? apiKey,
    AiProvider provider = AiProvider.openai,
    bool useAi = true,
    Uint8List? videoBytes,
    String? videoMimeType,
    String? videoFileName,
  }) async {
    final trimmed = sourceText.trim();
    final caption = (captionText ?? '').trim();
    final hasVideo = videoBytes != null && videoBytes.isNotEmpty;

    if (trimmed.isEmpty &&
        caption.isEmpty &&
        !hasVideo &&
        (sourceUrl == null || sourceUrl.trim().isEmpty)) {
      throw Exception(
        'Bitte Link, den Text unter dem Video, oder ein Video hinzufügen.',
      );
    }

    var url = sourceUrl?.trim() ?? '';
    var preview = PagePreview(url: url, title: '', description: '');

    if (url.isEmpty) {
      final found = _extractFirstUrl(trimmed.isNotEmpty ? trimmed : caption);
      if (found != null) url = found;
    }

    if (url.isNotEmpty) {
      preview = await fetchPagePreview(url);
      // Facebook liefert oft den Reel-Canonical in og:url — den bevorzugen.
      if (preview.url.isNotEmpty && preview.url != url) {
        url = preview.url;
      }
    }

    // Wenn niemand Caption eingefügt hat: Meta-Beschreibung vom Link nutzen.
    var effectiveCaption = caption;
    if (effectiveCaption.isEmpty || _looksTruncatedCaption(effectiveCaption)) {
      final fromMeta = preview.description.trim();
      if (fromMeta.length > effectiveCaption.length) {
        effectiveCaption = fromMeta;
      }
    }
    if (effectiveCaption.isEmpty &&
        preview.title.trim().isNotEmpty &&
        !_isUselessDishTitle(_cleanTitle(_stripPlatformSuffix(preview.title)))) {
      effectiveCaption = _stripFacebookViewsPrefix(preview.title).trim();
    }

    // YouTube: Untertitel / Transkript vom Ton laden.
    String? autoTranscript;
    if (url.isNotEmpty && _looksLikeYoutube(url)) {
      autoTranscript = await _transcripts.fetchYoutubeTranscript(url);
    }

    // Angehängtes Video: mit Whisper (OpenAI) Ton → Text, falls kein Gemini-Video.
    String? whisperTranscript;
    if (hasVideo &&
        useAi &&
        apiKey != null &&
        apiKey.trim().isNotEmpty &&
        provider == AiProvider.openai) {
      try {
        whisperTranscript = await _transcripts.transcribeWithWhisper(
          bytes: videoBytes,
          filename: videoFileName ?? 'recipe-video.mp4',
          apiKey: apiKey.trim(),
        );
      } catch (_) {
        // Weiter mit Textquellen; Fehler hängt die KI-Route ggf. später an.
      }
    }

    final sources = _buildSourceBlocks(
      preview: preview,
      url: url,
      pastedText: trimmed,
      caption: effectiveCaption,
      youtubeTranscript: autoTranscript,
      whisperTranscript: whisperTranscript,
    );

    final dishTitle = _bestDishTitle(
      pageTitle: preview.title,
      caption: effectiveCaption,
      pastedText: trimmed,
      youtubeTranscript: autoTranscript,
      whisperTranscript: whisperTranscript,
    );

    final combinedForAi = [
      'Aufgabe: Erstelle ein vollständiges, nachkochbares Rezept.',
      'Nutze ALLE folgenden Quellen gemeinsam (Video-Beschreibung, '
          'Untertitel/Ton, Link-Infos).',
      'WICHTIG: Erfinde KEIN anderes Gericht. Wenn Quellen einen '
          'Gerichtsnamen nennen (z. B. „High Protein Döner Wrap“), '
          'muss title genau dazu passen.',
      'Schreibe korrektes Deutsch mit ä, ö, ü und ß '
          '(nicht „Hhnchen“ oder „Gemsebrhe“).',
      'Erfinde KEIN „klassisches Ersatzrezept“ (z. B. Frikadellen, '
          'irgendetwas Beliebtes), nur weil Details fehlen.',
      'Fehlen Mengen/Zeiten/Schritte zum genannten Gericht: typische '
          'Zubereitung genau für DIESES Gericht ergänzen und in notes '
          'kurz vermerken, was geschätzt wurde.',
      'Steht in den Quellen wirklich gar kein Gericht: dann title '
          '„Rezept ergänzen“, kurze Platzhalter-Zutaten/Schritte und in '
          'notes bitten, Caption oder Video nachzutragen.',
      'Widersprüche: der klarere/aktuellere Hinweis gewinnt '
          '(meist gesprochener Text + Caption).',
      'WICHTIG für title: klarer deutscher Gerichtsname. '
          'Niemals Plattformnamen wie Facebook, Instagram, TikTok oder '
          '„Rezept von …“ als Titel.',
      if (dishTitle != 'Neues Rezept')
        'Der Gerichtsname aus den Quellen lautet: „$dishTitle“. '
            'Nutze diesen Namen (oder eine klare deutsche Variante davon).',
      '',
      sources,
    ].join('\n');

    Recipe local() => _extractLocally(
          combinedText: sources,
          titleHint: dishTitle,
          sourceUrl: url,
        );

    if (!useAi || apiKey == null || apiKey.trim().isEmpty) {
      return local();
    }

    try {
      // Gemini: Video direkt mitschicken (sieht + hört mit).
      if (hasVideo && provider == AiProvider.gemini) {
        return await _extractWithGeminiVideo(
          combinedText: combinedForAi,
          sourceUrl: url,
          apiKey: apiKey.trim(),
          videoBytes: videoBytes,
          videoMimeType: videoMimeType ?? 'video/mp4',
        );
      }

      return await _extractWithAi(
        provider: provider,
        combinedText: combinedForAi,
        sourceUrl: url,
        apiKey: apiKey.trim(),
      );
    } catch (e) {
      final fallback = local();
      final reason = e.toString().replaceFirst('Exception: ', '');
      return fallback.copyWith(
        notes: [
          'KI war gerade nicht nutzbar ($reason).',
          'Deshalb wurde eine einfache Auswertung ohne KI erstellt.',
          'Du kannst Zutaten und Schritte danach selbst ergänzen.',
          if (fallback.notes != null && fallback.notes!.isNotEmpty)
            fallback.notes!,
        ].join('\n'),
      );
    }
  }

  String _buildSourceBlocks({
    required PagePreview preview,
    required String url,
    required String pastedText,
    required String caption,
    String? youtubeTranscript,
    String? whisperTranscript,
  }) {
    final parts = <String>[];

    if (url.isNotEmpty) parts.add('Quelle (Link): $url');
    if (preview.title.isNotEmpty) parts.add('Seitentitel: ${preview.title}');
    if (preview.description.isNotEmpty) {
      parts.add('Seitenbeschreibung / Meta-Text:\n${preview.description}');
    }
    if (caption.isNotEmpty) {
      parts.add('Text unter dem Video (Caption / Beschreibung):\n$caption');
    }
    if (pastedText.isNotEmpty) {
      parts.add('Eingefügter Text / geteilter Inhalt:\n$pastedText');
    }
    if (youtubeTranscript != null && youtubeTranscript.trim().isNotEmpty) {
      parts.add(
        'Gesprochener Text / Untertitel aus dem Video:\n'
        '${youtubeTranscript.trim()}',
      );
    }
    if (whisperTranscript != null && whisperTranscript.trim().isNotEmpty) {
      parts.add(
        'Aus dem Video-Ton transkribierter Text:\n'
        '${whisperTranscript.trim()}',
      );
    }
    return parts.join('\n\n');
  }

  bool _looksLikeYoutube(String url) {
    final host = Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? '';
    return host.contains('youtube.com') || host == 'youtu.be';
  }

  /// Liest ein abfotografiertes Papier-Rezept mit KI aus (Bild → Rezept).
  Future<Recipe> extractRecipeFromImage({
    required Uint8List imageBytes,
    required String mimeType,
    required String apiKey,
    AiProvider provider = AiProvider.gemini,
  }) async {
    final b64 = base64Encode(imageBytes);
    final prompt =
        'Lies dieses Foto eines handgeschriebenen oder gedruckten Rezepts. '
        'Erstelle daraus ein nachkochbares Rezept. $_systemPrompt';

    switch (provider) {
      case AiProvider.openai:
        return _extractImageWithOpenAi(
          prompt: prompt,
          mimeType: mimeType,
          b64: b64,
          apiKey: apiKey,
        );
      case AiProvider.gemini:
        return _extractImageWithGemini(
          prompt: prompt,
          mimeType: mimeType,
          b64: b64,
          apiKey: apiKey,
        );
      case AiProvider.claude:
        return _extractImageWithClaude(
          prompt: prompt,
          mimeType: mimeType,
          b64: b64,
          apiKey: apiKey,
        );
    }
  }

  Future<Recipe> _extractImageWithOpenAi({
    required String prompt,
    required String mimeType,
    required String b64,
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
              {
                'role': 'user',
                'content': [
                  {'type': 'text', 'text': prompt},
                  {
                    'type': 'image_url',
                    'image_url': {
                      'url': 'data:$mimeType;base64,$b64',
                    },
                  },
                ],
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _aiErrorMessage(AiProvider.openai, response.statusCode, response.body),
      );
    }

    final body = jsonDecode(_utf8Body(response)) as Map<String, dynamic>;
    final content =
        (body['choices'] as List).first['message']['content'] as String;
    return _recipeFromAiJson(content, '');
  }

  Future<Recipe> _extractImageWithGemini({
    required String prompt,
    required String mimeType,
    required String b64,
    required String apiKey,
  }) async {
    final body = await _postGeminiGenerateContent(
      apiKey: apiKey,
      payload: {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': mimeType,
                  'data': b64,
                },
              },
            ],
          },
        ],
        'generationConfig': _geminiJsonGenerationConfig(),
      },
      timeout: const Duration(seconds: 60),
    );
    return _recipeFromAiJson(_geminiAnswerText(body), '');
  }

  Future<Recipe> _extractImageWithClaude({
    required String prompt,
    required String mimeType,
    required String b64,
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
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'type': 'image',
                    'source': {
                      'type': 'base64',
                      'media_type': mimeType,
                      'data': b64,
                    },
                  },
                  {'type': 'text', 'text': prompt},
                ],
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _aiErrorMessage(AiProvider.claude, response.statusCode, response.body),
      );
    }

    final body = jsonDecode(_utf8Body(response)) as Map<String, dynamic>;
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
    return _recipeFromAiJson(text, '');
  }

  /// Manuelles Rezept ohne KI (immer möglich).
  Recipe buildManualRecipe({
    required String title,
    required List<String> ingredients,
    required List<String> steps,
    String? servings,
    String? notes,
  }) {
    final cleanTitle = title.trim().isEmpty ? 'Mein Rezept' : title.trim();
    final cleanIngredients = ingredients
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final cleanSteps =
        steps.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    return Recipe(
      id: _uuid.v4(),
      title: cleanTitle,
      ingredients: cleanIngredients.isEmpty
          ? ['Zutaten noch ergänzen']
          : cleanIngredients,
      steps: cleanSteps.isEmpty
          ? ['Schritte noch ergänzen']
          : cleanSteps,
      sourceUrl: '',
      createdAt: DateTime.now(),
      servings: servings?.trim().isEmpty == true ? null : servings?.trim(),
      notes: notes?.trim().isEmpty == true
          ? 'Manuell erfasst (ohne KI).'
          : notes?.trim(),
    );
  }

  static const _systemPrompt =
      'Du hilfst beim Nachkochen von Rezeptvideos. '
      'Antworte NUR als JSON mit den Feldern: '
      'title (string), servings (string|null), '
      'prepTimeMinutes (number|null), '
      'ingredients (string[]), steps (string[]), '
      'notes (string|null). '
      'Sprache: korrektes Deutsch mit Umlauten. '
      'WICHTIG: Immer ä, ö, ü und ß schreiben. '
      'Falsch: „Hhnchen“, „Gemsebrhe“, „Hirtenkse“, „fr“, „geschtzt“. '
      'Richtig: „Hähnchen“, „Gemüsebrühe“, „Hirtenkäse“, „für“, „geschätzt“. '
      'title MUSS dem Gericht aus den Quellen entsprechen '
      '(z. B. „High Protein Döner Wrap“, „Knoblauch-Garnelen“). '
      'Niemals Facebook/Instagram/TikTok/YouTube oder „Rezept von …“ '
      'als title. '
      'Niemals ein anderes klassisches Rezept erfinden, nur weil der '
      'Link wenig Text enthält. '
      'Nutze Caption, Transkript und Meta-Text gemeinsam. '
      'Fehlende Mengen/Zeiten/Schritte nur für das genannte Gericht '
      'sinnvoll ergänzen und in notes als Schätzung markieren. '
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

  Future<Recipe> _extractWithGeminiVideo({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
    required Uint8List videoBytes,
    required String videoMimeType,
  }) async {
    final body = await _postGeminiGenerateContent(
      apiKey: apiKey,
      payload: {
        'systemInstruction': {
          'parts': [
            {'text': _systemPrompt},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {
                'text':
                    'Im Anhang ist das Rezeptvideo (Bild + Ton). '
                    'Berücksichtige Video, Ton und diesen Text:\n'
                    '$combinedText',
              },
              {
                'inline_data': {
                  'mime_type': videoMimeType,
                  'data': base64Encode(videoBytes),
                },
              },
            ],
          },
        ],
        'generationConfig': _geminiJsonGenerationConfig(),
      },
      timeout: const Duration(seconds: 90),
    );
    return _recipeFromAiJson(_geminiAnswerText(body), sourceUrl);
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

    final body = jsonDecode(_utf8Body(response)) as Map<String, dynamic>;
    final content =
        (body['choices'] as List).first['message']['content'] as String;
    return _recipeFromAiJson(content, sourceUrl);
  }

  Future<Recipe> _extractWithGemini({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
  }) async {
    final body = await _postGeminiGenerateContent(
      apiKey: apiKey,
      payload: {
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
        'generationConfig': _geminiJsonGenerationConfig(),
      },
      timeout: const Duration(seconds: 45),
    );
    return _recipeFromAiJson(_geminiAnswerText(body), sourceUrl);
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

    final body = jsonDecode(_utf8Body(response)) as Map<String, dynamic>;
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

  /// Modelle der Reihe nach — bei 503/Überlastung das nächste versuchen.
  static const _geminiModels = <String>[
    'gemini-3.5-flash',
    'gemini-2.5-flash',
    'gemini-2.0-flash',
  ];

  /// Gemini-JSON-Config: festes Schema + wenig „Mitdenken“,
  /// damit die Antwort nicht kaputt gemischt wird.
  Map<String, dynamic> _geminiJsonGenerationConfig() {
    return {
      'maxOutputTokens': 4096,
      'responseMimeType': 'application/json',
      'thinkingConfig': {
        'thinkingLevel': 'MINIMAL',
      },
      'responseSchema': {
        'type': 'OBJECT',
        'properties': {
          'title': {'type': 'STRING'},
          'servings': {
            'type': 'STRING',
            'nullable': true,
          },
          'prepTimeMinutes': {
            'type': 'INTEGER',
            'nullable': true,
          },
          'ingredients': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'steps': {
            'type': 'ARRAY',
            'items': {'type': 'STRING'},
          },
          'notes': {
            'type': 'STRING',
            'nullable': true,
          },
        },
        'required': ['title', 'ingredients', 'steps'],
      },
    };
  }

  /// Gemini mit Retry (503/429) und Ersatz-Modellen.
  Future<Map<String, dynamic>> _postGeminiGenerateContent({
    required String apiKey,
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    Exception? lastError;

    for (final model in _geminiModels) {
      for (var attempt = 0; attempt < 3; attempt++) {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '$model:generateContent',
        );

        late final http.Response response;
        try {
          final requestPayload = _payloadForGeminiModel(model, payload);
          response = await _client
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json; charset=utf-8',
                  'x-goog-api-key': apiKey,
                  'Accept': 'application/json',
                },
                body: utf8.encode(jsonEncode(requestPayload)),
              )
              .timeout(timeout);
        } catch (e) {
          lastError = Exception(
            'Gemini-Netzwerkfehler. Bitte Verbindung prüfen und erneut versuchen.',
          );
          await Future<void>.delayed(
            Duration(milliseconds: 700 * (attempt + 1)),
          );
          continue;
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return jsonDecode(_utf8Body(response)) as Map<String, dynamic>;
        }

        final retriable = response.statusCode == 429 ||
            response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503;
        final modelMissing = response.statusCode == 404;

        lastError = Exception(
          _aiErrorMessage(
            AiProvider.gemini,
            response.statusCode,
            _utf8Body(response),
          ),
        );

        if (modelMissing) break; // nächstes Modell
        if (!retriable) throw lastError;
        await Future<void>.delayed(
          Duration(milliseconds: 700 * (attempt + 1)),
        );
      }
    }

    throw lastError ??
        Exception(
          'Gemini ist gerade nicht erreichbar. Bitte später erneut versuchen.',
        );
  }

  /// Nur den echten Antwort-Text nehmen — Denk-Texte von Gemini ignorieren.
  String _geminiAnswerText(Map<String, dynamic> body) {
    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception(
        'Gemini hat keine Antwort geliefert. Bitte erneut versuchen.',
      );
    }
    final first = Map<String, dynamic>.from(candidates.first as Map);
    final parts = first['content'] is Map
        ? (first['content'] as Map)['parts'] as List?
        : null;
    if (parts == null || parts.isEmpty) {
      throw Exception('Gemini-Antwort war leer. Bitte erneut versuchen.');
    }

    final answerTexts = <String>[];
    final anyTexts = <String>[];
    for (final part in parts) {
      if (part is! Map) continue;
      final text = part['text']?.toString() ?? '';
      if (text.trim().isEmpty) continue;
      anyTexts.add(text);
      if (part['thought'] == true) continue;
      answerTexts.add(text);
    }

    final text =
        (answerTexts.isNotEmpty ? answerTexts : anyTexts).join().trim();
    if (text.isEmpty) {
      throw Exception('Gemini-Antwort war leer. Bitte erneut versuchen.');
    }

    final finish = first['finishReason']?.toString() ?? '';
    if (finish == 'MAX_TOKENS' || finish == 'LENGTH') {
      // Trotzdem versuchen zu parsen; bei Fehler klarere Meldung.
      try {
        _decodeAiJsonObject(text);
      } catch (_) {
        throw Exception(
          'Gemini-Antwort wurde abgeschnitten. '
          'Bitte Caption kürzen und erneut versuchen.',
        );
      }
    }
    return text;
  }

  /// Robustes JSON lesen (auch mit ```json … ``` oder Text drumherum).
  Map<String, dynamic> _decodeAiJsonObject(String raw) {
    var cleaned = raw.trim();
    cleaned = cleaned
        .replaceFirst(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s*```\s*$'), '')
        .trim();

    Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } catch (_) {
      final start = cleaned.indexOf('{');
      final end = cleaned.lastIndexOf('}');
      if (start < 0 || end <= start) {
        throw const FormatException(
          'KI-Antwort war kein gültiges JSON-Rezept.',
        );
      }
      decoded = jsonDecode(cleaned.substring(start, end + 1));
    }

    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('KI-Antwort war kein JSON-Objekt.');
  }

  @visibleForTesting
  Recipe parseAiRecipeJson(String raw, [String sourceUrl = '']) {
    return _recipeFromAiJson(raw, sourceUrl);
  }

  @visibleForTesting
  String readGeminiAnswerText(Map<String, dynamic> body) {
    return _geminiAnswerText(body);
  }

  @visibleForTesting
  String cleanDishTitleForTest(String title) {
    return _cleanTitle(_stripPlatformSuffix(title));
  }

  @visibleForTesting
  String decodeHtmlForTest(String value) => _decodeHtml(value);

  Recipe _recipeFromAiJson(String raw, String sourceUrl) {
    final parsed = _decodeAiJsonObject(raw);

    var title = (parsed['title'] as String?)?.trim() ?? '';
    title = _fixGermanSpelling(_cleanTitle(_stripPlatformSuffix(title)));
    if (title.isEmpty || _isUselessDishTitle(title)) {
      title = 'Neues Rezept';
    }

    final servingsRaw = parsed['servings'];
    final servings = servingsRaw == null
        ? null
        : servingsRaw.toString().trim().isEmpty
            ? null
            : _fixGermanSpelling(servingsRaw.toString().trim());

    final notesRaw = parsed['notes'];
    final notes = notesRaw == null
        ? null
        : notesRaw.toString().trim().isEmpty
            ? null
            : _fixGermanSpelling(notesRaw.toString().trim());

    return Recipe(
      id: _uuid.v4(),
      title: title,
      ingredients: _asStringList(parsed['ingredients'])
          .map(_fixGermanSpelling)
          .toList(),
      steps: _asStringList(parsed['steps']).map(_fixGermanSpelling).toList(),
      sourceUrl: sourceUrl,
      createdAt: DateTime.now(),
      servings: servings,
      prepTimeMinutes: parsed['prepTimeMinutes'] is int
          ? parsed['prepTimeMinutes'] as int
          : int.tryParse('${parsed['prepTimeMinutes']}'),
      notes: notes,
    );
  }

  /// Antwort immer als UTF-8 lesen (sonst fehlen Umlaute auf manchen Geräten).
  String _utf8Body(http.Response response) {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  /// Häufige KI-Fehler ohne Umlaute korrigieren (Hhnchen → Hähnchen).
  @visibleForTesting
  String fixGermanSpellingForTest(String text) => _fixGermanSpelling(text);

  String _fixGermanSpelling(String text) {
    if (text.isEmpty) return text;
    var out = text;

    // Längere / spezifischere Ersetzungen zuerst.
    const replacements = <String, String>{
      'Hhnchenbrustfilet': 'Hähnchenbrustfilet',
      'hhnchenbrustfilet': 'Hähnchenbrustfilet',
      'Hhnchenfleisch': 'Hähnchenfleisch',
      'hhnchenfleisch': 'Hähnchenfleisch',
      'Hhnchenbrust': 'Hähnchenbrust',
      'Hhnchen': 'Hähnchen',
      'hhnchen': 'hähnchen',
      'H hnchen': 'Hähnchen',
      'h hnchen': 'hähnchen',
      'Gemsebrhe': 'Gemüsebrühe',
      'gemsebrhe': 'Gemüsebrühe',
      'Gemse': 'Gemüse',
      'gemse': 'Gemüse',
      'Hirtenkse': 'Hirtenkäse',
      'hirtenkse': 'Hirtenkäse',
      'Schafskse': 'Schafskäse',
      'Frischkse': 'Frischkäse',
      'Reibekse': 'Reibekäse',
      'Olivenl': 'Olivenöl',
      'olivenl': 'Olivenöl',
      'Sonnenblumenl': 'Sonnenblumenöl',
      'Rapsel': 'Rapsöl',
      'Mehlschwitze': 'Mehlschwitze',
      'geschtzt': 'geschätzt',
      'Geschtzt': 'Geschätzt',
      'zerbrseln': 'zerbröseln',
      'Zerbrseln': 'Zerbröseln',
      'unterrhren': 'unterrühren',
      'Unterrhren': 'Unterrühren',
      'andnsten': 'andünsten',
      'Andnsten': 'Andünsten',
      'anbraten': 'anbraten',
      'Flssigkeit': 'Flüssigkeit',
      'flssigkeit': 'Flüssigkeit',
      'kcheln': 'köcheln',
      'Kcheln': 'Köcheln',
      'wrzen': 'würzen',
      'Wrzen': 'Würzen',
      'abgeschmeckt': 'abgeschmeckt',
      'Zwiebelwfel': 'Zwiebelwürfel',
      'mundgerechte Stcke': 'mundgerechte Stücke',
      'Stcke': 'Stücke',
      'stcke': 'Stücke',
      'groen': 'großen',
      'Groen': 'Großen',
      'groe ': 'große ',
      'Groe ': 'Große ',
      'Dner': 'Döner',
      'dner': 'Döner',
      'D ner': 'Döner',
      'berbacken': 'überbacken',
      'berbrhen': 'überbrühen',
      'berall': 'überall',
      'hinzufgen': 'hinzufügen',
      'Hinzufgen': 'Hinzufügen',
      'glasiert': 'glasiert',
      'schwenken': 'schwenken',
      'nchsten': 'nächsten',
      'Nchsten': 'Nächsten',
      'gertet': 'gerätet',
      'Kse ': 'Käse ',
      ' kse': ' Käse',
      'Kse.': 'Käse.',
      'Kse,': 'Käse,',
    };

    for (final entry in replacements.entries) {
      out = out.replaceAll(entry.key, entry.value);
    }

    // Häufiges kleines Wort „fr“ → „für“ (nur als ganzes Wort).
    out = out.replaceAllMapped(
      RegExp(r'\bfr\b'),
      (_) => 'für',
    );
    out = out.replaceAllMapped(
      RegExp(r'\bFr\b'),
      (_) => 'Für',
    );

    return out;
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

    final title = () {
      final fromHint = titleHint.trim().isNotEmpty
          ? _cleanTitle(_stripPlatformSuffix(titleHint))
          : '';
      if (fromHint.isNotEmpty && !_isUselessDishTitle(fromHint)) {
        return fromHint;
      }
      final fromText = _guessTitleFromText(combinedText);
      if (!_isUselessDishTitle(fromText)) return fromText;
      return 'Neues Rezept';
    }();

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

  /// Seiten-/Plattform-Titel, die kein Gerichtsname sind.
  bool _isUselessDishTitle(String title) {
    final t = title.trim().toLowerCase();
    if (t.isEmpty) return true;
    if (t.startsWith('rezept von ')) return true;
    if (RegExp(
      r'^(facebook|instagram|tiktok|youtube|fb\.watch|youtu\.be)'
      r'(\.com)?$',
    ).hasMatch(t)) {
      return true;
    }
    if (RegExp(
      r'^(watch|reel|reels|video|shared (post|video)|beitrag|geteilt)$',
    ).hasMatch(t)) {
      return true;
    }
    // „Something | Facebook“ ohne echten Namen
    if (RegExp(r'^\s*(watch|reel|video)?\s*\|?\s*(facebook|instagram|tiktok)\s*$')
        .hasMatch(t)) {
      return true;
    }
    return false;
  }

  /// Facebook & Co. hängen oft „| Facebook“ an — entfernen.
  String _stripPlatformSuffix(String title) {
    return title
        .replaceAll(
          RegExp(
            r'\s*[\|\-–—]\s*(Facebook|Instagram|TikTok|YouTube|Watch)\s*$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  /// Bester Titel aus Meta, Caption und Text — nie „Rezept von facebook.com“.
  String _bestDishTitle({
    required String pageTitle,
    required String caption,
    required String pastedText,
    String? youtubeTranscript,
    String? whisperTranscript,
  }) {
    final candidates = <String>[];

    void add(String? value) {
      if (value == null) return;
      final cleaned = _cleanTitle(_stripPlatformSuffix(value));
      if (cleaned.isEmpty || _isUselessDishTitle(cleaned)) return;
      if (cleaned.toLowerCase() == 'neues rezept') return;
      if (!candidates.contains(cleaned)) candidates.add(cleaned);
    }

    // Caption & eingefügter Text zuerst — dort steht meist der Gerichtsname.
    for (final block in [caption, pastedText]) {
      for (final line in block.split(RegExp(r'[\n\r]+'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (trimmed.startsWith('http')) continue;
        if (trimmed.startsWith('#')) continue;
        final titled = RegExp(
          r'^Titel\s*:\s*(.+)$',
          caseSensitive: false,
        ).firstMatch(trimmed);
        if (titled != null) {
          add(titled.group(1));
          break;
        }
        if (trimmed.length >= 3 &&
            trimmed.length <= 80 &&
            !_looksLikeIngredient(trimmed) &&
            !_looksLikeStep(trimmed)) {
          add(trimmed);
          break;
        }
      }
    }

    add(pageTitle);

    for (final transcript in [youtubeTranscript, whisperTranscript]) {
      if (transcript == null || transcript.trim().isEmpty) continue;
      final firstSentences = transcript
          .split(RegExp(r'[.!?\n]'))
          .map((e) => e.trim())
          .where((e) => e.length >= 8 && e.length <= 80)
          .toList();
      if (firstSentences.isNotEmpty) add(firstSentences.first);
    }

    if (candidates.isNotEmpty) return candidates.first;
    return 'Neues Rezept';
  }

  String _guessTitleFromUrl(String url) {
    // Früher: „Rezept von facebook.com“ — das ist kein Gerichtsname.
    return 'Neues Rezept';
  }

  String _guessTitleFromText(String text) {
    final lines = text
        .split(RegExp(r'[\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    for (final line in lines) {
      final titled = RegExp(
        r'^Titel\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (titled != null) {
        return _cleanTitle(titled.group(1)!);
      }
    }

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('quelle') ||
          lower.startsWith('seitentitel') ||
          lower.startsWith('seitenbeschreibung') ||
          lower.startsWith('text unter dem video') ||
          lower.startsWith('eingefügter text') ||
          lower.startsWith('gesprochener text') ||
          lower.startsWith('aus dem video-ton') ||
          lower.startsWith('zutat') ||
          lower.startsWith('zubereitung') ||
          lower.startsWith('anleitung')) {
        continue;
      }
      return _cleanTitle(line.replaceFirst(RegExp(r'^Titel:\s*'), ''));
    }

    return 'Neues Rezept';
  }

  /// Ältere Gemini-Modelle verstehen thinkingConfig nicht.
  Map<String, dynamic> _payloadForGeminiModel(
    String model,
    Map<String, dynamic> payload,
  ) {
    if (model.startsWith('gemini-3')) return payload;
    final copy = Map<String, dynamic>.from(payload);
    final gen = copy['generationConfig'];
    if (gen is Map) {
      final genCopy = Map<String, dynamic>.from(gen);
      genCopy.remove('thinkingConfig');
      copy['generationConfig'] = genCopy;
    }
    return copy;
  }

  String _bestFacebookCaption(String html) {
    final candidates = [
      _metaContent(html, 'og:image:alt'),
      _metaContent(html, 'og:title'),
      _metaName(html, 'twitter:image:alt'),
      _metaContent(html, 'og:description'),
      _metaName(html, 'description'),
      _metaName(html, 'twitter:description'),
    ]
        .map(_stripFacebookViewsPrefix)
        .map((e) => e.trim())
        .where((e) => e.length >= 8)
        .toList();

    if (candidates.isEmpty) return '';

    final complete =
        candidates.where((e) => !_looksTruncatedCaption(e)).toList();
    final pool = complete.isNotEmpty ? complete : candidates;
    pool.sort((a, b) => b.length.compareTo(a.length));
    return pool.first;
  }

  bool _looksTruncatedCaption(String text) {
    final t = text.trim();
    if (t.isEmpty) return true;
    return RegExp(r'\.\.\.\s*$').hasMatch(t) || t.endsWith('…');
  }

  String _stripFacebookViewsPrefix(String raw) {
    var t = raw.replaceAll('\r', '').trim();
    final parts = t
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final left = parts.first.toLowerCase();
      if (RegExp(
        r'(aufrufe|views|reaktionen|reactions|likes|kommentare|comments|shares)',
      ).hasMatch(left)) {
        t = parts.sublist(1).join(' | ').trim();
      }
    }
    return t;
  }

  String _cleanTitle(String title) {
    var t = title.replaceAll(RegExp(r'[\n\r]+'), '\n').trim();
    // Erste Zeile: Facebook packt oft Caption-Fortsetzung in og:title.
    t = t.split('\n').first.trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();

    final parts = t
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      final left = parts.first.toLowerCase();
      final right = parts.last.toLowerCase();
      // „12.345 Aufrufe · … | High Protein Döner Wrap“ → Teil rechts
      if (RegExp(
        r'(aufrufe|views|reaktionen|reactions|likes|kommentare|comments|shares)',
      ).hasMatch(left)) {
        t = parts.sublist(1).join(' | ').trim();
      } else if (RegExp(
        r'^(facebook|instagram|tiktok|youtube|watch)$',
      ).hasMatch(right)) {
        t = parts.sublist(0, parts.length - 1).join(' | ').trim();
      }
    }
    return t.trim();
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

  @visibleForTesting
  String bestFacebookCaptionForTest(String html) => _bestFacebookCaption(html);

  @visibleForTesting
  String stripFacebookViewsPrefixForTest(String raw) =>
      _stripFacebookViewsPrefix(raw);

  String _decodeHtml(String value) {
    return value
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&auml;', 'ä')
        .replaceAll('&ouml;', 'ö')
        .replaceAll('&uuml;', 'ü')
        .replaceAll('&Auml;', 'Ä')
        .replaceAll('&Ouml;', 'Ö')
        .replaceAll('&Uuml;', 'Ü')
        .replaceAll('&szlig;', 'ß')
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(1)!, radix: 16);
          if (code == null) return m.group(0)!;
          return String.fromCharCodes([code]);
        })
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1)!);
          if (code == null) return m.group(0)!;
          return String.fromCharCodes([code]);
        });
  }
}
