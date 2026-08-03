// Offline support for Trace.
//
// Network-first, falling back to cache. Cache-first would be marginally faster
// to start, but an installed home-screen app would then keep serving the
// version it first saw — you could push a fix and never see it on the iPad. So:
// take the fresh copy when there's wifi, fall back to the cached one when there
// isn't. The cache is refreshed on every successful fetch.

const CACHE = 'trace-v2';
const ASSETS = [
  './',
  './index.html',
  './styles.css',
  './manifest.webmanifest',
  './icons/icon.svg',
  './src/main.js',
  './src/board.js',
  './src/geometry.js',
  './src/shapes.js',
  './src/difficulty.js',
  './src/celebrate.js',
  './src/audio.js',
  './src/lines.js',
  './src/rng.js',
];

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  if (new URL(e.request.url).origin !== self.location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        // Only cache real successes — an error page cached as the app would
        // survive long after the outage that produced it.
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(e.request, copy));
        }
        return res;
      })
      .catch(() => caches.match(e.request).then((hit) => hit || caches.match('./index.html'))),
  );
});
