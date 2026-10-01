/* Texas Burger — service worker: notificações no celular + abertura rápida/offline da página.
   Precisa ficar na MESMA pasta do HTML, em endereço https.
   Página: tenta a rede (sempre pega a versão nova) e, se a rede demorar mais de 4s ou cair,
   abre a última cópia guardada. Nada do Apps Script/planilha é guardado aqui. */
const CACHE = 'texas-shell-v2';
self.addEventListener('install', e => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil((async () => {
  for (const k of await caches.keys()) { if (k !== CACHE && k.indexOf('texas-shell') === 0) await caches.delete(k); }
  await self.clients.claim();
})()));
self.addEventListener('fetch', e => {
  const r = e.request;
  if (r.method !== 'GET' || r.mode !== 'navigate') return;
  if (new URL(r.url).origin !== self.location.origin) return;
  e.respondWith((async () => {
    const c = await caches.open(CACHE);
    const rede = fetch(r).then(res => { if (res && res.ok) c.put('./', res.clone()); return res; });
    try {
      return await Promise.race([rede, new Promise((_, rej) => setTimeout(() => rej(new Error('lento')), 4000))]);
    } catch (err) {
      const copia = await c.match('./');
      return copia || rede;
    }
  })());
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const c of list) { if ('focus' in c) return c.focus(); }
    if (self.clients.openWindow) return self.clients.openWindow('./');
  }));
});
