/* eslint-disable no-restricted-globals, no-console */
/* globals clients */

// ============================================================================
// Cache only the offline page and immutable Vite assets, never dashboard HTML,
// version.json or API responses. Purge legacy caches during activation.
// Bump OFFLINE_CACHE when offline.html changes and ASSET_CACHE when its policy changes.
// ============================================================================
const OFFLINE_CACHE = 'app-offline-v1';
const OFFLINE_URL = '/offline.html';
const ASSET_CACHE = 'app-assets-v1';
const MAX_ASSET_ENTRIES = 200;
const HASHED_ASSET_PATH =
  /^\/vite\/assets\/[^/]+-[\w-]{8}\.(?:js|css|woff2?|ttf|otf|png|jpe?g|webp|avif|svg|ico|gif)$/;

const fetchAsset = async event => {
  const cache = await caches.open(ASSET_CACHE);
  const cached = await cache.match(event.request);
  if (cached) return cached;

  const response = await fetch(event.request);
  if (
    response.ok &&
    response.type === 'basic' &&
    !response.redirected &&
    !response.headers.get('content-type')?.includes('text/html')
  ) {
    event.waitUntil(
      cache
        .put(event.request, response.clone())
        .then(async () => {
          const keys = await cache.keys();
          const overflow = keys.length - MAX_ASSET_ENTRIES;
          if (overflow > 0) {
            await Promise.all(
              keys.slice(0, overflow).map(key => cache.delete(key))
            );
          }
        })
        // Cache quota/storage failures must not prevent loading a fetched asset.
        .catch(() => {})
    );
  }
  return response;
};

self.addEventListener('install', event => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(OFFLINE_CACHE);
      await cache.add(new Request(OFFLINE_URL, { cache: 'reload' }));
      await self.skipWaiting();
    })()
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    (async () => {
      if (typeof caches !== 'undefined' && caches.keys) {
        const names = await caches.keys();
        await Promise.all(
          names
            .filter(n => n !== OFFLINE_CACHE && n !== ASSET_CACHE)
            .map(n => caches.delete(n))
        );
      }
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', event => {
  if (event.request.method !== 'GET') return;
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  if (event.request.mode === 'navigate') {
    event.respondWith(
      fetch(event.request).catch(async () => {
        const cache = await caches.open(OFFLINE_CACHE);
        return cache.match(OFFLINE_URL);
      })
    );
  } else if (HASHED_ASSET_PATH.test(url.pathname)) {
    event.respondWith(fetchAsset(event));
  }
});

self.addEventListener('push', event => {
  let notification = event.data && event.data.json();

  event.waitUntil(
    self.registration.showNotification(notification.title, {
      tag: notification.tag,
      data: {
        url: notification.url,
      },
    })
  );
});

self.addEventListener('notificationclick', event => {
  let notification = event.notification;

  event.waitUntil(
    clients.matchAll({ type: 'window' }).then(windowClients => {
      let matchingWindowClients = windowClients.filter(
        client => client.url === notification.data.url
      );

      if (matchingWindowClients.length) {
        let firstWindow = matchingWindowClients[0];
        if (firstWindow && 'focus' in firstWindow) {
          firstWindow.focus();
          return;
        }
      }
      if (clients.openWindow) {
        clients.openWindow(notification.data.url);
      }
    })
  );
});
