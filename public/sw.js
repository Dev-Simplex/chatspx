/* eslint-disable no-restricted-globals, no-console */
/* globals clients */

// ============================================================================
// Only the standalone offline page is cached. Keep purging legacy app caches:
// caching dashboard HTML or API responses can leave users on a stale version.
// Bump this cache version whenever offline.html changes.
// ============================================================================
const OFFLINE_CACHE = 'app-offline-v1';
const OFFLINE_URL = '/offline.html';

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
          names.filter(n => n !== OFFLINE_CACHE).map(n => caches.delete(n))
        );
      }
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', event => {
  if (event.request.mode !== 'navigate' || event.request.method !== 'GET')
    return;

  event.respondWith(
    fetch(event.request).catch(async () => {
      const cache = await caches.open(OFFLINE_CACHE);
      return cache.match(OFFLINE_URL);
    })
  );
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
