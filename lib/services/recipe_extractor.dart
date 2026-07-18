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
    bool skipPagePreview = false,
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

    if (url.isNotEmpty && !skipPagePreview) {
      preview = await fetchPagePreview(url);
      // Facebook liefert oft den Reel-Canonical in og:url — den bevorzugen.
      if (preview.url.isNotEmpty && preview.url != url) {
        url = preview.url;
      }
    } else if (url.isNotEmpty && skipPagePreview && caption.isNotEmpty) {
      // Caption/Video schon vom Link geladen — Facebook nicht erneut anfragen.
      preview = PagePreview(
        url: url,
        title: '',
        description: caption,
      );
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

    final hasSpokenSource = hasVideo ||
        (autoTranscript != null && autoTranscript.trim().isNotEmpty) ||
        (whisperTranscript != null && whisperTranscript.trim().isNotEmpty);
    final captionMostlyIngredients =
        captionLooksLikeIngredientsOnly(effectiveCaption);

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
      if (hasSpokenSource) ...[
        'GESPROCHENER TON / VIDEO ist die HAUPTQUELLE für die Schritte.',
        'Übernimm Reihenfolge, Tipps und Technik der sprechenden Person.',
        'Die Caption oft nur für Zutaten und Mengen nutzen.',
        'Nicht eine Standard-Zubereitung erfinden, die im Video so nicht vorkommt.',
      ] else ...[
        'Es gibt kein Video/Ton — nur Text (Caption).',
        'Erstelle daraus ein nachkochbares Rezept: Zutaten genau übernehmen.',
        'Für steps: sinnvolle, kurze Schritte für GENAU DIESES Gericht '
            '(passend zu Titel und Zutaten). Kein anderes Gericht erfinden.',
        'In notes schreiben: „Bitte mit Originalvideo abgleichen.“',
      ],
      if (hasSpokenSource)
        'Fehlen einzelne Mengen: nur für DIESES Gericht typisch ergänzen '
            'und in notes als Schätzung markieren.',
      'Steht in den Quellen wirklich gar kein Gericht: dann title '
          '„Rezept ergänzen“, kurze Platzhalter und in notes bitten, '
          'Caption oder Video nachzutragen.',
      'Widersprüche: gesprochener Text schlägt Caption.',
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
          caption: effectiveCaption,
          ingredientsOnly: captionMostlyIngredients && !hasSpokenSource,
        );

    if (!useAi || apiKey == null || apiKey.trim().isEmpty) {
      return local();
    }

    try {
      // Optional: wenn jemand ein Video mitgeteilt hat (selten), Gemini nutzen.
      if (hasVideo && provider == AiProvider.gemini) {
        final recipe = await _extractWithGeminiVideo(
          combinedText: combinedForAi,
          sourceUrl: url,
          apiKey: apiKey.trim(),
          videoBytes: videoBytes,
          videoMimeType: videoMimeType ?? 'video/mp4',
          titleFallback: dishTitle,
        );
        return _finalizeAiRecipe(
          recipe,
          titleFallback: dishTitle,
          captionMostlyIngredients: captionMostlyIngredients,
          hasSpokenSource: hasSpokenSource,
        );
      }

      final recipe = await _extractWithAi(
        provider: provider,
        combinedText: combinedForAi,
        sourceUrl: url,
        apiKey: apiKey.trim(),
        titleFallback: dishTitle,
      );
      return _finalizeAiRecipe(
        recipe,
        titleFallback: dishTitle,
        captionMostlyIngredients: captionMostlyIngredients,
        hasSpokenSource: hasSpokenSource,
      );
    } catch (e) {
      // Bei Limit/Guthaben: kein erfundenes Platzhalter-Rezept speichern.
      if (_isHardAiFailure(e)) {
        rethrow;
      }
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

  /// Limit, Guthaben, ungültiger Schlüssel → Nutzer soll warten/aufladen, nicht speichern.
  bool _isHardAiFailure(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('429') ||
        lower.contains('limit erreicht') ||
        lower.contains('kontingent') ||
        lower.contains('guthaben') ||
        lower.contains('insufficient_quota') ||
        lower.contains('resource_exhausted') ||
        lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('without berechtigung');
  }

  /// Nach KI-Antwort: nutzlosen Titel korrigieren.
  /// Caption-first: KI darf aus Zutaten + Gerichtsnamen Schritte vorschlagen.
  Recipe _finalizeAiRecipe(
    Recipe recipe, {
    required String titleFallback,
    required bool captionMostlyIngredients,
    required bool hasSpokenSource,
  }) {
    var title = recipe.title;
    if (_isUselessDishTitle(title) &&
        titleFallback.isNotEmpty &&
        !_isUselessDishTitle(titleFallback)) {
      title = titleFallback;
    }

    if (!hasSpokenSource && captionMostlyIngredients) {
      final notes = [
        if (recipe.notes != null && recipe.notes!.isNotEmpty) recipe.notes!,
        'Schritte aus Caption/Zutaten vorgeschlagen — bitte mit dem Video '
            'kurz abgleichen und bei Bedarf unter „Alles bearbeiten“ anpassen.',
      ].join(' ');
      return recipe.copyWith(title: title, notes: notes);
    }

    return title != recipe.title ? recipe.copyWith(title: title) : recipe;
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
      'Hauptquelle ist der Caption-Text (Zutaten + ggf. Anleitung). '
      'Wenn nur Zutaten + Gerichtsname da sind: passende kurze Schritte '
      'für GENAU DIESES Gericht vorschlagen und in notes bitten, '
      'mit dem Originalvideo abzugleichen. '
      'Schreibe klare, kurze Kochschritte.';

  Future<Recipe> _extractWithAi({
    required AiProvider provider,
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
    required String titleFallback,
  }) async {
    final userPrompt =
        'Erstelle daraus ein nachkochbares Rezept:\n$combinedText';

    switch (provider) {
      case AiProvider.openai:
        return _extractWithOpenAi(
          combinedText: userPrompt,
          sourceUrl: sourceUrl,
          apiKey: apiKey,
          titleFallback: titleFallback,
        );
      case AiProvider.gemini:
        return _extractWithGemini(
          combinedText: userPrompt,
          sourceUrl: sourceUrl,
          apiKey: apiKey,
          titleFallback: titleFallback,
        );
      case AiProvider.claude:
        return _extractWithClaude(
          combinedText: userPrompt,
          sourceUrl: sourceUrl,
          apiKey: apiKey,
          titleFallback: titleFallback,
        );
    }
  }

  Future<Recipe> _extractWithGeminiVideo({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
    required Uint8List videoBytes,
    required String videoMimeType,
    required String titleFallback,
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
                    'Im Anhang ist das Rezeptvideo (Bild + Ton).\n'
                    'PRIORITÄT: Die gesprochenen Zubereitungsschritte der '
                    'Person im Video sind maßgeblich — Reihenfolge und '
                    'Technik genau übernehmen.\n'
                    'Caption/Text vor allem für Zutaten und Mengen nutzen.\n'
                    'Erfinde keine anderen Schritte als im Video erklärt.\n'
                    'Zusätzlicher Text:\n'
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
    return _recipeFromAiJson(
      _geminiAnswerText(body),
      sourceUrl,
      titleFallback: titleFallback,
    );
  }

  Future<Recipe> _extractWithOpenAi({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
    required String titleFallback,
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
    return _recipeFromAiJson(content, sourceUrl, titleFallback: titleFallback);
  }

  Future<Recipe> _extractWithGemini({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
    required String titleFallback,
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
    return _recipeFromAiJson(
      _geminiAnswerText(body),
      sourceUrl,
      titleFallback: titleFallback,
    );
  }

  Future<Recipe> _extractWithClaude({
    required String combinedText,
    required String sourceUrl,
    required String apiKey,
    required String titleFallback,
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
    return _recipeFromAiJson(text, sourceUrl, titleFallback: titleFallback);
  }
  static const _geminiModels = <String>[
    'gemini-2.0-flash',
    'gemini-2.5-flash',
    'gemini-3.5-flash',
  ];

  /// Pro Rezept-Erstellung höchstens so viele Gemini-HTTP-Anfragen.
  static const _maxGeminiRequestsPerRecipe = 3;

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

  /// Gemini: wenige Versuche — kein 9×-Retry mit erneutem Video-Upload.
  Future<Map<String, dynamic>> _postGeminiGenerateContent({
    required String apiKey,
    required Map<String, dynamic> payload,
    required Duration timeout,
  }) async {
    Exception? lastError;
    var requestsMade = 0;

    for (final model in _geminiModels) {
      var serverRetriesLeft = 1;

      while (requestsMade < _maxGeminiRequestsPerRecipe) {
        requestsMade++;
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
        } catch (_) {
          lastError = Exception(
            'Gemini-Netzwerkfehler. Bitte Verbindung prüfen und erneut versuchen.',
          );
          if (requestsMade < _maxGeminiRequestsPerRecipe) {
            await Future<void>.delayed(const Duration(seconds: 1));
            continue;
          }
          throw lastError;
        }

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return jsonDecode(_utf8Body(response)) as Map<String, dynamic>;
        }

        final body = _utf8Body(response);
        lastError = Exception(
          _aiErrorMessage(AiProvider.gemini, response.statusCode, body),
        );

        // 429 oder leeres Kontingent: sofort stoppen (Free-Tier verträgt kein Karussell).
        if (response.statusCode == 429 || _isQuotaOrBillingExhausted(body)) {
          throw lastError;
        }

        if (response.statusCode == 404) {
          break;
        }

        final retriableServer = response.statusCode == 500 ||
            response.statusCode == 502 ||
            response.statusCode == 503;

        if (retriableServer &&
            serverRetriesLeft > 0 &&
            requestsMade < _maxGeminiRequestsPerRecipe) {
          serverRetriesLeft--;
          final wait = _retryAfterSeconds(response.headers) ?? 2;
          await Future<void>.delayed(Duration(seconds: wait));
          continue;
        }

        if (retriableServer) {
          break;
        }

        throw lastError;
      }
    }

    throw lastError ??
        Exception(
          'Gemini ist gerade nicht erreichbar. Bitte später erneut versuchen.',
        );
  }

  bool _isQuotaOrBillingExhausted(String body) {
    final lower = body.toLowerCase();
    return lower.contains('resource_exhausted') ||
        lower.contains('insufficient_quota') ||
        lower.contains('exceeded your current quota') ||
        lower.contains('quota exceeded') ||
        lower.contains('billing');
  }

  int? _retryAfterSeconds(Map<String, String> headers) {
    final raw = headers['retry-after']?.trim();
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
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

  /// Wandelt KI-JSON in ein Rezept um (auch für Fallback-Anbieter).
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

  Recipe _recipeFromAiJson(
    String raw,
    String sourceUrl, {
    String titleFallback = '',
  }) {
    final parsed = _decodeAiJsonObject(raw);

    var title = (parsed['title'] as String?)?.trim() ?? '';
    title = _fixGermanSpelling(_cleanTitle(_stripPlatformSuffix(title)));
    if (title.isEmpty || _isUselessDishTitle(title)) {
      if (titleFallback.isNotEmpty && !_isUselessDishTitle(titleFallback)) {
        title = titleFallback;
      } else {
        title = 'Neues Rezept';
      }
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
    String caption = '',
    bool ingredientsOnly = false,
  }) {
    final captionText =
        caption.isNotEmpty ? caption : _extractCaptionBlock(combinedText);

    var ingredients = _parseIngredientsFromText(captionText);
    var steps = _parseStepsFromText(captionText);

    if (ingredients.isEmpty) {
      for (final line in combinedText.split(RegExp(r'[\n\r]+'))) {
        final cleaned = _stripBullet(line.trim());
        if (cleaned.isEmpty) continue;
        if (_looksLikeIngredient(cleaned)) {
          ingredients.add(cleaned);
        }
      }
    }

    final title = _resolveLocalTitle(titleHint, captionText);

    if (ingredients.isEmpty && steps.isEmpty) {
      return _buildHonestPlaceholderRecipe(
        title: title,
        sourceUrl: sourceUrl,
      );
    }

    if (ingredientsOnly && steps.isEmpty) {
      steps = const [
        'Die Zubereitung wird im Video gesprochen — ohne Video/KI nicht übernehmbar.',
        'Bitte Video anhängen oder „Video vom Link laden“, dann erneut erstellen.',
      ];
    }

    return Recipe(
      id: _uuid.v4(),
      title: title,
      ingredients: ingredients.isEmpty
          ? [
              'Zutaten waren im Text nicht klar erkennbar — bitte aus dem Video ergänzen.',
            ]
          : ingredients,
      steps: steps.isEmpty
          ? [
              'Originalvideo beim Kochen offen lassen und Schritte manuell eintragen.',
            ]
          : steps,
      sourceUrl: sourceUrl,
      createdAt: DateTime.now(),
      notes: ingredientsOnly
          ? 'Zutaten aus der Caption übernommen. Für echte Schritte Video + KI (Gemini) nutzen.'
          : 'Erstellt ohne KI-Schlüssel (lokale Auswertung). Für bessere Ergebnisse '
              'unter Einstellungen einen KI-Schlüssel hinterlegen (OpenAI, Gemini oder Claude).',
    );
  }

  String _extractCaptionBlock(String combinedText) {
    const marker = 'Text unter dem Video (Caption / Beschreibung):';
    final idx = combinedText.indexOf(marker);
    if (idx < 0) return combinedText;
    var rest = combinedText.substring(idx + marker.length).trim();
    for (final stop in [
      'Eingefügter Text / geteilter Inhalt:',
      'Gesprochener Text / Untertitel',
      'Aus dem Video-Ton transkribierter Text:',
      'Quelle (Link):',
    ]) {
      final stopIdx = rest.indexOf(stop);
      if (stopIdx > 0) {
        rest = rest.substring(0, stopIdx).trim();
      }
    }
    return rest;
  }

  List<String> _parseIngredientsFromText(String text) {
    final ingredients = <String>[];
    var mode = 'none';

    for (final raw in text.split(RegExp(r'[\n\r]+'))) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('http') || line.startsWith('#')) {
        continue;
      }
      final lower = line.toLowerCase();
      if (lower.contains('zutat')) {
        mode = 'ingredients';
        continue;
      }
      if (lower.contains('zubereitung') ||
          lower.contains('anleitung') ||
          lower.startsWith('schritt')) {
        break;
      }
      if (_isMarketingLine(line)) continue;

      final cleaned = _stripBullet(line);
      if (mode == 'ingredients' ||
          _looksLikeIngredient(cleaned) ||
          _looksLikeIngredientLine(cleaned)) {
        if (!_looksLikeStep(cleaned)) {
          ingredients.add(cleaned);
        }
      }
    }
    return ingredients;
  }

  List<String> _parseStepsFromText(String text) {
    final steps = <String>[];
    var mode = 'none';

    for (final raw in text.split(RegExp(r'[\n\r]+'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final lower = line.toLowerCase();
      if (lower.contains('zubereitung') ||
          lower.contains('anleitung') ||
          lower.startsWith('schritt')) {
        mode = 'steps';
        continue;
      }
      if (mode == 'steps' || _looksLikeStep(line)) {
        steps.add(_stripBullet(line));
      }
    }
    return steps;
  }

  bool _looksLikeIngredientLine(String line) {
    if (line.length < 3 || line.length > 120) return false;
    return RegExp(
      r'\b(\d+[.,]?\d*\s*(g|kg|mg|ml|l|cl|el|tl|prise|stück|stk|zehe|zehen|bund|dose|packung|pck|tasse|becher|handvoll|scheibe|scheiben))\b',
      caseSensitive: false,
    ).hasMatch(line);
  }

  String _resolveLocalTitle(String titleHint, String captionText) {
    if (titleHint.trim().isNotEmpty &&
        !_isUselessDishTitle(_cleanTitle(_stripPlatformSuffix(titleHint)))) {
      return _cleanTitle(_stripPlatformSuffix(titleHint));
    }
    for (final line in captionText.split(RegExp(r'[\n\r]+'))) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('http') ||
          _looksLikeIngredient(trimmed) ||
          _looksLikeIngredientLine(trimmed) ||
          _isMarketingLine(trimmed)) {
        continue;
      }
      if (trimmed.length >= 3 && trimmed.length <= 80 && !_looksLikeStep(trimmed)) {
        return _cleanTitle(trimmed);
      }
    }
    return 'Neues Rezept';
  }

  bool _isMarketingLine(String line) {
    final t = line.toLowerCase();
    return RegExp(
      r'(begeistern|nie gesehen|schaut euch|folgt mir|link in bio|'
      r'rezept des tages|so einfach|genial|unglaublich|sensation|'
      r'musst du probieren|unbedingt nachmachen|werbung|sponsored|'
      r'dieses rezept wird)',
      caseSensitive: false,
    ).hasMatch(t);
  }

  Recipe _buildHonestPlaceholderRecipe({
    required String title,
    required String sourceUrl,
  }) {
    return Recipe(
      id: _uuid.v4(),
      title: title,
      ingredients: const [
        'Zutaten bitte aus dem Video oder der Caption einfügen.',
      ],
      steps: const [
        'Caption oder Video-Link laden, dann erneut „Anleitung erstellen“.',
        'Für gesprochene Schritte: Video anhängen und Gemini nutzen.',
      ],
      sourceUrl: sourceUrl,
      createdAt: DateTime.now(),
      notes:
          'Es wurde zu wenig Text gefunden. Bitte Caption unter dem Video '
          'einfügen oder Video vom Link laden.',
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
        if (provider == AiProvider.gemini) {
          return 'Gemini-Limit erreicht (429). Beim kostenlosen Tarif sind '
              'nur wenige Anfragen pro Minute und pro Tag möglich '
              '(oft ca. 5/Minute, 20/Tag). '
              'Bitte 1–2 Minuten warten oder in Google AI Studio '
              'Abrechnung aktivieren (Pay-as-you-go) für höhere Limits.';
        }
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
    if (RegExp(
      r'(begeistern|nie gesehen|schaut euch|folgt mir|link in bio|'
      r'rezept des tages|so einfach|genial|unglaublich|sensation|'
      r'musst du probieren|unbedingt nachmachen|dieses rezept wird)',
      caseSensitive: false,
    ).hasMatch(t)) {
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
        if (_isMarketingLine(trimmed)) continue;
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

  /// Caption hat Zutaten/Mengen, aber kaum eine gesprochene Anleitung.
  @visibleForTesting
  bool isUselessDishTitleForTest(String title) => _isUselessDishTitle(title);

  bool captionLooksLikeIngredientsOnly(String caption) {
    final lines = caption
        .split(RegExp(r'[\n\r]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.startsWith('http'))
        .toList();
    if (lines.isEmpty) return true;

    var ingredientLines = 0;
    var stepLines = 0;
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.contains('zubereitung') ||
          lower.contains('anleitung') ||
          lower.startsWith('schritt')) {
        stepLines += 2;
        continue;
      }
      if (_looksLikeIngredient(line) ||
          RegExp(
            r'\b(\d+[.,]?\d*\s*(g|kg|ml|l|el|tl)|prise|bund|zehe|stück)\b',
            caseSensitive: false,
          ).hasMatch(line)) {
        ingredientLines++;
        continue;
      }
      if (_looksLikeStep(line)) {
        stepLines++;
      }
    }

    // Typisch Facebook: viele Mengenzeilen, kaum echte Schritte.
    if (ingredientLines >= 2 && stepLines == 0) return true;
    if (ingredientLines >= 3 && stepLines <= 1) return true;
    if (lines.length <= 6 && ingredientLines >= 1 && stepLines == 0) {
      // Kurze Caption ohne Kochverben → oft nur Marketing + Zutaten.
      final joined = caption.toLowerCase();
      final hasCookVerb = RegExp(
        r'\b(braten|kochen|schneiden|rühren|backen|würzen|anbraten|'
        r'köcheln|verühren|schalen|hacken|dünsten)\b',
      ).hasMatch(joined);
      if (!hasCookVerb) return true;
    }
    return false;
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
