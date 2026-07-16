import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'recipe_extractor.dart';

class FetchedCaption {
  const FetchedCaption({
    required this.title,
    required this.caption,
    required this.source,
    this.warning,
  });

  final String title;
  final String caption;
  final String source;
  final String? warning;

  bool get hasCaption => caption.trim().isNotEmpty;
}

/// Lädt die Beschreibung / Caption zu einem Video-Link.
///
/// - Im Browser (iPhone-Web): über `/api/fetch-caption` (Vercel), ohne CORS-Ärger.
/// - In der App (Android/iOS): direkt vom Gerät.
class CaptionFetcher {
  CaptionFetcher({
    http.Client? client,
    RecipeExtractor? extractor,
  })  : _client = client ?? http.Client(),
        _extractor = extractor ?? RecipeExtractor(client: client);

  final http.Client _client;
  final RecipeExtractor _extractor;

  Future<FetchedCaption> fetchFromUrl(String rawUrl) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw Exception('Das sieht nicht nach einem gültigen Link aus.');
    }

    if (kIsWeb) {
      return _fetchViaApi(url);
    }
    return _fetchDirect(url);
  }

  Future<FetchedCaption> _fetchViaApi(String url) async {
    final endpoint = Uri.parse('/api/fetch-caption').replace(
      queryParameters: {'url': url},
    );
    final response = await _client
        .get(endpoint)
        .timeout(const Duration(seconds: 25));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Caption konnte nicht geladen werden (${response.statusCode}).',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final caption = (body['caption'] as String?)?.trim() ?? '';
    final title = (body['title'] as String?)?.trim() ?? '';
    final source = (body['source'] as String?)?.trim() ?? 'none';
    final warning = (body['warning'] as String?)?.trim();

    if (caption.isEmpty) {
      return FetchedCaption(
        title: title,
        caption: '',
        source: source,
        warning: warning ??
            'Kein Beschreibungstext gefunden. '
                'Bei Instagram/TikTok den Text unter dem Video bitte manuell kopieren.',
      );
    }

    return FetchedCaption(
      title: title,
      caption: caption,
      source: source,
      warning: warning,
    );
  }

  Future<FetchedCaption> _fetchDirect(String url) async {
    final host = Uri.parse(url).host.replaceFirst('www.', '').toLowerCase();

    // TikTok oEmbed (Titel = Caption)
    if (host.contains('tiktok.com')) {
      final oembed = await _getJson(
        'https://www.tiktok.com/oembed?url=${Uri.encodeComponent(url)}',
      );
      final title = (oembed?['title'] as String?)?.trim() ?? '';
      if (title.isNotEmpty) {
        return FetchedCaption(
          title: title,
          caption: title,
          source: 'tiktok-oembed',
        );
      }
    }

    // HTML / Meta / YouTube shortDescription
    final preview = await _extractor.fetchPagePreview(url);
    var caption = preview.description.trim();

    if (host.contains('youtube.com') || host == 'youtu.be') {
      final ytDesc = await _youtubeShortDescription(url);
      if (ytDesc != null && ytDesc.trim().isNotEmpty) {
        caption = ytDesc.trim();
      }
    }

    // Facebook: Beschreibung oft abgeschnitten — längeren Titel-Text nutzen.
    if (host.contains('facebook.com') || host == 'fb.watch' || host == 'fb.com') {
      final fromTitle = preview.title.trim();
      final titleLooksLonger = fromTitle.length > caption.length + 20;
      final captionTruncated =
          caption.endsWith('...') || caption.endsWith('…');
      if (caption.isEmpty || (captionTruncated && titleLooksLonger)) {
        caption = fromTitle;
      }
    }

    if (caption.isEmpty) {
      return FetchedCaption(
        title: preview.title,
        caption: '',
        source: 'none',
        warning:
            'Kein Beschreibungstext gefunden. '
            'Bitte den Text unter dem Video manuell einfügen.',
      );
    }

    return FetchedCaption(
      title: preview.title,
      caption: caption,
      source: host.contains('youtube')
          ? 'youtube'
          : host.contains('facebook')
              ? 'facebook-og'
              : 'og',
    );
  }

  Future<String?> _youtubeShortDescription(String url) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 400) return null;
      final match =
          RegExp(r'"shortDescription":"(.*?)"').firstMatch(response.body);
      if (match == null) return null;
      try {
        return jsonDecode('"${match.group(1)}"') as String;
      } catch (_) {
        return match
            .group(1)!
            .replaceAll(r'\n', '\n')
            .replaceAll(r'\"', '"')
            .replaceAll(r'\\', r'\');
      }
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _getJson(String url) async {
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
