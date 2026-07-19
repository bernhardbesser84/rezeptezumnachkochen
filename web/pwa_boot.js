/**
 * Frühe PWA-Hilfe für die Home-Bildschirm-App auf dem iPhone.
 * - Alte Caches aufräumen (Flutter hatte früher aggressive Offline-Caches)
 * - Service-Worker auf Updates prüfen
 * - klarer Neustart: clearAndReload()
 */
(function () {
  'use strict';

  async function clearAllCaches() {
    if (!('caches' in window)) return;
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
  }

  async function unregisterServiceWorkers() {
    if (!('serviceWorker' in navigator)) return;
    const regs = await navigator.serviceWorker.getRegistrations();
    await Promise.all(regs.map((reg) => reg.unregister()));
  }

  async function checkServiceWorkerUpdate() {
    if (!('serviceWorker' in navigator)) return;
    try {
      const reg = await navigator.serviceWorker.getRegistration();
      if (!reg) return;
      await reg.update();
      if (reg.waiting) {
        reg.waiting.postMessage({ type: 'SKIP_WAITING' });
      }
    } catch (_) {
      // Ignorieren — Update-Check ist best-effort.
    }
  }

  async function clearAndReload() {
    try {
      await clearAllCaches();
      await unregisterServiceWorkers();
    } catch (_) {
      // Trotzdem neu laden.
    }
    const url = new URL(window.location.href);
    url.searchParams.set('_app_refresh', String(Date.now()));
    window.location.replace(url.toString());
  }

  // Beim Start: alte Flutter-/Workbox-Caches weg, SW-Update anstoßen.
  (async function boot() {
    try {
      if ('caches' in window) {
        const keys = await caches.keys();
        await Promise.all(
          keys
            .filter((key) => /flutter|workbox|rezept/i.test(key))
            .map((key) => caches.delete(key)),
        );
      }
      await checkServiceWorkerUpdate();
    } catch (_) {
      // still start Flutter
    }
  })();

  window.RezeptPwa = {
    clearAndReload: clearAndReload,
    checkServiceWorkerUpdate: checkServiceWorkerUpdate,
    clearAllCaches: clearAllCaches,
  };
})();
