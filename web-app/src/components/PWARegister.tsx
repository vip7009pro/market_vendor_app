'use client';

import { useEffect } from 'react';

export default function PWARegister() {
  useEffect(() => {
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
