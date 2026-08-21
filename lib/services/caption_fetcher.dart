import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'recipe_extractor.dart';
import 'facebook_share_resolve.dart';
import 'youtube_caption.dart';

class FetchedCaption {
  const FetchedCaption({
    required this.title,
    required this.caption,
    required this.source,
    this.warning,
    this.imageUrl,
  });

  final String title;
  final String caption;
  final String source;
  final String? warning;
  final String? imageUrl;

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

    // Server kann Platzhalter liefern — lokal nochmals prüfen.
    if (isYoutubeUrl(url) &&
        isYoutubeGarbageCaption(title: title, caption: caption)) {
      return FetchedCaption(
        title: title == 'YouTube' || title == 'youtube' ? '' : title,
        caption: '',
        source: 'none',
        warning: warning?.isNotEmpty == true ? warning : kYoutubeManualHint,
      );
    }

    if (caption.isEmpty) {
      return FetchedCaption(
        title: title,
        caption: '',
        source: source,
        warning: warning ??
            (isYoutubeUrl(url)
                ? kYoutubeManualHint
                : 'Kein Beschreibungstext gefunden. '
                    'Bei Instagram/TikTok den Text unter dem Video bitte manuell kopieren.'),
      );
    }

    return FetchedCaption(
      title: title,
      caption: caption,
      source: source,
      warning: warning,
      imageUrl: (body['imageUrl'] as String?)?.trim(),
    );
  }

  Future<FetchedCaption> _fetchDirect(String url) async {
    final host = Uri.parse(url).host.replaceFirst('www.', '').toLowerCase();

    if (isYoutubeUrl(url)) {
      return _fetchYoutubeDirect(url);
    }

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

    // HTML / Meta — Facebook-Share ggf. erst zur Reel-URL auflösen.
    final urlsToTry = <String>[url];
    if (host.contains('facebook.com') ||
        host == 'fb.watch' ||
        host == 'fb.com') {
      try {
        final expanded = await FacebookShareResolve(client: _client)
            .expandCandidateUrls(url);
        for (final candidate in expanded) {
          if (!urlsToTry.contains(candidate)) urlsToTry.add(candidate);
        }
      } catch (_) {
        // Mit Original-URL weiterprobieren.
      }
    }

    PagePreview? bestPreview;
    var caption = '';
    for (final candidate in urlsToTry) {
      final preview = await _extractor.fetchPagePreview(candidate);
      var text = preview.description.trim();
      final fromTitle = preview.title.trim();
      if (host.contains('facebook.com') ||
          host == 'fb.watch' ||
          host == 'fb.com' ||
          candidate.contains('facebook.com')) {
        final titleLooksLonger = fromTitle.length > text.length + 20;
        final captionTruncated =
            text.endsWith('...') || text.endsWith('…');
        if (text.isEmpty || (captionTruncated && titleLooksLonger)) {
          text = fromTitle;
        }
        if (RegExp(
          r'log into facebook|bei facebook anmelden',
          caseSensitive: false,
        ).hasMatch(fromTitle)) {
          continue;
        }
      }
      if (text.length >= caption.length) {
        caption = text;
        bestPreview = preview;
      }
      if (caption.length >= 40) break;
    }

    final preview = bestPreview ?? await _extractor.fetchPagePreview(url);

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
      source: host.contains('facebook') ? 'facebook-og' : 'og',
      imageUrl: preview.imageUrl,
    );
  }

  Future<FetchedCaption> _fetchYoutubeDirect(String url) async {
    final videoId = youtubeVideoId(url);
    if (videoId == null) {
      return const FetchedCaption(
        title: '',
        caption: '',
        source: 'none',
        warning: 'Das sieht nicht nach einem YouTube-Link aus.',
      );
    }

    final watchUrl = 'https://www.youtube.com/watch?v=$videoId';
    const userAgents = [
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    ];

    for (final userAgent in userAgents) {
      try {
        final response = await _client
            .get(
              Uri.parse(watchUrl),
              headers: {
                'User-Agent': userAgent,
                'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
                'Accept': 'text/html,application/xhtml+xml',
              },
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode < 200 || response.statusCode >= 400) {
          continue;
        }
        final details = youtubeDetailsFromPlayerHtml(response.body);
        if (details != null &&
            !isYoutubeGarbageCaption(
              title: details.title,
              caption: details.caption,
            )) {
          return FetchedCaption(
            title: details.title,
            caption: details.caption,
            source: 'youtube-player',
          );
        }
      } catch (_) {
        // Nächsten User-Agent versuchen.
      }
    }

    // oEmbed: zumindest Titel — Beschreibung muss ggf. manuell rein.
    final oembed = await _getJson(
      'https://www.youtube.com/oembed'
      '?url=${Uri.encodeComponent(watchUrl)}&format=json',
    );
    final title = (oembed?['title'] as String?)?.trim() ?? '';

    return FetchedCaption(
      title: title,
      caption: '',
      source: 'none',
      warning: kYoutubeManualHint,
    );
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
