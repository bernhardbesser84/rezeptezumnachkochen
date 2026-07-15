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

  if (
    host.includes('facebook.com') ||
    host === 'fb.watch' ||
    host === 'fb.com'
  ) {
    return fetchFacebook(url);
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

const UA_FACEBOOK =
  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';
const UA_MOBILE =
  'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
  + '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

async function fetchHtml(url, userAgent = UA_MOBILE) {
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

async function fetchFacebook(url) {
  // Facebook liefert og:title/description zuverlässig an Crawler-UAs.
  // Wichtig: og:description ist oft abgeschnitten („…“),
  // og:title / og:image:alt enthalten den vollen Text.
  const agents = [UA_FACEBOOK, UA_MOBILE];
  for (const agent of agents) {
    try {
      const { html, finalUrl } = await fetchHtml(url, agent);
      if (html.includes('Error Facebook') && !html.includes('og:title')) {
        continue;
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
      if (caption || title) {
        return {
          title,
          caption,
          source: caption ? 'facebook-og' : 'none',
          canonicalUrl: ogUrl || finalUrl || url,
        };
      }
    } catch (_) {
      // Nächsten UA versuchen.
    }
  }
  return {
    title: '',
    caption: '',
    source: 'none',
    warning:
      'Facebook hat keinen Beschreibungstext geliefert. '
      + 'Bitte den Text unter dem Video manuell kopieren.',
  };
}

/** Längsten, nicht abgeschnittenen Caption-Text wählen. */
function pickBestFacebookCaption(candidates) {
  const cleaned = candidates
    .map((raw) => stripFacebookViewsPrefix(decodeEntities(raw || '')).trim())
    .filter((t) => t.length >= 8);

  if (cleaned.length === 0) return '';

  // Vollständige Texte bevorzugen (nicht mit „…“ abgeschnitten).
  const complete = cleaned.filter((t) => !/\.\.\.\s*$/.test(t));
  const pool = complete.length > 0 ? complete : cleaned;
  pool.sort((a, b) => b.length - a.length);
  return pool[0];
}

function stripFacebookViewsPrefix(raw) {
  let t = (raw || '').replace(/\r/g, '').trim();
  // „58K views · … | High Protein …“ → ab dem Gerichtsnamen
  const pipe = t.split('|');
  if (pipe.length >= 2) {
    const left = pipe[0].toLowerCase();
    if (/(aufrufe|views|reaktionen|reactions|likes|kommentare|comments|shares)/.test(left)) {
      t = pipe.slice(1).join('|').trim();
    }
  }
  return t;
}

async function fetchYoutube(url) {
  const { html } = await fetchHtml(url);
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
    const { html } = await fetchHtml(url);
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

/** „12 Aufrufe | High Protein Döner Wrap“ → Gerichtsname. */
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
    .replace(/&nbsp;/g, ' ')
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => {
      try {
        return String.fromCodePoint(parseInt(hex, 16));
      } catch (_) {
        return _;
      }
    })
    .replace(/&#(\d+);/g, (_, num) => {
      try {
        return String.fromCodePoint(parseInt(num, 10));
      } catch (_) {
        return _;
      }
    });
}
