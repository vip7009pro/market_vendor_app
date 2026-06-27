'use client';

import { useEffect } from 'react';

export default function PWARegister() {
  useEffect(() => {
    // Only register Service Worker in production mode to avoid HMR caching conflict in development
    if (process.env.NODE_ENV !== 'production') {
      if (typeof window !== 'undefined' && 'serviceWorker' in navigator) {
        navigator.serviceWorker.getRegistrations().then((registrations) => {
          for (const registration of registrations) {
            registration.unregister();
            console.log('PWA ServiceWorker unregistered in development mode');
          }
        });
      }
      return;
    }

    if (typeof window !== 'undefined' && 'serviceWorker' in navigator) {
      window.addEventListener('load', () => {
        navigator.serviceWorker.register('/sw.js').then(
          (registration) => {
            console.log('PWA ServiceWorker registered with scope: ', registration.scope);
          },
          (err) => {
            console.error('PWA ServiceWorker registration failed: ', err);
          }
        );
      });
    }
  }, []);

  return null;
}
