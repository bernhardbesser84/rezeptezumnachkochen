/**
 * Vercel Serverless: Caption / Beschreibung zu einem Video-Link laden.
 * Läuft auf dem Server — dadurch kein CORS-Problem im iPhone-Browser.
 *
 * Aufruf: GET /api/fetch-caption?url=https://...
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
    const result = await fetchCaption(rawUrl);
    res.status(200).json(result);
  } catch (e) {
    res.status(200).json({
      title: '',
      caption: '',
      source: 'none',
      warning:
        'Caption konnte nicht geladen werden. Bitte Text unter dem Video manuell kopieren.',
    });
  }
};

async function fetchCaption(url) {
  const host = safeHost(url);

  if (host.includes('youtube.com') || host === 'youtu.be') {
    const yt = await fetchYoutube(url);
    if (yt.caption) return yt;
  }

  if (host.includes('tiktok.com')) {
    const tt = await fetchTikTokOEmbed(url);
    if (tt.caption) return tt;
  }

  if (host.includes('instagram.com')) {
    const ig = await fetchInstagramOEmbed(url);
    if (ig.caption) return ig;
  }

  return fetchGenericOg(url);
}

function safeHost(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, '').toLowerCase();
  } catch (_) {
    return '';
  }
}

async function fetchHtml(url) {
  const response = await fetch(url, {
    headers: {
      'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
        + '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
      Accept: 'text/html,application/xhtml+xml',
    },
    redirect: 'follow',
  });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.text();
}

async function fetchYoutube(url) {
  const html = await fetchHtml(url);
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
  };
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

async function fetchTikTokOEmbed(url) {
  const endpoint =
    `https://www.tiktok.com/oembed?url=${encodeURIComponent(url)}`;
  const response = await fetch(endpoint, {
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) return { title: '', caption: '', source: 'none' };
  const data = await response.json();
  const title = (data.title || '').toString().trim();
  return {
    title,
    caption: title,
    source: title ? 'tiktok-oembed' : 'none',
  };
}

async function fetchInstagramOEmbed(url) {
  // Öffentliches oEmbed — oft eingeschränkt, aber einen Versuch wert.
  const endpoint =
    `https://www.instagram.com/api/v1/oembed/?url=${encodeURIComponent(url)}`;
  try {
    const response = await fetch(endpoint, {
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) return fetchGenericOg(url);
    const data = await response.json();
    const title = (data.title || '').toString().trim();
    return {
      title,
      caption: title,
      source: title ? 'instagram-oembed' : 'none',
    };
  } catch (_) {
    return fetchGenericOg(url);
  }
}

async function fetchGenericOg(url) {
  try {
    const html = await fetchHtml(url);
    const title = meta(html, 'og:title') || tagText(html, 'title') || '';
    const caption =
      meta(html, 'og:description') ||
      metaName(html, 'description') ||
      metaName(html, 'twitter:description') ||
      '';
    return {
      title: decodeEntities(title).trim(),
      caption: decodeEntities(caption).trim(),
      source: caption ? 'og' : 'none',
    };
  } catch (_) {
    return { title: '', caption: '', source: 'none' };
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
  return value
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'")
    .replace(/&nbsp;/g, ' ');
}
