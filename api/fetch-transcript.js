/**
 * Vercel Serverless: YouTube-Untertitel / Transkript laden.
 * Läuft auf dem Server — kein CORS-Problem im iPhone-Browser.
 *
 * Aufruf: GET /api/fetch-transcript?url=https://youtube.com/watch?v=...
 * Antwort: { transcript, source, warning? }
 *
 * Strategie:
 * 1) Innertube player API (ANDROID/WEB) → captionTracks
 * 2) captionTracks aus watch-HTML (falls noch vorhanden)
 * 3) öffentliche timedtext-Endpunkte
 */
module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  if (req.method !== 'GET') {
    res.status(405).json({ error: 'Nur GET erlaubt.' });
    return;
  }

  const rawUrl = (req.query.url || '').toString().trim();
  if (!rawUrl || !/^https?:\/\//i.test(rawUrl)) {
    res.status(400).json({ error: 'Bitte einen gültigen http(s)-Link angeben.' });
    return;
  }

  try {
    const result = await fetchTranscript(rawUrl);
    res.status(200).json(result);
  } catch (_) {
    res.status(200).json({
      transcript: '',
      source: 'none',
      warning:
        'Untertitel konnten nicht geladen werden. '
        + 'Bitte Caption-Text einfügen oder später erneut versuchen.',
    });
  }
};

const UA_MOBILE =
  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
  + '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const UA_ANDROID_APP =
  'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip';

async function fetchTranscript(url) {
  const videoId = youtubeId(url);
  if (!videoId) {
    return {
      transcript: '',
      source: 'none',
      warning: 'Das sieht nicht nach einem YouTube-Link aus.',
    };
  }

  // 1) Innertube (zuverlässiger als HTML, wenn YouTube nicht blockiert)
  const fromInnertube = await transcriptFromInnertube(videoId);
  if (fromInnertube) return fromInnertube;

  // 2) Watch-HTML → captionTracks (wie bisher in media_transcript.dart)
  const fromHtml = await transcriptFromWatchHtml(videoId);
  if (fromHtml) return fromHtml;

  // 3) Öffentliche timedtext-Endpunkte
  for (const lang of ['de', 'en', 'a.de', 'a.en']) {
    const timed = await downloadTimedText(
      `https://www.youtube.com/api/timedtext?v=${videoId}&lang=${lang}`,
    );
    if (timed) {
      return { transcript: timed, source: `youtube-timedtext-${lang}` };
    }
  }

  return {
    transcript: '',
    source: 'none',
    warning:
      'Keine Untertitel für dieses Video gefunden. '
      + 'Manche Videos haben keine Untertitel — oder YouTube blockiert den Abruf.',
  };
}

async function transcriptFromInnertube(videoId) {
  const clients = [
    {
      name: 'android',
      client: {
        clientName: 'ANDROID',
        clientVersion: '20.10.38',
        androidSdkVersion: 30,
        userAgent: UA_ANDROID_APP,
        hl: 'de',
        gl: 'DE',
      },
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': UA_ANDROID_APP,
      },
    },
    {
      name: 'web',
      client: {
        clientName: 'WEB',
        clientVersion: '2.20240101.00.00',
        hl: 'de',
        gl: 'DE',
      },
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': UA_MOBILE,
        'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
      },
    },
  ];

  for (const entry of clients) {
    try {
      const response = await fetch(
        'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
        {
          method: 'POST',
          headers: entry.headers,
          body: JSON.stringify({
            context: { client: entry.client },
            videoId,
          }),
        },
      );
      if (!response.ok) continue;
      const json = await response.json();
      const tracks =
        json?.captions?.playerCaptionsTracklistRenderer?.captionTracks;
      if (!Array.isArray(tracks) || tracks.length === 0) continue;

      const preferred =
        tracks.find((t) => String(t.languageCode || '').startsWith('de'))
        || tracks[0];
      if (!preferred?.baseUrl) continue;

      const transcript = await downloadTimedText(preferred.baseUrl);
      if (transcript) {
        return {
          transcript,
          source: `youtube-innertube-${entry.name}`,
        };
      }
    } catch (_) {
      // Nächsten Client versuchen.
    }
  }
  return null;
}

async function transcriptFromWatchHtml(videoId) {
  try {
    const watchUrl = `https://www.youtube.com/watch?v=${videoId}`;
    const response = await fetch(watchUrl, {
      headers: {
        'User-Agent': UA_MOBILE,
        'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
        Accept: 'text/html,application/xhtml+xml',
      },
      redirect: 'follow',
    });
    if (!response.ok) return null;
    const html = await response.text();
    const captionUrl = findCaptionTrackUrl(html);
    if (!captionUrl) return null;
    const transcript = await downloadTimedText(captionUrl);
    if (!transcript) return null;
    return { transcript, source: 'youtube-captionTracks' };
  } catch (_) {
    return null;
  }
}

function youtubeId(url) {
  try {
    const uri = new URL(url.trim());
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (host === 'youtu.be') {
      const id = uri.pathname.split('/').filter(Boolean)[0];
      return id && id.length >= 6 ? id : null;
    }
    if (host.includes('youtube.com')) {
      const v = uri.searchParams.get('v');
      if (v) return v;
      const parts = uri.pathname.split('/').filter(Boolean);
      if (
        parts.length >= 2
        && (parts[0] === 'shorts' || parts[0] === 'embed' || parts[0] === 'live')
      ) {
        return parts[1];
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

function findCaptionTrackUrl(html) {
  const match = html.match(/"captionTracks":\s*(\[.*?\])/s);
  if (!match) return null;
  try {
    const raw = match[1]
      .replace(/\\u0026/g, '&')
      .replace(/\\u003d/g, '=')
      .replace(/\\\//g, '/');
    const list = JSON.parse(raw);
    if (!Array.isArray(list) || list.length === 0) return null;

    let preferred = null;
    for (const item of list) {
      if (!item || typeof item !== 'object') continue;
      const lang = String(item.languageCode || '').toLowerCase();
      if (lang.startsWith('de')) {
        preferred = item;
        break;
      }
      if (!preferred) preferred = item;
    }
    let baseUrl = preferred && preferred.baseUrl ? String(preferred.baseUrl) : '';
    if (!baseUrl) return null;
    return baseUrl
      .replace(/\\u0026/g, '&')
      .replace(/\\u003d/g, '=')
      .replace(/\\\//g, '/');
  } catch (_) {
    return null;
  }
}

async function downloadTimedText(url) {
  try {
    // JSON3 ist oft robuster als Standard-XML
    const withFmt = url.includes('fmt=')
      ? url
      : `${url}${url.includes('?') ? '&' : '?'}fmt=json3`;

    for (const candidate of [withFmt, url]) {
      const response = await fetch(candidate, {
        headers: {
          'User-Agent': UA_MOBILE,
          'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
        },
        redirect: 'follow',
      });
      if (!response.ok) continue;
      const body = await response.text();
      if (!body || !body.trim()) continue;

      if (body.trim().startsWith('{')) {
        try {
          const json = JSON.parse(body);
          const events = json.events || [];
          const parts = [];
          for (const event of events) {
            const segs = (event && event.segs) || [];
            for (const seg of segs) {
              if (seg && seg.utf8 != null) parts.push(String(seg.utf8));
            }
          }
          if (parts.length > 0) return parts.join('').replace(/\n/g, ' ').trim();
        } catch (_) {
          // XML versuchen
        }
      }

      const xmlParts = [];
      const textRe = /<text[^>]*>([\s\S]*?)<\/text>/gi;
      let m;
      while ((m = textRe.exec(body)) !== null) {
        const decoded = decodeXml(m[1] || '');
        if (decoded) xmlParts.push(decoded);
      }
      if (xmlParts.length > 0) return xmlParts.join(' ').trim();
    }
    return null;
  } catch (_) {
    return null;
  }
}

function decodeXml(value) {
  return value
    .replace(/<[^>]+>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\n/g, ' ')
    .trim();
}
