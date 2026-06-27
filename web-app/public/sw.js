const CACHE_NAME = 'market-vendor-cache-v1';
const urlsToCache = [
  '/',
  '/login',
  '/dashboard',
  '/pos',
  '/products',
  '/customers',
  '/debts',
  '/expenses',
  '/reports',
  '/settings',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(urlsToCache).catch((err) => console.log('SW Cache addAll error:', err));
    })
  );
});

self.addEventListener('fetch', (event) => {
  // Only cache HTTP/HTTPS GET requests
  if (event.request.method !== 'GET' || !event.request.url.startsWith('http')) {
    return;
  }
  
  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) {
        return cachedResponse;
      }
      
      return fetch(event.request).then((response) => {
        // Don't cache non-success or third-party requests
        if (!response || response.status !== 200 || response.type !== 'basic') {
          return response;
        }
        
        const responseToCache = response.clone();
        caches.open(CACHE_NAME).then((cache) => {
          cache.put(event.request, responseToCache);
        });
        
        return response;
      }).catch(() => {
        // Fallback for document navigation if offline
        if (event.request.mode === 'navigate') {
          return caches.match('/pos'); // default to POS page if offline
        }
      });
    })
  );
});
