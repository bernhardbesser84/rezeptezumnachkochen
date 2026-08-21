import 'package:http/http.dart' as http;

/// Löst Facebook-Share-/Story-Links zur öffentlichen Reel-URL auf.
///
/// Manche `/share/r/…`-Links zeigen nur auf `story.php` (Login-Wand).
/// Das Embed-Plugin verrät dann die echte `/reel/{id}/`-Adresse.
class FacebookShareResolve {
  FacebookShareResolve({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const iphoneUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
      'Mobile/15E148 Safari/604.1';
  static const facebookBotUa =
      'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';

  Future<List<String>> expandCandidateUrls(String pageUrl) async {
    final urls = <String>[];
    void add(String? raw) {
      final url = raw?.trim() ?? '';
      if (url.isEmpty || urls.contains(url)) return;
      if (!url.startsWith('http')) return;
      urls.add(url);
    }

    add(pageUrl);
    final uri = Uri.tryParse(pageUrl);
    if (uri != null) {
      final host = uri.host.replaceFirst('www.', '').toLowerCase();
      if (host.contains('facebook.com') ||
          host == 'fb.watch' ||
          host == 'fb.com') {
        add(uri.replace(host: 'm.facebook.com').toString());
      }
    }

    for (final start in List<String>.from(urls)) {
      for (final hop in await _followRedirects(start, facebookBotUa)) {
        add(hop);
      }
    }

    for (final candidate in List<String>.from(urls)) {
      if (!_needsPluginResolve(candidate)) continue;
      try {
        final reel = await resolveReelViaPlugin(candidate);
        add(reel);
      } catch (_) {
        // Nächsten Kandidaten versuchen.
      }
    }

    for (final candidate in List<String>.from(urls)) {
      final parsed = Uri.tryParse(candidate);
      final storyId =
          parsed?.queryParameters['story_fbid'] ??
          parsed?.queryParameters['v'] ??
          '';
      if (RegExp(r'^\d{10,}$').hasMatch(storyId)) {
        add('https://www.facebook.com/reel/$storyId/');
      }
    }

    return urls;
  }

  Future<String?> resolveReelViaPlugin(String pageUrl) async {
    final cleaned = _stripTracking(pageUrl);
    final targets = [
      Uri.https('www.facebook.com', '/plugins/post.php', {
        'href': cleaned,
        'show_text': 'true',
        'width': '500',
      }),
      Uri.https('www.facebook.com', '/plugins/video.php', {
        'href': cleaned,
        'show_text': 'true',
        'width': '500',
      }),
    ];

    for (final plugin in targets) {
      var current = plugin;
      for (var i = 0; i < 6; i++) {
        final response = await _client
            .send(
              http.Request('GET', current)
                ..headers.addAll({
                  'User-Agent': iphoneUa,
                  'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
                  'Accept': 'text/html,application/xhtml+xml',
                })
                ..followRedirects = false,
            )
            .timeout(const Duration(seconds: 20));
        final status = response.statusCode;
        if (status >= 300 && status < 400) {
          final loc = response.headers['location'];
          if (loc == null || loc.isEmpty) break;
          final next = Uri.parse(current.toString()).resolve(loc);
          if (next.path.toLowerCase().contains('/login')) break;
          final fromLoc =
              extractReelUrl(next.toString()) ??
              extractReelFromPluginHref(next.toString());
          if (fromLoc != null) return fromLoc;
          current = next;
          continue;
        }
        if (status >= 200 && status < 300) {
          final body = await response.stream.bytesToString();
          return extractReelUrl(body) ?? extractReelFromPluginHref(body);
        }
        break;
      }
    }
    return null;
  }

  Future<List<String>> _followRedirects(String startUrl, String userAgent) async {
    final hops = <String>[];
    final parsed = Uri.tryParse(startUrl);
    if (parsed == null) return hops;
    var current = parsed;

    for (var i = 0; i < 6; i++) {
      final url = current.toString();
      if (hops.contains(url)) break;
      hops.add(url);
      try {
        final response = await _client
            .send(
              http.Request('GET', current)
                ..headers.addAll({
                  'User-Agent': userAgent,
                  'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
                  'Accept': 'text/html,application/xhtml+xml',
                })
                ..followRedirects = false,
            )
            .timeout(const Duration(seconds: 20));
        final status = response.statusCode;
        if (status >= 300 && status < 400) {
          final loc = response.headers['location'];
          if (loc == null || loc.isEmpty) break;
          final next = current.resolve(loc);
          if (next.path.toLowerCase().contains('/login')) break;
          current = next;
          continue;
        }
      } catch (_) {
        break;
      }
      break;
    }
    return hops;
  }

  static bool _needsPluginResolve(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/share/r/') ||
        lower.contains('story.php') ||
        lower.contains('/posts/') ||
        lower.contains('permalink.php');
  }

  static String? extractReelUrl(String raw) {
    final match = RegExp(
      r'facebook\.com/reel/(\d+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return null;
    return 'https://www.facebook.com/reel/${match.group(1)}/';
  }

  static String? extractReelFromPluginHref(String raw) {
    final encoded = RegExp(
      r'facebook\.com%2Freel%2F(\d+)',
      caseSensitive: false,
    ).firstMatch(raw);
    if (encoded != null) {
      return 'https://www.facebook.com/reel/${encoded.group(1)}/';
    }
    final uri = Uri.tryParse(raw);
    final href = uri?.queryParameters['href'];
    if (href != null && href.isNotEmpty) {
      return extractReelUrl(href);
    }
    final hrefMatch = RegExp(
      r'''[?&]href=([^&"']+)''',
      caseSensitive: false,
    ).firstMatch(raw);
    if (hrefMatch != null) {
      try {
        return extractReelUrl(Uri.decodeComponent(hrefMatch.group(1)!));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static String _stripTracking(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final kept = Map<String, String>.from(uri.queryParameters)
      ..removeWhere(
        (key, _) => RegExp(
          r'^(mibextid|rdid|share_url|refsrc|_rdr)$',
          caseSensitive: false,
        ).hasMatch(key),
      );
    return uri.replace(queryParameters: kept.isEmpty ? null : kept).toString();
  }
}
