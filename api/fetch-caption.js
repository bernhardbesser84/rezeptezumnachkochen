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

const {
  expandFacebookCandidateUrls,
} = require('./facebook_resolve');

async function fetchFacebook(url) {
  // Share-Links (/share/r/…) zeigen oft auf story.php (Login).
  // Zuerst echte Reel-URL auflösen, dann og:title / og:description lesen.
  const candidates = await expandFacebookCandidateUrls(url);
  const agents = [UA_FACEBOOK, UA_MOBILE];
  for (const candidate of candidates) {
    for (const agent of agents) {
      try {
        const { html, finalUrl } = await fetchHtml(candidate, agent);
        if (html.includes('Error Facebook') && !html.includes('og:title')) {
          continue;
        }
        // Login-Seiten haben keinen Rezepttext.
        if (/log into facebook|bei facebook anmelden/i.test(
          meta(html, 'og:title') || '',
        )) {
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
        const imageUrl = decodeEntities(
          meta(html, 'og:image') ||
            meta(html, 'og:image:url') ||
            meta(html, 'og:image:secure_url') ||
            '',
        ).trim();
        if (caption || title) {
          return {
            title,
            caption,
            source: caption ? 'facebook-og' : 'none',
            canonicalUrl: ogUrl || finalUrl || candidate,
            imageUrl,
          };
        }
      } catch (_) {
        // Nächsten UA / Link versuchen.
      }
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

const YOUTUBE_MANUAL_HINT =
  'YouTube-Beschreibung konnte nicht geladen werden. '
  + 'Bitte auf dem Short den Titel antippen → Beschreibung → „…mehr“, '
  + 'dann den ganzen Text kopieren und hier einfügen.';

async function fetchYoutube(url) {
  const videoId = youtubeVideoId(url);
  if (!videoId) {
    return {
      title: '',
      caption: '',
      source: 'none',
      warning: 'Das sieht nicht nach einem YouTube-Link aus.',
    };
  }

  const watchUrl = `https://www.youtube.com/watch?v=${videoId}`;
  const agents = [
    UA_MOBILE,
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      + '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  ];

  // 1) Watch-HTML: nur echte Player-Daten mit playability OK nutzen.
  //    Platzhalter wie „Teile deine Videos…“ / Titel „YouTube“ verwerfen.
  for (const agent of agents) {
    try {
      const { html } = await fetchHtml(watchUrl, agent);
      const fromPlayer = detailsFromPlayerResponse(html);
      if (fromPlayer && !isYoutubeGarbage(fromPlayer.title, fromPlayer.caption)) {
        return {
          title: fromPlayer.title,
          caption: fromPlayer.caption,
          source: 'youtube-player',
          imageUrl: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
        };
      }
    } catch (_) {
      // Nächsten UA versuchen.
    }
  }

  // 2) Innertube (ANDROID) — oft robuster als Meta-Tags.
  try {
    const fromApi = await youtubeDetailsFromInnertube(videoId);
    if (fromApi && !isYoutubeGarbage(fromApi.title, fromApi.caption)) {
      return {
        title: fromApi.title,
        caption: fromApi.caption,
        source: 'youtube-innertube',
        imageUrl: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
      };
    }
  } catch (_) {
    // Fallback unten.
  }

  // 3) oEmbed liefert zuverlässig den Titel (nicht die volle Beschreibung).
  const oembedTitle = await youtubeOEmbedTitle(watchUrl);
  return {
    title: oembedTitle,
    caption: '',
    source: 'none',
    warning: YOUTUBE_MANUAL_HINT,
    imageUrl: `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg`,
  };
}

function youtubeVideoId(url) {
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

function isYoutubeGarbage(title, caption) {
  const t = (title || '').trim().toLowerCase();
  const c = (caption || '').trim().toLowerCase();
  if (!c) return true;
  if (t === 'youtube' || t === 'youtube.com') return true;
  if (c.includes('teile deine videos mit freunden')) return true;
  if (c.includes('enjoy the videos and music you love')) return true;
  if (c.includes('share your videos with friends, family')) return true;
  return false;
}

function detailsFromPlayerResponse(html) {
  const json = extractYtInitialPlayerResponse(html);
  if (!json) return null;
  const status = String(json?.playabilityStatus?.status || '');
  // Nur OK-Antworten vertrauen — sonst liefert YouTube Fake-Beschreibungen.
  if (status && status !== 'OK') return null;
  const title = decodeEntities(String(json?.videoDetails?.title || '')).trim();
  const caption = decodeEntities(
    String(json?.videoDetails?.shortDescription || ''),
  ).trim();
  if (!title && !caption) return null;
  return { title, caption };
}

function extractYtInitialPlayerResponse(html) {
  const marker = 'ytInitialPlayerResponse';
  const idx = html.indexOf(marker);
  if (idx < 0) return null;
  const eq = html.indexOf('=', idx + marker.length);
  if (eq < 0) return null;
  let i = eq + 1;
  while (i < html.length && /\s/.test(html[i])) i += 1;
  if (html[i] !== '{') return null;
  let depth = 0;
  let inString = false;
  let escape = false;
  for (let j = i; j < html.length; j += 1) {
    const ch = html[j];
    if (inString) {
      if (escape) {
        escape = false;
      } else if (ch === '\\') {
        escape = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
      continue;
    }
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) {
        try {
          return JSON.parse(html.slice(i, j + 1));
        } catch (_) {
          return null;
        }
      }
    }
  }
  return null;
}

async function youtubeDetailsFromInnertube(videoId) {
  const response = await fetch(
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'User-Agent':
          'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip',
      },
      body: JSON.stringify({
        context: {
          client: {
            clientName: 'ANDROID',
            clientVersion: '20.10.38',
            androidSdkVersion: 30,
            hl: 'de',
            gl: 'DE',
          },
        },
        videoId,
        contentCheckOk: true,
        racyCheckOk: true,
      }),
    },
  );
  if (!response.ok) return null;
  const json = await response.json();
  const status = String(json?.playabilityStatus?.status || '');
  if (status && status !== 'OK') return null;
  const title = decodeEntities(String(json?.videoDetails?.title || '')).trim();
  const caption = decodeEntities(
    String(json?.videoDetails?.shortDescription || ''),
  ).trim();
  if (!title && !caption) return null;
  return { title, caption };
}

async function youtubeOEmbedTitle(watchUrl) {
  try {
    const endpoint =
      `https://www.youtube.com/oembed?url=${encodeURIComponent(watchUrl)}`
      + '&format=json';
    const response = await fetch(endpoint, {
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) return '';
    const data = await response.json();
    return decodeEntities(String(data.title || '')).trim();
  } catch (_) {
    return '';
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
    imageUrl: (data.thumbnail_url || '').toString().trim(),
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
      imageUrl: (data.thumbnail_url || '').toString().trim(),
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
      imageUrl: decodeEntities(
        meta(html, 'og:image') || meta(html, 'og:image:url') || '',
      ).trim(),
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
