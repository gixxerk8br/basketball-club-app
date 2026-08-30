// WILD CATS活動管理アプリ: プッシュ通知を受け取るためのService Worker
// このファイルはサイトのルート(index.htmlと同じ階層)に置く必要がある
// (Service Workerは自分がある場所より下の階層しか制御できないため)。

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// プッシュ通知を受信したときに、実際に通知を表示する
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { title: 'WILD CATS', body: event.data ? event.data.text() : '' }; }

  const title = data.title || 'WILD CATS活動管理アプリ';
  const options = {
    body: data.body || '',
    icon: 'assets/icon-512.png',
    badge: 'assets/icon-512.png',
    data: { url: data.url || './' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

// 通知をタップしたときに、アプリを開く(すでに開いていればそのタブに切り替える)
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = (event.notification.data && event.notification.data.url) || './';
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) return client.focus();
      }
      if (self.clients.openWindow) return self.clients.openWindow(url);
    })
  );
});
