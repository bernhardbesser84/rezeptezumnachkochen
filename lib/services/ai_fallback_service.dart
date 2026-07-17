import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/fallback_api_keys.dart';
import '../models/recipe.dart';
import 'recipe_extractor.dart';

/// Gemini-429-Fallback: Groq (Whisper) → Mistral → OpenRouter (:free).
class AiFallbackService {
  AiFallbackService({
    http.Client? client,
    RecipeExtractor? extractor,
  })  : _client = client ?? http.Client(),
        _extractor = extractor ?? RecipeExtractor(client: client);

  final http.Client _client;
  final RecipeExtractor _extractor;

  static const _groqBase = 'https://api.groq.com/openai/v1';
  static const _mistralBase = 'https://api.mistral.ai/v1';
  static const _openRouterBase = 'https://openrouter.ai/api/v1';

  /// Transkribiert Video/Audio mit Groq Whisper (kostenloses Kontingent).
  Future<String> transcribeWithGroq({
    required List<int> bytes,
    required String filename,
    required String apiKey,
  }) async {
    debugPrint('[Fallback] Schritt A: Groq Whisper (whisper-large-v3)…');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_groqBase/audio/transcriptions'),
    );
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = 'whisper-large-v3';
    request.fields['language'] = 'de';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      debugPrint(
        '[Fallback] Groq Whisper fehlgeschlagen (${streamed.statusCode})',
      );
      throw Exception(
        'Groq-Transkription fehlgeschlagen (${streamed.statusCode}).',
      );
    }

    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final text = (decoded['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      throw Exception('Groq Whisper lieferte keinen Text.');
    }
    debugPrint(
      '[Fallback] Groq Whisper OK (${text.length} Zeichen Transkript).',
    );
    return text;
  }

  /// Caption + Transkript → Rezept über Mistral, sonst OpenRouter :free.
  Future<Recipe> extractRecipeFromText({
    required String combinedText,
    required String sourceUrl,
    required FallbackApiKeys keys,
  }) async {
    Exception? lastError;

    if (keys.hasMistral) {
      try {
        debugPrint('[Fallback] Schritt B: Mistral (Text-LLM)…');
        final content = await _chatCompletionsRaw(
          baseUrl: _mistralBase,
          apiKey: keys.mistral!.trim(),
          model: 'mistral-small-latest',
          combinedText: combinedText,
          providerLabel: 'Mistral',
        );
        debugPrint('[Fallback] Mistral OK.');
        return _extractor.parseAiRecipeJson(content, sourceUrl);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[Fallback] Mistral fehlgeschlagen: $e');
      }
    } else {
      debugPrint('[Fallback] Kein MISTRAL_API_KEY — überspringe Mistral.');
    }

    if (keys.hasOpenRouter) {
      try {
        debugPrint(
          '[Fallback] Schritt B: OpenRouter (kostenloses Modell :free)…',
        );
        final content = await _chatCompletionsRaw(
          baseUrl: _openRouterBase,
          apiKey: keys.openRouter!.trim(),
          model: 'google/gemma-2-9b-it:free',
          combinedText: combinedText,
          providerLabel: 'OpenRouter',
          extraHeaders: {
            'HTTP-Referer': 'https://rezeptezumnachkochen.vercel.app',
            'X-Title': 'Rezept Nachkochen',
          },
        );
        debugPrint('[Fallback] OpenRouter OK.');
        return _extractor.parseAiRecipeJson(content, sourceUrl);
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        debugPrint('[Fallback] OpenRouter fehlgeschlagen: $e');
      }
    } else {
      debugPrint(
        '[Fallback] Kein OPENROUTER_API_KEY — überspringe OpenRouter.',
      );
    }

    throw lastError ??
        Exception(
          'Kein Mistral- oder OpenRouter-Schlüssel für den Text-Fallback.',
        );
  }

  /// Gesamte Kette nach Gemini-429.
  Future<Recipe> runAfterGeminiLimit({
    required FallbackApiKeys keys,
    required String caption,
    required String sourceUrl,
    required String titleFallback,
    required String dishContext,
    Uint8List? videoBytes,
    String? videoFileName,
  }) async {
    debugPrint('[Fallback] Gemini-Limit (429) — Fallback-Kette starten.');

    if (!keys.hasAny) {
      throw Exception(
        'Gemini-Limit erreicht (429). Beim kostenlosen Tarif sind '
        'nur wenige Anfragen pro Minute und pro Tag möglich '
        '(oft ca. 5/Minute, 20/Tag). '
        'Bitte 1–2 Minuten warten oder unter Einstellungen '
        'Groq/Mistral/OpenRouter als Fallback hinterlegen.',
      );
    }

    String? transcript;
    if (videoBytes != null && videoBytes.isNotEmpty && keys.hasGroq) {
      try {
        transcript = await transcribeWithGroq(
          bytes: videoBytes,
          filename: videoFileName ?? 'recipe-video.mp4',
          apiKey: keys.groq!.trim(),
        );
      } catch (e) {
        debugPrint('[Fallback] Schritt A übersprungen: $e');
      }
    } else if (videoBytes != null && videoBytes.isNotEmpty && !keys.hasGroq) {
      debugPrint(
        '[Fallback] Kein GROQ_API_KEY — Transkription übersprungen.',
      );
    }

    final hasCaption = caption.trim().isNotEmpty;
    final hasTranscript = transcript != null && transcript.trim().isNotEmpty;
    if (!hasCaption && !hasTranscript) {
      throw Exception(
        'Gemini-Limit erreicht (429). Fallback ohne Caption/Transkript '
        'nicht möglich. Bitte 1–2 Minuten warten und erneut versuchen.',
      );
    }

    final combined = [
      'Aufgabe: Erstelle ein vollständiges, nachkochbares Rezept als JSON.',
      'Nutze Caption und Transkript. Erfinde kein anderes Gericht.',
      'Schreibe korrektes Deutsch mit ä, ö, ü und ß.',
      if (titleFallback.isNotEmpty && titleFallback != 'Neues Rezept')
        'Gerichtsname-Hinweis: „$titleFallback“.',
      '',
      if (hasCaption) 'Caption / Text unter dem Video:\n${caption.trim()}',
      if (hasTranscript)
        'Gesprochener Text (Transkription aus dem Video):\n${transcript.trim()}',
      if (dishContext.trim().isNotEmpty) '\nKontext:\n$dishContext',
    ].join('\n');

    try {
      final recipe = await extractRecipeFromText(
        combinedText: combined,
        sourceUrl: sourceUrl,
        keys: keys,
      );
      return recipe.copyWith(
        notes: [
          if (recipe.notes != null && recipe.notes!.isNotEmpty) recipe.notes!,
          'Erstellt über Fallback nach Gemini-Limit'
              '${hasTranscript ? ' (Groq-Transkription + Text-LLM)' : ' (Text-LLM)'}.',
        ].join(' '),
      );
    } catch (_) {
      debugPrint(
        '[Fallback] Schritt C: Alle Fallback-Anbieter fehlgeschlagen.',
      );
      throw Exception(
        'Gemini-Limit erreicht (429). Beim kostenlosen Tarif sind '
        'nur wenige Anfragen pro Minute und pro Tag möglich '
        '(oft ca. 5/Minute, 20/Tag). '
        'Bitte 1–2 Minuten warten oder in Google AI Studio '
        'Abrechnung aktivieren (Pay-as-you-go) für höhere Limits. '
        'Fallback (Groq/Mistral/OpenRouter) ist ebenfalls fehlgeschlagen.',
      );
    }
  }

  Future<String> _chatCompletionsRaw({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String combinedText,
    required String providerLabel,
    Map<String, String>? extraHeaders,
  }) async {
    final headers = <String, String>{
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
      ...?extraHeaders,
    };

    final response = await _client
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: headers,
          body: jsonEncode({
            'model': model,
            'temperature': 0.2,
            'response_format': {'type': 'json_object'},
            'messages': [
              {
                'role': 'system',
                'content':
                    'Du bist ein Rezept-Assistent. Antworte NUR mit einem '
                    'JSON-Objekt: title (string), servings (string|null), '
                    'prepTimeMinutes (number|null), ingredients (string[]), '
                    'steps (string[]), notes (string|null). '
                    'Korrektes Deutsch mit Umlauten. Keine Plattformnamen als Titel.',
              },
              {
                'role': 'user',
                'content':
                    'Erstelle daraus ein nachkochbares Rezept:\n$combinedText',
              },
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('[Fallback] $providerLabel HTTP ${response.statusCode}');
      throw Exception(
        '$providerLabel fehlgeschlagen (${response.statusCode}).',
      );
    }

    final body =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content =
        (body['choices'] as List).first['message']['content'] as String?;
    final text = content?.trim() ?? '';
    if (text.isEmpty) {
      throw Exception('$providerLabel lieferte eine leere Antwort.');
    }
    return text;
  }
}
