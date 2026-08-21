/**
 * Facebook-Share-Links (/share/r/…) zeigen oft auf story.php (Login-Wand).
 * Die echte öffentliche Reel-URL finden wir über das Embed-Plugin.
 */

const UA_IPHONE =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) '
  + 'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 '
  + 'Mobile/15E148 Safari/604.1';
const UA_FACEBOOK =
  'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';

async function expandFacebookCandidateUrls(pageUrl, fetchImpl = fetch) {
  const urls = [];
  const add = (raw) => {
    const url = normalizeFacebookUrl(raw);
    if (!url || urls.includes(url)) return;
    urls.push(url);
  };

  add(pageUrl);
  try {
    const uri = new URL(pageUrl);
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (host.endsWith('facebook.com') || host === 'fb.watch' || host === 'fb.com') {
      const mobile = new URL(pageUrl);
      mobile.hostname = 'm.facebook.com';
      add(mobile.toString());
    }
  } catch (_) {
    // ignore
  }

  for (const start of [...urls]) {
    const chain = await followFacebookRedirects(start, UA_FACEBOOK, fetchImpl);
    for (const hop of chain) add(hop);
  }

  // story.php / share → echte Reel-URL über Plugin
  for (const candidate of [...urls]) {
    if (!needsFacebookPluginResolve(candidate)) continue;
    try {
      const reel = await resolveReelViaPlugin(candidate, fetchImpl);
      if (reel) add(reel);
    } catch (_) {
      // Nächsten Kandidaten versuchen.
    }
  }

  // story_fbid aus Query zusätzlich als Reel-Kandidat (manchmal identisch)
  for (const candidate of [...urls]) {
    try {
      const uri = new URL(candidate);
      const storyId =
        uri.searchParams.get('story_fbid')
        || uri.searchParams.get('v')
        || '';
      if (/^\d{10,}$/.test(storyId)) {
        add(`https://www.facebook.com/reel/${storyId}/`);
      }
    } catch (_) {
      // ignore
    }
  }

  return urls;
}

function needsFacebookPluginResolve(url) {
  return /\/share\/r\//i.test(url)
    || /story\.php/i.test(url)
    || /\/posts\//i.test(url)
    || /\/permalink\.php/i.test(url);
}

async function followFacebookRedirects(startUrl, userAgent, fetchImpl) {
  const hops = [];
  let current = startUrl;
  for (let i = 0; i < 6; i++) {
    if (!current || hops.includes(current)) break;
    hops.push(current);
    let response;
    try {
      response = await fetchImpl(current, {
        method: 'GET',
        redirect: 'manual',
        headers: {
          'User-Agent': userAgent,
          'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
          Accept: 'text/html,application/xhtml+xml',
        },
      });
    } catch (_) {
      break;
    }

    const status = response.status;
    if (status >= 300 && status < 400) {
      const loc = response.headers.get('location');
      if (!loc) break;
      const next = absoluteUrl(loc, current);
      if (!next || /\/login/i.test(next)) break;
      current = next;
      continue;
    }
    break;
  }
  return hops;
}

async function resolveReelViaPlugin(pageUrl, fetchImpl) {
  const targets = [
    'https://www.facebook.com/plugins/post.php?href='
      + encodeURIComponent(stripTrackingParams(pageUrl))
      + '&show_text=true&width=500',
    'https://www.facebook.com/plugins/video.php?href='
      + encodeURIComponent(stripTrackingParams(pageUrl))
      + '&show_text=true&width=500',
  ];

  for (const pluginUrl of targets) {
    let current = pluginUrl;
    for (let i = 0; i < 6; i++) {
      let response;
      try {
        response = await fetchImpl(current, {
          method: 'GET',
          redirect: 'manual',
          headers: {
            'User-Agent': UA_IPHONE,
            'Accept-Language': 'de-DE,de;q=0.9,en;q=0.8',
            Accept: 'text/html,application/xhtml+xml',
          },
        });
      } catch (_) {
        break;
      }

      const status = response.status;
      if (status >= 300 && status < 400) {
        const loc = response.headers.get('location');
        if (!loc) break;
        const next = absoluteUrl(loc, current);
        if (!next || /\/login/i.test(next)) break;
        const fromLoc = extractReelUrl(next) || extractReelFromPluginHref(next);
        if (fromLoc) return fromLoc;
        current = next;
        continue;
      }

      if (status >= 200 && status < 300) {
        const html = await response.text();
        const fromHtml = extractReelUrl(html) || extractReelFromPluginHref(html);
        if (fromHtml) return fromHtml;
      }
      break;
    }
  }
  return '';
}

function extractReelFromPluginHref(raw) {
  const text = String(raw || '');
  const encoded = text.match(/facebook\.com%2Freel%2F(\d+)/i);
  if (encoded) {
    return `https://www.facebook.com/reel/${encoded[1]}/`;
  }
  try {
    const uri = new URL(text);
    const href = uri.searchParams.get('href');
    if (href) return extractReelUrl(href);
  } catch (_) {
    // ignore
  }
  const hrefMatch = text.match(/[?&]href=([^&"']+)/i);
  if (hrefMatch) {
    try {
      return extractReelUrl(decodeURIComponent(hrefMatch[1]));
    } catch (_) {
      // ignore
    }
  }
  return '';
}

function extractReelUrl(raw) {
  const text = decodeEntities(String(raw || ''));
  const match = text.match(/facebook\.com\/reel\/(\d+)/i);
  if (match) return `https://www.facebook.com/reel/${match[1]}/`;
  return '';
}

function normalizeFacebookUrl(raw) {
  const text = String(raw || '').trim();
  if (!/^https?:\/\//i.test(text)) return '';
  try {
    const uri = new URL(text);
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (
      !host.endsWith('facebook.com')
      && host !== 'fb.watch'
      && host !== 'fb.com'
      && host !== 'm.facebook.com'
    ) {
      return text;
    }
    return uri.toString();
  } catch (_) {
    return '';
  }
}

function stripTrackingParams(url) {
  try {
    const uri = new URL(url);
    for (const key of [...uri.searchParams.keys()]) {
      if (/^mibextid$|^rdid$|^share_url$|^refsrc$|^_rdr$/i.test(key)) {
        uri.searchParams.delete(key);
      }
    }
    return uri.toString();
  } catch (_) {
    return url;
  }
}

function absoluteUrl(loc, base) {
  try {
    return new URL(loc, base).toString();
  } catch (_) {
    return '';
  }
}

function decodeEntities(text) {
  return String(text || '')
    .replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"')
    .replace(/&#(\d+);/g, (_, n) => String.fromCharCode(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCharCode(parseInt(h, 16)));
}

module.exports = {
  expandFacebookCandidateUrls,
  extractReelUrl,
  resolveReelViaPlugin,
  followFacebookRedirects,
};
