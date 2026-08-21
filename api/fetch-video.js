/**
 * Vercel Serverless: Video-Datei zu einem Social-Link laden
 * (Facebook-Reel / YouTube Short).
 *
 * Aufruf: GET /api/fetch-video?url=https://...
 * Erfolg: video/mp4 (oder audio/mp4) Bytes
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
  } catch (_) {
    res.status(200).json({
      error:
        'Video konnte nicht vom Link geladen werden. '
        + 'Bitte die Datei manuell speichern und unter „Video wählen“ anhängen.',
    });
  }
};

const MAX_BYTES = 4_400_000; // unter Vercel-Limit (~4,5 MB Antwort)
const UA_IPHONE =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
  + 'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
  + 'Mobile/15E148 Safari/604.1';
const UA_FACEBOOK =
  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';
const UA_GOOGLEBOT =
  'Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)';
const UA_ANDROID_YT =
  'com.google.android.youtube/20.10.38 (Linux; U; Android 14) gzip';

async function fetchVideo(pageUrl) {
  const host = safeHost(pageUrl);

  if (host.includes('youtube.com') || host === 'youtu.be') {
    return fetchYoutubeVideo(pageUrl);
  }

  const isFacebook =
    host.includes('facebook.com') || host === 'fb.watch' || host === 'fb.com';

  if (isFacebook) {
    return fetchFacebookVideo(pageUrl);
  }

  const fromOg = await videoFromOgTags(pageUrl, UA_IPHONE);
  if (fromOg.ok) return fromOg;
  return {
    ok: false,
    error:
      'Automatischer Video-Download für diese Plattform klappt oft nicht. '
      + 'Bitte Video speichern und manuell anhängen.',
  };
}

function safeHost(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, '').toLowerCase();
  } catch (_) {
    return '';
  }
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

async function fetchYoutubeVideo(pageUrl) {
  const videoId = youtubeVideoId(pageUrl);
  if (!videoId) {
    return {
      ok: false,
      error: 'Das sieht nicht nach einem YouTube-Link aus.',
    };
  }

  try {
    const response = await fetch(
      'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': UA_ANDROID_YT,
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
    if (!response.ok) {
      return {
        ok: false,
        error:
          'YouTube hat das Video nicht freigegeben. '
          + 'Bitte speichern und unter „Video wählen“ anhängen.',
        warning: 'youtube-http',
      };
    }

    const json = await response.json();
    const status = String(json?.playabilityStatus?.status || '');
    if (status && status !== 'OK') {
      return {
        ok: false,
        error:
          'YouTube blockiert den automatischen Video-Download. '
          + 'Bitte in der YouTube-App speichern/teilen und hier '
          + 'unter „Video wählen“ anhängen. '
          + 'Beschreibung und Untertitel können trotzdem helfen.',
        warning: 'youtube-blocked',
      };
    }

    const streamUrl = pickYoutubeStreamUrl(json);
    if (!streamUrl) {
      return {
        ok: false,
        error:
          'Kein passendes YouTube-Video unter der Größengrenze gefunden. '
          + 'Bitte kürzeres Video wählen oder Datei manuell anhängen.',
        warning: 'youtube-too-large',
      };
    }

    return downloadVideo(
      streamUrl.url,
      streamUrl.fileName,
      streamUrl.source,
      streamUrl.mimeType,
    );
  } catch (_) {
    return {
      ok: false,
      error:
        'YouTube-Video konnte nicht geladen werden. '
        + 'Bitte Datei manuell anhängen.',
      warning: 'youtube-error',
    };
  }
}

/** Wählt eine Datei unter MAX_BYTES: zuerst gemuxtes MP4, dann Audio. */
function pickYoutubeStreamUrl(playerJson) {
  const progressive = Array.isArray(playerJson?.streamingData?.formats)
    ? playerJson.streamingData.formats
    : [];
  const adaptive = Array.isArray(playerJson?.streamingData?.adaptiveFormats)
    ? playerJson.streamingData.adaptiveFormats
    : [];

  const progressiveMp4 = progressive
    .filter((f) => f && f.url && String(f.mimeType || '').includes('video/mp4'))
    .map((f) => ({
      url: String(f.url),
      size: Number(f.contentLength) || 0,
      mimeType: 'video/mp4',
      fileName: 'youtube-video.mp4',
      source: `youtube-itag-${f.itag || 'progressive'}`,
    }));

  const audioMp4 = adaptive
    .filter((f) => f && f.url && String(f.mimeType || '').startsWith('audio/mp4'))
    .map((f) => ({
      url: String(f.url),
      size: Number(f.contentLength) || 0,
      mimeType: 'audio/mp4',
      fileName: 'youtube-audio.m4a',
      source: `youtube-audio-${f.itag || 'm4a'}`,
    }));

  const pool = [...progressiveMp4, ...audioMp4]
    .filter((f) => f.size <= 0 || f.size <= MAX_BYTES)
    .sort((a, b) => {
      // Video vor Audio, dann kleinere Datei zuerst.
      const av = a.mimeType.startsWith('video') ? 0 : 1;
      const bv = b.mimeType.startsWith('video') ? 0 : 1;
      if (av !== bv) return av - bv;
      const as = a.size || Number.MAX_SAFE_INTEGER;
      const bs = b.size || Number.MAX_SAFE_INTEGER;
      return as - bs;
    });

  return pool[0] || null;
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
  return {
    html: await response.text(),
    finalUrl: response.url || url,
  };
}

const {
  expandFacebookCandidateUrls,
} = require('./facebook_resolve');

/**
 * Facebook-Share-Links (/share/r/…) liefern oft nur die Caption.
 * Die MP4-URL steckt in og:video beim iPhone-UA — oder erst auf der Reel-URL.
 * Zu große Dateien werden abgeschnitten, nicht verworfen (Facebook ignoriert Range).
 */
async function fetchFacebookVideo(pageUrl) {
  const agents = [UA_IPHONE, UA_GOOGLEBOT, UA_FACEBOOK];
  const queue = await expandFacebookCandidateUrls(pageUrl);
  const triedPages = new Set();
  let sawMediaUrl = false;

  while (queue.length > 0) {
    const url = queue.shift();
    if (!url || triedPages.has(url)) continue;
    triedPages.add(url);

    for (const agent of agents) {
      try {
        const { html, finalUrl } = await fetchHtml(url, agent);
        if (html.includes('Error Facebook') && !html.includes('og:video')) {
          continue;
        }

        const canonical = facebookCanonicalUrl(html, finalUrl, url);
        if (canonical && !triedPages.has(canonical)) {
          queue.push(canonical);
        }

        const candidates = collectFacebookVideoUrls(html);
        if (candidates.length > 0) sawMediaUrl = true;
        for (const videoUrl of candidates) {
          const result = await downloadVideo(
            videoUrl,
            'facebook-reel.mp4',
            'facebook-mp4',
          );
          if (result.ok) return result;
        }
      } catch (_) {
        // Nächsten UA / Link versuchen.
      }
    }
  }

  return {
    ok: false,
    error: sawMediaUrl
      ? 'Das Facebook-Video war nicht vollständig ladbar. '
        + 'Tipp: Im Browser auf Teilen → „Video speichern“, '
        + 'dann hier „Video wählen“.'
      : 'Facebook hat kein ladbares Video geliefert. '
        + 'Tipp: Im Browser auf Teilen → „Video speichern“ / Download, '
        + 'dann hier „Video wählen“.',
    warning: 'facebook-no-mp4',
  };
}

function facebookUrlVariants(pageUrl) {
  const urls = [pageUrl];
  try {
    const uri = new URL(pageUrl);
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (host.endsWith('facebook.com') || host === 'fb.watch' || host === 'fb.com') {
      const mobile = new URL(pageUrl);
      mobile.hostname = 'm.facebook.com';
      urls.push(mobile.toString());
    }
  } catch (_) {
    // ignore
  }
  return uniqueStrings(urls);
}

function facebookCanonicalUrl(html, finalUrl, fallback) {
  const og = cleanMediaUrl(meta(html, 'og:url') || '');
  if (/facebook\.com\/(reel|reels|watch|video|videos|share)\//i.test(og)) {
    return og;
  }
  const reel = String(html || '').match(/facebook\.com\/reel\/(\d+)/i);
  if (reel) {
    return `https://www.facebook.com/reel/${reel[1]}/`;
  }
  if (finalUrl && /facebook\.com\/reel\//i.test(finalUrl) && finalUrl !== fallback) {
    return finalUrl;
  }
  return '';
}

function collectFacebookVideoUrls(html) {
  const urls = [];
  const add = (raw) => {
    const url = cleanMediaUrl(raw);
    if (!isPlayableVideoUrl(url) || urls.includes(url)) return;
    urls.push(url);
  };

  add(meta(html, 'og:video:secure_url'));
  add(meta(html, 'og:video:url'));
  add(meta(html, 'og:video'));
  for (const mp4 of extractAllMp4Urls(html)) add(mp4);

  const jsonKeys = [
    'playable_url',
    'playable_url_quality_hd',
    'browser_native_sd_url',
    'browser_native_hd_url',
    'sd_src',
    'hd_src',
  ];
  for (const key of jsonKeys) {
    const re = new RegExp(`"${key}"\\s*:\\s*"(https?:[^"]+)"`, 'gi');
    let match = re.exec(html);
    while (match) {
      add(match[1]);
      match = re.exec(html);
    }
  }

  urls.sort((a, b) => facebookVideoScore(a) - facebookVideoScore(b));
  return urls;
}

function facebookVideoScore(url) {
  const lower = url.toLowerCase();
  let score = 0;
  if (lower.includes('fbcdn.net')) score -= 20;
  if (/\.mp4(\?|$)/i.test(url)) score -= 10;
  if (/360|sd|m367|basic-gen2_360/.test(lower)) score -= 8;
  if (/1080|720|hd_src|quality_hd/.test(lower)) score += 12;
  return score;
}

function isPlayableVideoUrl(url) {
  if (!/^https?:\/\//i.test(url)) return false;
  const host = safeHost(url);
  if (host.includes('fbcdn.net') || host.includes('cdninstagram.com')) return true;
  if (host.includes('facebook.com') && !/\.mp4(\?|$)/i.test(url)) return false;
  return /\.mp4(\?|$)/i.test(url);
}

async function videoFromOgTags(pageUrl, userAgent) {
  const { html } = await fetchHtml(pageUrl, userAgent);
  const candidates = [
    meta(html, 'og:video:secure_url'),
    meta(html, 'og:video:url'),
    meta(html, 'og:video'),
    extractMp4Url(html),
  ]
    .map((u) => cleanMediaUrl(u || ''))
    .filter((u) => isPlayableVideoUrl(u));

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

function extractAllMp4Urls(html) {
  const matches = String(html || '').match(
    /https?:\\?\/\\?\/[^"'<>\s]+?\.mp4[^"'<>\s]*/gi,
  );
  if (!matches) return [];
  return uniqueStrings(matches.map((raw) => cleanMediaUrl(raw)).filter(Boolean));
}

function extractMp4Url(html) {
  const urls = extractAllMp4Urls(html);
  let best = '';
  for (const url of urls) {
    if (url.length > best.length) best = url;
  }
  return best;
}

function cleanMediaUrl(raw) {
  let url = decodeEntities(String(raw || '')).trim();
  url = url.replace(/\\\//g, '/');
  url = url.replace(/\\u0025/gi, '%');
  url = url.replace(/\\u0026/gi, '&');
  url = url.replace(/\\u002f/gi, '/');
  try {
    url = JSON.parse(`"${url.replace(/"/g, '\\"')}"`);
  } catch (_) {
    // schon plain
  }
  return url.replace(/&amp;/g, '&').replace(/\\+$/g, '');
}

async function downloadVideo(videoUrl, fileName, source, mimeType = 'video/mp4') {
  const response = await fetch(videoUrl, {
    headers: {
      'User-Agent': UA_IPHONE,
      Accept: 'video/mp4,audio/mp4,video/*,audio/*,*/*',
      Range: `bytes=0-${MAX_BYTES - 1}`,
      Referer: 'https://www.facebook.com/',
    },
    redirect: 'follow',
  });

  if (!(response.ok || response.status === 206)) {
    return { ok: false };
  }

  // Facebook ignoriert Range oft und sendet die ganze Datei.
  // Lieber den Anfang behalten (für gesprochene Schritte), als komplett scheitern.
  const buf = await readLimited(response, MAX_BYTES);
  if (buf.length < 1000) return { ok: false };

  const head = buf.slice(0, 64).toString('utf8');
  if (head.includes('<html') || head.includes('<!DOCTYPE')) {
    return { ok: false };
  }

  return {
    ok: true,
    bytes: buf,
    mimeType,
    fileName,
    source,
  };
}

async function readLimited(response, maxBytes) {
  const body = response.body;
  if (!body || typeof body.getReader !== 'function') {
    const buf = Buffer.from(await response.arrayBuffer());
    return buf.length > maxBytes ? buf.subarray(0, maxBytes) : buf;
  }

  const reader = body.getReader();
  const chunks = [];
  let received = 0;
  try {
    while (received < maxBytes) {
      const { done, value } = await reader.read();
      if (done || !value) break;
      const take = Math.min(value.length, maxBytes - received);
      chunks.push(
        take === value.length
          ? Buffer.from(value)
          : Buffer.from(value.subarray(0, take)),
      );
      received += take;
      if (take < value.length) break;
    }
  } finally {
    try {
      await reader.cancel();
    } catch (_) {
      // ignore
    }
  }
  return Buffer.concat(chunks, received);
}

function uniqueStrings(values) {
  const result = [];
  for (const value of values) {
    if (value && !result.includes(value)) result.push(value);
  }
  return result;
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
