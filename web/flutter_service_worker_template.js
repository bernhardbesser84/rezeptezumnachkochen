'use strict';

/**
 * Build-ID wird beim Deploy in die Datei geschrieben.
 * - skipWaiting + clients.claim: neue Version übernimmt sofort
 * - Alte Caches werden gelöscht
 * - Network-only: keine stille Offline-App-Version mehr
 */
const APP_BUILD_ID = '__APP_BUILD_ID__';
const CACHE_NAME = 'rezept-pwa-' + APP_BUILD_ID;

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(Promise.resolve());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys
        .filter((key) => key !== CACHE_NAME)
        .map((key) => caches.delete(key)),
    );
    await self.clients.claim();
  })());
});

self.addEventListener('message', (event) => {
  const data = event.data;
  if (data === 'skipWaiting' || (data && data.type === 'SKIP_WAITING')) {
    self.skipWaiting();
  }
});

// Bewusst kein Caching der App-Shell — verhindert veraltete PWA-Versionen.
self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  event.respondWith(
    fetch(request, { cache: 'no-store' }).catch(async () => {
      // Optionaler Fallback nur wenn wirklich offline und etwas im Cache liegt.
      const cached = await caches.match(request);
      if (cached) return cached;
      throw new Error('offline');
    }),
  );
});
