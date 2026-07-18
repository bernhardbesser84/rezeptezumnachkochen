import 'dart:convert';

/// Hilfen zum Lesen der YouTube-Beschreibung (nicht die sichtbare „Caption“
/// wie bei Instagram — bei Shorts steckt der Text in der Beschreibung).

const kYoutubeManualHint =
    'YouTube-Beschreibung konnte nicht geladen werden. '
    'Bitte auf dem Short den Titel antippen → Beschreibung → „…mehr“, '
    'dann den ganzen Text kopieren und hier einfügen.';

String? youtubeVideoId(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final host = uri.host.replaceFirst('www.', '').toLowerCase();
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

bool isYoutubeUrl(String url) {
  return youtubeVideoId(url) != null;
}

/// YouTube liefert bei Bot-Schutz oft diesen Platzhalter statt der echten Beschreibung.
bool isYoutubeGarbageCaption({
  required String title,
  required String caption,
}) {
  final t = title.trim().toLowerCase();
  final c = caption.trim().toLowerCase();
  if (c.isEmpty) return true;
  if (t == 'youtube' || t == 'youtube.com') return true;
  if (c.contains('teile deine videos mit freunden')) return true;
  if (c.contains('enjoy the videos and music you love')) return true;
  if (c.contains('share your videos with friends, family')) return true;
  return false;
}

/// Liest Titel + Beschreibung nur wenn der Player-Status OK ist.
({String title, String caption})? youtubeDetailsFromPlayerHtml(String html) {
  final jsonText = _extractYtInitialPlayerResponse(html);
  if (jsonText == null) return null;
  try {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) return null;
    final playability = decoded['playabilityStatus'];
    final status =
        playability is Map ? '${playability['status'] ?? ''}' : '';
    if (status.isNotEmpty && status != 'OK') return null;

    final details = decoded['videoDetails'];
    if (details is! Map) return null;
    final title = '${details['title'] ?? ''}'.trim();
    final caption = '${details['shortDescription'] ?? ''}'.trim();
    if (title.isEmpty && caption.isEmpty) return null;
    return (title: title, caption: caption);
  } catch (_) {
    return null;
  }
}

String? _extractYtInitialPlayerResponse(String html) {
  const marker = 'ytInitialPlayerResponse';
  final idx = html.indexOf(marker);
  if (idx < 0) return null;
  final eq = html.indexOf('=', idx + marker.length);
  if (eq < 0) return null;
  var i = eq + 1;
  while (i < html.length &&
      (html.codeUnitAt(i) == 32 ||
          html.codeUnitAt(i) == 9 ||
          html.codeUnitAt(i) == 10 ||
          html.codeUnitAt(i) == 13)) {
    i += 1;
  }
  if (i >= html.length || html[i] != '{') return null;

  var depth = 0;
  var inString = false;
  var escape = false;
  for (var j = i; j < html.length; j++) {
    final ch = html[j];
    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch == r'\') {
        escape = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
      continue;
    }
    if (ch == '{') depth += 1;
    if (ch == '}') {
      depth -= 1;
      if (depth == 0) {
        return html.substring(i, j + 1);
      }
    }
  }
  return null;
}
