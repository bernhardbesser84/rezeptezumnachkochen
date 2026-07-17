import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'caption_fetcher.dart';

/// Caption + optional Video in möglichst wenigen Netzwerk-Anfragen.
class FetchedLinkContent {
  const FetchedLinkContent({
    required this.title,
    required this.caption,
    required this.source,
    this.warning,
    this.canonicalUrl,
    this.videoBytes,
    this.videoMimeType,
    this.videoFileName,
    this.videoError,
  });

  final String title;
  final String caption;
  final String source;
  final String? warning;
  final String? canonicalUrl;
  final Uint8List? videoBytes;
  final String? videoMimeType;
  final String? videoFileName;
  final String? videoError;

  bool get hasCaption => caption.trim().isNotEmpty;
  bool get hasVideo => videoBytes != null && videoBytes!.isNotEmpty;
}

class LinkContentFetcher {
  LinkContentFetcher({
    http.Client? client,
    this._captionFetcher,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final CaptionFetcher? _captionFetcher;

  static const _maxVideoBytes = 2700000;
  static const _iphoneUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
      'Mobile/15E148 Safari/604.1';

  Future<FetchedLinkContent> fetchFromUrl(String rawUrl) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw Exception('Das sieht nicht nach einem gültigen Link aus.');
    }

    if (_looksLikeFacebook(url)) {
      if (kIsWeb) {
        return _fetchFacebookViaApi(url);
      }
      return _fetchFacebookDirect(url);
    }

    final captionFetcher = _captionFetcher ?? CaptionFetcher(client: _client);
    final caption = await captionFetcher.fetchFromUrl(url);
    return FetchedLinkContent(
      title: caption.title,
      caption: caption.caption,
      source: caption.source,
      warning: caption.warning,
      canonicalUrl: url,
    );
  }

  bool _looksLikeFacebook(String url) {
    final host = Uri.parse(url).host.replaceFirst('www.', '').toLowerCase();
    return host.contains('facebook.com') ||
        host == 'fb.watch' ||
        host == 'fb.com';
  }

  Future<FetchedLinkContent> _fetchFacebookViaApi(String url) async {
    final endpoint = Uri.parse('/api/fetch-all').replace(
      queryParameters: {'url': url},
    );
    final response = await _client
        .get(endpoint)
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Link-Inhalte konnten nicht geladen werden (${response.statusCode}).',
      );
    }

    final body = jsonDecode(utf8.decode(response.bodyBytes))
        as Map<String, dynamic>;

    Uint8List? videoBytes;
    final b64 = (body['videoBase64'] as String?)?.trim();
    if (b64 != null && b64.isNotEmpty) {
      videoBytes = base64Decode(b64);
    }

    return FetchedLinkContent(
      title: (body['title'] as String?)?.trim() ?? '',
      caption: (body['caption'] as String?)?.trim() ?? '',
      source: (body['source'] as String?)?.trim() ?? 'none',
      warning: (body['warning'] as String?)?.trim(),
      canonicalUrl: (body['canonicalUrl'] as String?)?.trim(),
      videoBytes: videoBytes,
      videoMimeType: (body['videoMimeType'] as String?)?.trim(),
      videoFileName: (body['videoFileName'] as String?)?.trim(),
      videoError: (body['videoError'] as String?)?.trim(),
    );
  }

  Future<FetchedLinkContent> _fetchFacebookDirect(String url) async {
    final pageResponse = await _client
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': _iphoneUa,
            'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
            'Accept': 'text/html,application/xhtml+xml',
          },
        )
        .timeout(const Duration(seconds: 25));

    if (pageResponse.statusCode < 200 || pageResponse.statusCode >= 400) {
      throw Exception(
        'Facebook-Seite konnte nicht geladen werden '
        '(${pageResponse.statusCode}).',
      );
    }

    final html = pageResponse.body;
    final caption = _pickBestFacebookCaption([
      _metaContent(html, 'og:image:alt'),
      _metaContent(html, 'og:title'),
      _metaContent(html, 'og:description'),
    ]);
    final title = _metaContent(html, 'og:title') ?? '';

    final mp4Url = _extractMp4Url(html) ??
        _metaContent(html, 'og:video:secure_url') ??
        _metaContent(html, 'og:video:url') ??
        _metaContent(html, 'og:video');

    Uint8List? videoBytes;
    String? videoError;
    if (mp4Url == null || mp4Url.isEmpty) {
      videoError =
          'Kein Video in der Facebook-Seite gefunden. '
          'Bitte speichern und unter „Video wählen“ anhängen.';
    } else {
      try {
        final videoResponse = await _client
            .get(
              Uri.parse(mp4Url),
              headers: {
                'User-Agent': _iphoneUa,
                'Accept': 'video/mp4,video/*,*/*',
                'Range': 'bytes=0-$_maxVideoBytes',
              },
            )
            .timeout(const Duration(seconds: 60));

        if (videoResponse.statusCode >= 200 &&
            videoResponse.statusCode < 400 &&
            videoResponse.bodyBytes.length >= 1000) {
          if (videoResponse.bodyBytes.length > _maxVideoBytes) {
            videoError =
                'Video ist zu groß für den automatischen Download. '
                'Bitte manuell anhängen.';
          } else {
            videoBytes = videoResponse.bodyBytes;
          }
        } else {
          videoError = 'Video-Datei konnte nicht heruntergeladen werden.';
        }
      } catch (_) {
        videoError = 'Video-Download ist fehlgeschlagen.';
      }
    }

    return FetchedLinkContent(
      title: title,
      caption: caption,
      source: caption.isNotEmpty ? 'facebook-combined' : 'none',
      warning: caption.isEmpty
          ? 'Keine Caption gefunden — bitte Text unter dem Video einfügen.'
          : null,
      canonicalUrl: _metaContent(html, 'og:url') ?? url,
      videoBytes: videoBytes,
      videoMimeType: videoBytes != null ? 'video/mp4' : null,
      videoFileName: videoBytes != null ? 'facebook-reel.mp4' : null,
      videoError: videoError,
    );
  }

  String _pickBestFacebookCaption(List<String?> candidates) {
    final cleaned = candidates
        .map((raw) => (raw ?? '').replaceAll('\r', '').trim())
        .where((t) => t.length >= 8)
        .toList();
    if (cleaned.isEmpty) return '';
    cleaned.sort((a, b) => b.length.compareTo(a.length));
    return cleaned.first;
  }

  String? _extractMp4Url(String html) {
    final matches = RegExp(
      r'https?:\\?/\\?/[^\s"<>]+?\.mp4[^\s"<>]*',
      caseSensitive: false,
    ).allMatches(html);
    if (matches.isEmpty) return null;

    var best = '';
    for (final match in matches) {
      var url = match.group(0)!;
      url = url
          .replaceAll(r'\/', '/')
          .replaceAll('&amp;', '&')
          .replaceAll(r'\u0025', '%');
      if (url.length > best.length) best = url;
    }
    return best.isEmpty ? null : best;
  }

  String? _metaContent(String html, String property) {
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
      if (match != null) {
        return match.group(1)!.replaceAll('&amp;', '&');
      }
    }
    return null;
  }
}
