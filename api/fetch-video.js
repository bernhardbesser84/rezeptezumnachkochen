/**
 * Vercel Serverless: Video-Datei zu einem Social-Link laden (z. B. Facebook).
 * Läuft auf dem Server — kein CORS-Problem im iPhone-Browser.
 *
 * Aufruf: GET /api/fetch-video?url=https://...
 * Erfolg: video/mp4 Bytes
 * Fehler: application/json { error, warning }
 */
module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
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
    const result = await fetchVideo(rawUrl);
    if (!result.ok) {
      res.status(200).json({
        error: result.error,
        warning: result.warning,
      });
      return;
    }

    res.setHeader('Content-Type', result.mimeType || 'video/mp4');
    res.setHeader('X-Video-Filename', result.fileName || 'rezept-video.mp4');
    res.setHeader('X-Video-Source', result.source || 'link');
    res.setHeader('X-Video-Size', String(result.bytes.length));
    res.status(200).send(Buffer.from(result.bytes));
  } catch (e) {
    res.status(200).json({
      error:
        'Video konnte nicht vom Link geladen werden. '
        + 'Bitte die Datei manuell speichern und unter „Video wählen“ anhängen.',
    });
  }
};

const MAX_BYTES = 3_800_000; // unter Vercel-Limit (~4,5 MB Antwort)
const UA_IPHONE =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
  + 'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
  + 'Mobile/15E148 Safari/604.1';
const UA_FACEBOOK =
  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';

async function fetchVideo(pageUrl) {
  const host = safeHost(pageUrl);
  const isFacebook =
    host.includes('facebook.com') || host === 'fb.watch' || host === 'fb.com';

  if (!isFacebook && !host.includes('fb.watch')) {
    // Andere Plattformen: erst Meta/og:video versuchen
    const fromOg = await videoFromOgTags(pageUrl, UA_IPHONE);
    if (fromOg.ok) return fromOg;
    return {
      ok: false,
      error:
        'Automatischer Video-Download für diese Plattform klappt oft nicht. '
        + 'Bitte Video speichern und manuell anhängen.',
    };
  }

  // Facebook: Mobile-HTML enthält oft eine direkte .mp4-URL.
  const fromMobile = await videoFromHtmlMp4(pageUrl, UA_IPHONE);
  if (fromMobile.ok) return fromMobile;

  const fromBot = await videoFromOgTags(pageUrl, UA_FACEBOOK);
  if (fromBot.ok) return fromBot;

  return {
    ok: false,
    error:
      'Facebook hat kein ladbares Video geliefert. '
      + 'Tipp: Im Browser auf Teilen → „Video speichern“ / Download, '
      + 'dann hier „Video wählen“.',
    warning: 'facebook-no-mp4',
  };
}

function safeHost(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, '').toLowerCase();
  } catch (_) {
    return '';
  }
}

async function fetchHtml(url, userAgent) {
  const response = await fetch(url, {
    headers: {
      'User-Agent': userAgent,
      'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
      Accept: 'text/html,application/xhtml+xml',
    },
    redirect: 'follow',
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.text();
}

async function videoFromHtmlMp4(pageUrl, userAgent) {
  const html = await fetchHtml(pageUrl, userAgent);
  const mp4Url = extractMp4Url(html);
  if (!mp4Url) return { ok: false };
  return downloadVideo(mp4Url, 'facebook-reel.mp4', 'facebook-mp4');
}

async function videoFromOgTags(pageUrl, userAgent) {
  const html = await fetchHtml(pageUrl, userAgent);
  const candidates = [
    meta(html, 'og:video:secure_url'),
    meta(html, 'og:video:url'),
    meta(html, 'og:video'),
    extractMp4Url(html),
  ]
    .map((u) => decodeEntities(u || '').trim())
    .filter((u) => /^https?:\/\//i.test(u));

  for (const videoUrl of candidates) {
    const result = await downloadVideo(
      videoUrl,
      'rezept-video.mp4',
      'og-video',
    );
    if (result.ok) return result;
  }
  return { ok: false };
}

function extractMp4Url(html) {
  const matches = html.match(
    /https?:\\?\/\\?\/[^"'<>\s]+?\.mp4[^"'<>\s]*/gi,
  );
  if (!matches || matches.length === 0) return '';
  let best = '';
  for (const raw of matches) {
    let url = decodeEntities(raw)
      .replace(/\\\//g, '/')
      .replace(/\\u0025/g, '%');
    try {
      url = JSON.parse(`"${url.replace(/"/g, '\\"')}"`);
    } catch (_) {
      // schon plain
    }
    url = url.replace(/&amp;/g, '&');
    if (url.length > best.length) best = url;
  }
  return best;
}

async function downloadVideo(videoUrl, fileName, source) {
  const response = await fetch(videoUrl, {
    headers: {
      'User-Agent': UA_IPHONE,
      Accept: 'video/mp4,video/*,*/*',
      Range: `bytes=0-${MAX_BYTES}`,
    },
    redirect: 'follow',
  });

  if (!(response.ok || response.status === 206)) {
    return { ok: false };
  }

  const buf = Buffer.from(await response.arrayBuffer());
  if (buf.length < 1000) return { ok: false };
  if (buf.length > MAX_BYTES) {
    return {
      ok: false,
      error:
        'Video ist zu groß für den automatischen Download. '
        + 'Bitte speichern und manuell unter „Video wählen“ anhängen.',
    };
  }

  // Grobe MP4-Signatur (ftyp) oder zumindest nicht HTML
  const head = buf.slice(0, 64).toString('utf8');
  if (head.includes('<html') || head.includes('<!DOCTYPE')) {
    return { ok: false };
  }

  return {
    ok: true,
    bytes: buf,
    mimeType: 'video/mp4',
    fileName,
    source,
  };
}

function meta(html, property) {
  const re = new RegExp(
    `<meta[^>]+property=["']${escapeReg(property)}["'][^>]+content=["']([^"']*)["']`,
    'i',
  );
  const re2 = new RegExp(
    `<meta[^>]+content=["']([^"']*)["'][^>]+property=["']${escapeReg(property)}["']`,
    'i',
  );
  const m = html.match(re) || html.match(re2);
  return m ? m[1] : '';
}

function escapeReg(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function decodeEntities(value) {
  return value
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'");
}
