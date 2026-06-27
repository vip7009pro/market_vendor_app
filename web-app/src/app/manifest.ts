import { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Bán hàng',
    short_name: 'Bán hàng',
    description: 'Hệ thống quản lý bán hàng và công nợ dành cho tiểu thương',
    start_url: '/',
    display: 'standalone',
    background_color: '#090d16',
    theme_color: '#6366f1',
    icons: [
      {
        src: '/icon.svg',
        sizes: '192x192',
        type: 'image/svg+xml',
      },
      {
        src: '/icon.svg',
        sizes: '512x512',
        type: 'image/svg+xml',
      },
    ],
  };
}
