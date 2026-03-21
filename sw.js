const CACHE_NAME = "greenmind-v4";
const ASSETS = [
  "/",
  "/chat.html",
  "/style.css",
  "/app.js",
  "/manifest.json",
  "/icons/icon-192.png",
  "/icons/icon-512.png",
];

// Install: cache all static assets, force activate immediately
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS))
  );
  self.skipWaiting();
});

// Activate: delete ALL old caches
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// Fetch: network-first for own assets, ignore external requests
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);

  // Let external requests (esm.run, huggingface, etc.) pass through — browser/WebLLM handles its own caching
  if (url.hostname !== location.hostname) {
    return;
  }

  // Network-first: try fresh version, fall back to cache if offline
  event.respondWith(
    fetch(event.request)
      .then((response) => {
        const clone = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
