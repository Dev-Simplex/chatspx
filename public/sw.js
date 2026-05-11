/* eslint-disable no-restricted-globals, no-console */
/* globals clients, caches */

// ============================================================================
// Cache purger — força limpeza de SW antigos que possam ter instalado fetch
// handler + cache no browser do usuário. skipWaiting + clients.claim garante
// que qualquer tab aberta passe para este SW sem precisar recarregar.
// ============================================================================
self.addEventListener('install', event => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', event => {
  event.waitUntil(
    (async () => {
      if (typeof caches !== 'undefined' && caches.keys) {
        const names = await caches.keys();
        await Promise.all(names.map(n => caches.delete(n)));
      }
      await self.clients.claim();
    })()
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
