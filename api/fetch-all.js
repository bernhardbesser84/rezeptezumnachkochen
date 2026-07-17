/**
 * Vercel Serverless: Caption + Video in einem Aufruf (weniger Facebook-Requests).
 *
 * Aufruf: GET /api/fetch-all?url=https://...
 * Antwort: JSON mit title, caption, optional videoBase64
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
    const result = await fetchAll(rawUrl);
    res.status(200).json(result);
  } catch (e) {
    res.status(200).json({
      title: '',
      caption: '',
      source: 'none',
      warning:
        'Link-Inhalte konnten nicht geladen werden. '
        + 'Bitte Caption und Video manuell ergänzen.',
      videoError: String(e.message || e),
    });
  }
};

// JSON-Antwort klein halten (Vercel ~4,5 MB Limit; Base64 +30 %).
const MAX_VIDEO_BYTES = 2_700_000;
const UA_IPHONE =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
  + 'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
  + 'Mobile/15E148 Safari/604.1';
const UA_FACEBOOK =
  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';

async function fetchAll(url) {
  const host = safeHost(url);
  const isFacebook =
    host.includes('facebook.com') || host === 'fb.watch' || host === 'fb.com';

  if (isFacebook) {
    return fetchFacebookCombined(url);
  }

  // Andere Plattformen: nur Caption (Video separat über fetch-video).
  const caption = await fetchCaptionOnly(url, host);
  return {
    ...caption,
    videoBase64: null,
    videoMimeType: null,
    videoFileName: null,
    videoSize: 0,
    videoError: null,
  };
}

async function fetchFacebookCombined(pageUrl) {
  let html = '';
  let finalUrl = pageUrl;

  // Ein HTML-Abruf (iPhone-UA liefert oft MP4 + Meta).
  try {
    const fetched = await fetchHtml(pageUrl, UA_IPHONE);
    html = fetched.html;
    finalUrl = fetched.finalUrl;
  } catch (_) {
    const fetched = await fetchHtml(pageUrl, UA_FACEBOOK);
    html = fetched.html;
    finalUrl = fetched.finalUrl;
  }

  if (html.includes('Error Facebook') && !html.includes('og:title')) {
    return {
      title: '',
      caption: '',
      source: 'none',
      warning:
        'Facebook hat keinen Inhalt geliefert. '
        + 'Bitte Caption und Video manuell ergänzen.',
      canonicalUrl: pageUrl,
      videoBase64: null,
      videoMimeType: null,
      videoFileName: null,
      videoSize: 0,
      videoError: 'Facebook-Seite blockiert oder Login nötig.',
    };
  }

  const ogTitle = decodeEntities(meta(html, 'og:title') || '');
  const ogImageAlt = decodeEntities(meta(html, 'og:image:alt') || '');
  const ogDescription = decodeEntities(
    meta(html, 'og:description') ||
      metaName(html, 'description') ||
      metaName(html, 'twitter:description') ||
      '',
  );
  const caption = pickBestFacebookCaption([
    ogImageAlt,
    ogTitle,
    ogDescription,
    decodeEntities(metaName(html, 'twitter:image:alt') || ''),
  ]);
  const title = cleanDishTitle(ogTitle || caption);
  const ogUrl = decodeEntities(meta(html, 'og:url') || '').trim();

  const mp4Candidates = [
    extractMp4Url(html),
    decodeEntities(meta(html, 'og:video:secure_url') || '').trim(),
    decodeEntities(meta(html, 'og:video:url') || '').trim(),
    decodeEntities(meta(html, 'og:video') || '').trim(),
  ].filter((u) => /^https?:\/\//i.test(u));

  let videoBase64 = null;
  let videoMimeType = null;
  let videoFileName = null;
  let videoSize = 0;
  let videoError = null;

  if (mp4Candidates.length === 0) {
    videoError =
      'Kein Video in der Facebook-Seite gefunden. '
      + 'Bitte speichern und unter „Video wählen“ anhängen.';
  } else {
    for (const videoUrl of mp4Candidates) {
      const dl = await downloadVideo(videoUrl);
      if (dl.ok) {
        videoBase64 = dl.bytes.toString('base64');
        videoMimeType = dl.mimeType;
        videoFileName = dl.fileName;
        videoSize = dl.bytes.length;
        videoError = null;
        break;
      }
      if (dl.error) videoError = dl.error;
    }
    if (!videoBase64 && !videoError) {
      videoError =
        'Video konnte nicht heruntergeladen werden. '
        + 'Bitte manuell speichern und anhängen.';
    }
  }

  return {
    title,
    caption,
    source: caption ? 'facebook-combined' : 'none',
    warning: caption
      ? null
      : 'Keine Caption gefunden — bitte Text unter dem Video manuell einfügen.',
    canonicalUrl: ogUrl || finalUrl || pageUrl,
    videoBase64,
    videoMimeType,
    videoFileName,
    videoSize,
    videoError,
  };
}

async function fetchCaptionOnly(url, host) {
  if (host.includes('youtube.com') || host === 'youtu.be') {
    return fetchYoutubeCaption(url);
  }
  if (host.includes('tiktok.com')) {
    return fetchTikTokOEmbed(url);
  }
  try {
    const { html } = await fetchHtml(url, UA_IPHONE);
    const title = decodeEntities(meta(html, 'og:title') || tagText(html, 'title') || '');
    const caption = decodeEntities(
      meta(html, 'og:description') ||
        metaName(html, 'description') ||
        '',
    ).trim();
    return {
      title: title.trim(),
      caption,
      source: caption ? 'og' : 'none',
      warning: caption ? null : 'Keine Caption gefunden.',
      canonicalUrl: url,
    };
  } catch (_) {
    return {
      title: '',
      caption: '',
      source: 'none',
      warning: 'Caption konnte nicht geladen werden.',
      canonicalUrl: url,
    };
  }
}

async function fetchYoutubeCaption(url) {
  const { html } = await fetchHtml(url, UA_IPHONE);
  const title = meta(html, 'og:title') || tagText(html, 'title') || '';
  let caption =
    shortDescriptionFromPlayer(html) ||
    meta(html, 'og:description') ||
    metaName(html, 'description') ||
    '';
  caption = decodeEntities(caption).trim();
  return {
    title: decodeEntities(title).trim(),
    caption,
    source: caption ? 'youtube' : 'none',
    warning: caption ? null : 'Keine YouTube-Beschreibung gefunden.',
    canonicalUrl: url,
  };
}

async function fetchTikTokOEmbed(url) {
  const endpoint = `https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`;
  const response = await fetch(endpoint, { headers: { Accept: 'application/json' } });
  if (!response.ok) {
    return { title: '', caption: '', source: 'none', warning: 'TikTok-Caption nicht gefunden.', canonicalUrl: url };
  }
  const data = await response.json();
  const title = (data.title || '').toString().trim();
  return {
    title,
    caption: title,
    source: title ? 'tiktok-oembed' : 'none',
    warning: title ? null : 'TikTok-Caption leer.',
    canonicalUrl: url,
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
  return { html: await response.text(), finalUrl: response.url || url };
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
      // plain
    }
    url = url.replace(/&amp;/g, '&');
    if (url.length > best.length) best = url;
  }
  return best;
}

async function downloadVideo(videoUrl) {
  const response = await fetch(videoUrl, {
    headers: {
      'User-Agent': UA_IPHONE,
      Accept: 'video/mp4,video/*,*/*',
      Range: `bytes=0-${MAX_VIDEO_BYTES}`,
    },
    redirect: 'follow',
  });

  if (!(response.ok || response.status === 206)) {
    return { ok: false };
  }

  const buf = Buffer.from(await response.arrayBuffer());
  if (buf.length < 1000) return { ok: false };
  if (buf.length > MAX_VIDEO_BYTES) {
    return {
      ok: false,
      error:
        'Video ist zu groß für den automatischen Download. '
        + 'Bitte speichern und unter „Video wählen“ anhängen.',
    };
  }

  const head = buf.slice(0, 64).toString('utf8');
  if (head.includes('<html') || head.includes('<!DOCTYPE')) {
    return { ok: false };
  }

  return {
    ok: true,
    bytes: buf,
    mimeType: 'video/mp4',
    fileName: 'facebook-reel.mp4',
  };
}

function pickBestFacebookCaption(candidates) {
  const cleaned = candidates
    .map((raw) => stripFacebookViewsPrefix(decodeEntities(raw || '')).trim())
    .filter((t) => t.length >= 8);
  if (cleaned.length === 0) return '';
  const complete = cleaned.filter((t) => !/\.\.\.\s*$/.test(t));
  const pool = complete.length > 0 ? complete : cleaned;
  pool.sort((a, b) => b.length - a.length);
  return pool[0];
}

function stripFacebookViewsPrefix(raw) {
  let t = (raw || '').replace(/\r/g, '').trim();
  const pipe = t.split('|');
  if (pipe.length >= 2) {
    const left = pipe[0].toLowerCase();
    if (/(aufrufe|views|reaktionen|reactions|likes|kommentare|comments|shares)/.test(left)) {
      t = pipe.slice(1).join('|').trim();
    }
  }
  return t;
}

function cleanDishTitle(raw) {
  let t = (raw || '').replace(/[\n\r]+/g, '\n').trim();
  t = t.split('\n')[0].trim().replace(/\s+/g, ' ');
  const parts = t.split('|').map((p) => p.trim()).filter(Boolean);
  if (parts.length >= 2) {
    const left = parts[0].toLowerCase();
    const right = parts[parts.length - 1].toLowerCase();
    if (/(aufrufe|views|reaktionen|reactions|likes|kommentare|comments|shares)/.test(left)) {
      t = parts.slice(1).join(' | ').trim();
    } else if (/^(facebook|instagram|tiktok|youtube|watch)$/.test(right)) {
      t = parts.slice(0, -1).join(' | ').trim();
    }
  }
  return t;
}

function shortDescriptionFromPlayer(html) {
  const m = html.match(/"shortDescription":"(.*?)"/);
  if (!m) return '';
  try {
    return JSON.parse(`"${m[1]}"`);
  } catch (_) {
    return m[1]
      .replace(/\\n/g, '\n')
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, '\\');
  }
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

function metaName(html, name) {
  const re = new RegExp(
    `<meta[^>]+name=["']${escapeReg(name)}["'][^>]+content=["']([^"']*)["']`,
    'i',
  );
  const re2 = new RegExp(
    `<meta[^>]+content=["']([^"']*)["'][^>]+name=["']${escapeReg(name)}["']`,
    'i',
  );
  const m = html.match(re) || html.match(re2);
  return m ? m[1] : '';
}

function tagText(html, tag) {
  const m = html.match(new RegExp(`<${tag}[^>]*>([^<]*)</${tag}>`, 'i'));
  return m ? m[1] : '';
}

function escapeReg(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function decodeEntities(value) {
  return (value || '')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&nbsp;/g, ' ');
}
