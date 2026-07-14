import 'dart:convert';

import 'package:http/http.dart' as http;

/// Holt Untertitel / Transkript aus Videos, soweit möglich.
class MediaTranscriptService {
  MediaTranscriptService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Versucht, bei YouTube-Links die Untertitel (deutsch/englisch) zu laden.
  Future<String?> fetchYoutubeTranscript(String url) async {
    final videoId = _youtubeId(url);
    if (videoId == null) return null;

    try {
      final watch = await _client
          .get(
            Uri.parse('https://www.youtube.com/watch?v=$videoId'),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (watch.statusCode < 200 || watch.statusCode >= 400) return null;

      final captionUrl = _findCaptionTrackUrl(watch.body);
      if (captionUrl != null) {
        final transcript = await _downloadTimedText(captionUrl);
        if (transcript != null && transcript.trim().isNotEmpty) {
          return transcript.trim();
        }
      }

      // Fallback: öffentliche timedtext-Endpunkte
      for (final lang in ['de', 'en', 'a.de', 'a.en']) {
        final timed = await _downloadTimedText(
          'https://www.youtube.com/api/timedtext?v=$videoId&lang=$lang',
        );
        if (timed != null && timed.trim().isNotEmpty) return timed.trim();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Sprache → Text mit OpenAI Whisper (Audio oder kurzes Video).
  Future<String> transcribeWithWhisper({
    required List<int> bytes,
    required String filename,
    required String apiKey,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
    );
    request.headers['Authorization'] = 'Bearer $apiKey';
    request.fields['model'] = 'whisper-1';
    request.fields['language'] = 'de';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );

    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw Exception(
        'Video-Ton konnte nicht ausgelesen werden '
        '(${streamed.statusCode}). '
        'Bitte Caption-Text einfügen oder Gemini für Video nutzen.',
      );
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final text = (decoded['text'] as String?)?.trim() ?? '';
    if (text.isEmpty) {
      throw Exception('Whisper lieferte keinen Text aus dem Video-Ton.');
    }
    return text;
  }

  String? _youtubeId(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    final host = uri.host.replaceFirst('www.', '');
    if (host == 'youtu.be') {
      final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
      return id != null && id.length >= 6 ? id : null;
    }
    if (host.contains('youtube.com')) {
      final v = uri.queryParameters['v'];
      if (v != null && v.isNotEmpty) return v;
      final parts = uri.pathSegments;
      if (parts.length >= 2 &&
          (parts[0] == 'shorts' || parts[0] == 'embed' || parts[0] == 'live')) {
        return parts[1];
      }
    }
    return null;
  }

  String? _findCaptionTrackUrl(String html) {
    // captionTracks in ytInitialPlayerResponse
    final match = RegExp(
      r'"captionTracks":\s*(\[.*?\])',
      dotAll: true,
    ).firstMatch(html);
    if (match == null) return null;
    try {
      final raw = match.group(1)!;
      final list = jsonDecode(raw) as List<dynamic>;
      if (list.isEmpty) return null;

      Map<String, dynamic>? preferred;
      for (final item in list) {
        if (item is! Map<String, dynamic>) continue;
        final lang = '${item['languageCode'] ?? ''}'.toLowerCase();
        if (lang.startsWith('de')) {
          preferred = item;
          break;
        }
        preferred ??= item;
      }
      final baseUrl = preferred?['baseUrl'] as String?;
      return baseUrl;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _downloadTimedText(String url) async {
    try {
      final response = await _client
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 400) return null;
      final body = response.body;
      if (body.trim().isEmpty) return null;

      // XML timedtext
      final texts = RegExp(
        r'<text[^>]*>(.*?)</text>',
        dotAll: true,
      ).allMatches(body).map((m) {
        return _decodeXml(m.group(1) ?? '');
      }).where((t) => t.isNotEmpty).toList();
      if (texts.isNotEmpty) return texts.join(' ');

      // JSON3 format
      if (body.trim().startsWith('{')) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        final events = json['events'] as List<dynamic>? ?? const [];
        final parts = <String>[];
        for (final event in events) {
          if (event is! Map<String, dynamic>) continue;
          final segs = event['segs'] as List<dynamic>? ?? const [];
          for (final seg in segs) {
            if (seg is Map && seg['utf8'] != null) {
              parts.add('${seg['utf8']}');
            }
          }
        }
        if (parts.isNotEmpty) return parts.join();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _decodeXml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('\n', ' ')
        .trim();
  }
}
