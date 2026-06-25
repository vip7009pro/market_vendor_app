import { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'Market Vendor App',
    short_name: 'MarketVendor',
    description: 'Hệ thống quản lý bán hàng và công nợ dành cho tiểu thương',
    start_url: '/',
    display: 'standalone',
    background_color: '#090d16',
    theme_color: '#6366f1',
    icons: [
      {
        src: '/globe.svg',
        sizes: '192x192',
        type: 'image/svg+xml',
      },
      {
        src: '/globe.svg',
        sizes: '512x512',
        type: 'image/svg+xml',
      },
    ],
  };
}
