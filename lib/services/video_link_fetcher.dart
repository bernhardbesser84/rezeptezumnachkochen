import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Lädt die Video-Datei zu einem Rezept-Link (z. B. Facebook-Reel).
class FetchedVideo {
  const FetchedVideo({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.source,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  final String source;
}

class VideoLinkFetcher {
  VideoLinkFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _maxBytes = 3800000;
  static const _iphoneUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
      'Mobile/15E148 Safari/604.1';

  Future<FetchedVideo> fetchFromUrl(String rawUrl) async {
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

  Future<FetchedVideo> _fetchViaApi(String url) async {
    final endpoint = Uri.parse('/api/fetch-video').replace(
      queryParameters: {'url': url},
    );
    final response = await _client
        .get(endpoint)
        .timeout(const Duration(seconds: 60));

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      final body = jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
      throw Exception(
        (body['error'] as String?)?.trim().isNotEmpty == true
            ? body['error'] as String
            : 'Video konnte nicht vom Link geladen werden.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Video konnte nicht geladen werden (${response.statusCode}).',
      );
    }

    final bytes = response.bodyBytes;
    if (bytes.length < 1000) {
      throw Exception('Video-Antwort war leer oder ungültig.');
    }

    return FetchedVideo(
      bytes: bytes,
      mimeType: contentType.contains('video')
          ? contentType.split(';').first.trim()
          : 'video/mp4',
      fileName: response.headers['x-video-filename'] ?? 'facebook-reel.mp4',
      source: response.headers['x-video-source'] ?? 'api',
    );
  }

  Future<FetchedVideo> _fetchDirect(String url) async {
    final host = Uri.parse(url).host.replaceFirst('www.', '').toLowerCase();
    final isFacebook =
        host.contains('facebook.com') || host == 'fb.watch' || host == 'fb.com';

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
        'Seite zum Video konnte nicht geladen werden '
        '(${pageResponse.statusCode}).',
      );
    }

    final html = pageResponse.body;
    final videoUrl = _extractMp4Url(html) ??
        _metaContent(html, 'og:video:secure_url') ??
        _metaContent(html, 'og:video:url') ??
        _metaContent(html, 'og:video');

    if (videoUrl == null || videoUrl.isEmpty) {
      throw Exception(
        isFacebook
            ? 'Facebook hat kein ladbares Video geliefert. '
                'Tipp: Video speichern und unter „Video wählen“ anhängen.'
            : 'Unter dem Link wurde kein Video gefunden.',
      );
    }

    final videoResponse = await _client
        .get(
          Uri.parse(videoUrl),
          headers: {
            'User-Agent': _iphoneUa,
            'Accept': 'video/mp4,video/*,*/*',
            'Range': 'bytes=0-$_maxBytes',
          },
        )
        .timeout(const Duration(seconds: 60));

    if (videoResponse.statusCode < 200 || videoResponse.statusCode >= 400) {
      throw Exception(
        'Video-Datei konnte nicht heruntergeladen werden '
        '(${videoResponse.statusCode}).',
      );
    }

    final bytes = videoResponse.bodyBytes;
    if (bytes.length < 1000) {
      throw Exception('Video-Datei war leer.');
    }
    if (bytes.length > _maxBytes) {
      throw Exception(
        'Video ist zu groß für den automatischen Download. '
        'Bitte speichern und manuell anhängen.',
      );
    }

    return FetchedVideo(
      bytes: bytes,
      mimeType: 'video/mp4',
      fileName: isFacebook ? 'facebook-reel.mp4' : 'rezept-video.mp4',
      source: 'direct',
    );
  }

  String? _extractMp4Url(String html) {
    // Keine Anführungszeichen/Leerzeichen/Tags in der URL.
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
