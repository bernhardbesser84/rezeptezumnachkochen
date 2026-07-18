import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'youtube_caption.dart';

/// Lädt die Video-Datei zu einem Rezept-Link (Facebook / YouTube).
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

  /// Web/API: unter Vercel-Limit. Nativ etwas großzügiger.
  static const maxBytesWeb = 3800000;
  static const maxBytesNative = 15000000;

  static const _iphoneUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
      'Mobile/15E148 Safari/604.1';
  static const _androidYtUa =
      'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip';

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
      mimeType: contentType.contains('video') || contentType.contains('audio')
          ? contentType.split(';').first.trim()
          : 'video/mp4',
      fileName: response.headers['x-video-filename'] ?? 'rezept-video.mp4',
      source: response.headers['x-video-source'] ?? 'api',
    );
  }

  Future<FetchedVideo> _fetchDirect(String url) async {
    if (isYoutubeUrl(url)) {
      return _fetchYoutubeDirect(url);
    }
    return _fetchHtmlMp4Direct(url);
  }

  Future<FetchedVideo> _fetchYoutubeDirect(String url) async {
    final videoId = youtubeVideoId(url);
    if (videoId == null) {
      throw Exception('Das sieht nicht nach einem YouTube-Link aus.');
    }

    final response = await _client
        .post(
          Uri.parse(
            'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
          ),
          headers: {
            'Content-Type': 'application/json',
            'User-Agent': _androidYtUa,
          },
          body: jsonEncode({
            'context': {
              'client': {
                'clientName': 'ANDROID',
                'clientVersion': '20.10.38',
                'androidSdkVersion': 30,
                'hl': 'de',
                'gl': 'DE',
              },
            },
            'videoId': videoId,
            'contentCheckOk': true,
            'racyCheckOk': true,
          }),
        )
        .timeout(const Duration(seconds: 25));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'YouTube hat das Video nicht freigegeben '
        '(${response.statusCode}). Bitte manuell anhängen.',
      );
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) {
      throw Exception('YouTube-Antwort war ungültig.');
    }

    final playability = json['playabilityStatus'];
    final status = playability is Map
        ? '${playability['status'] ?? ''}'
        : '';
    if (status.isNotEmpty && status != 'OK') {
      throw Exception(
        'YouTube blockiert den automatischen Video-Download. '
        'Bitte in der YouTube-App speichern und hier unter '
        '„Video wählen“ anhängen.',
      );
    }

    final picked = pickYoutubeStreamForTest(json, maxBytes: maxBytesNative);
    if (picked == null) {
      throw Exception(
        'Kein passendes YouTube-Video unter der Größengrenze gefunden. '
        'Bitte Datei manuell anhängen.',
      );
    }

    return _downloadBytes(
      picked.url,
      fileName: picked.fileName,
      mimeType: picked.mimeType,
      source: picked.source,
      maxBytes: maxBytesNative,
    );
  }

  Future<FetchedVideo> _fetchHtmlMp4Direct(String url) async {
    final host = Uri.parse(url).host.replaceFirst('www.', '').toLowerCase();
    final isFacebook = host.contains('facebook.com') ||
        host == 'fb.watch' ||
        host == 'fb.com';

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

    return _downloadBytes(
      videoUrl,
      fileName: isFacebook ? 'facebook-reel.mp4' : 'rezept-video.mp4',
      mimeType: 'video/mp4',
      source: 'direct',
      maxBytes: maxBytesNative,
    );
  }

  Future<FetchedVideo> _downloadBytes(
    String videoUrl, {
    required String fileName,
    required String mimeType,
    required String source,
    required int maxBytes,
  }) async {
    final videoResponse = await _client
        .get(
          Uri.parse(videoUrl),
          headers: {
            'User-Agent': _iphoneUa,
            'Accept': 'video/mp4,audio/mp4,video/*,audio/*,*/*',
            'Range': 'bytes=0-$maxBytes',
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
    if (bytes.length > maxBytes) {
      throw Exception(
        'Video ist zu groß für den automatischen Download. '
        'Bitte speichern und manuell anhängen.',
      );
    }

    return FetchedVideo(
      bytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
      source: source,
    );
  }

  String? _extractMp4Url(String html) {
    final matches = RegExp(
      r'''https?:\\?/\\?/[^"' <>]+?\.mp4[^"'<>]*''',
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

/// Für Tests und direkte Auswahl der YouTube-Stream-URL.
({String url, String mimeType, String fileName, String source})?
    pickYoutubeStreamForTest(
  Map<String, dynamic> playerJson, {
  int maxBytes = VideoLinkFetcher.maxBytesWeb,
}) {
  final streaming = playerJson['streamingData'];
  if (streaming is! Map) return null;

  final progressive = streaming['formats'] is List
      ? streaming['formats'] as List
      : const [];
  final adaptive = streaming['adaptiveFormats'] is List
      ? streaming['adaptiveFormats'] as List
      : const [];

  final candidates =
      <({String url, int size, String mimeType, String fileName, String source})>[];

  for (final item in progressive) {
    if (item is! Map) continue;
    final url = '${item['url'] ?? ''}';
    final mime = '${item['mimeType'] ?? ''}';
    if (url.isEmpty || !mime.contains('video/mp4')) continue;
    final size = int.tryParse('${item['contentLength'] ?? ''}') ?? 0;
    if (size > 0 && size > maxBytes) continue;
    candidates.add((
      url: url,
      size: size,
      mimeType: 'video/mp4',
      fileName: 'youtube-video.mp4',
      source: 'youtube-itag-${item['itag'] ?? ' progressive'}',
    ));
  }

  for (final item in adaptive) {
    if (item is! Map) continue;
    final url = '${item['url'] ?? ''}';
    final mime = '${item['mimeType'] ?? ''}';
    if (url.isEmpty || !mime.startsWith('audio/mp4')) continue;
    final size = int.tryParse('${item['contentLength'] ?? ''}') ?? 0;
    if (size > 0 && size > maxBytes) continue;
    candidates.add((
      url: url,
      size: size,
      mimeType: 'audio/mp4',
      fileName: 'youtube-audio.m4a',
      source: 'youtube-audio-${item['itag'] ?? 'm4a'}',
    ));
  }

  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final av = a.mimeType.startsWith('video') ? 0 : 1;
    final bv = b.mimeType.startsWith('video') ? 0 : 1;
    if (av != bv) return av - bv;
    final as = a.size == 0 ? 1 << 30 : a.size;
    final bs = b.size == 0 ? 1 << 30 : b.size;
    return as.compareTo(bs);
  });
  final best = candidates.first;
  return (
    url: best.url,
    mimeType: best.mimeType,
    fileName: best.fileName,
    source: best.source,
  );
}
