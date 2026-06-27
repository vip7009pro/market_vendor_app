import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { AuthProvider } from "@/lib/auth";

const inter = Inter({
  subsets: ["latin", "vietnamese"],
  variable: "--font-inter",
});

export const metadata: Metadata = {
  title: "Market Vendor — Quản Lý Bán Hàng Thông Minh",
  description: "Hệ thống quản lý bán hàng, tồn kho, công nợ toàn diện cho tiểu thương. Miễn phí, dễ sử dụng, đa nền tảng.",
  keywords: ["quản lý bán hàng", "POS", "tiểu thương", "tồn kho", "công nợ", "market vendor"],
};

import PWARegister from "@/components/PWARegister";

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="vi" className="theme-midnight dark" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: `
              (function() {
                try {
                  const theme = localStorage.getItem('app_theme') || 'midnight';
                  const isLight = ['light', 'spring', 'sky', 'mist'].indexOf(theme) !== -1;
                  document.documentElement.className = 'theme-' + theme + ' ' + (isLight ? 'light' : 'dark');
                } catch (e) {}
              })()
            `,
          }}
        />
      </head>
      <body className={`${inter.variable} font-sans antialiased`}>
        <AuthProvider>
          <PWARegister />
          {children}
        </AuthProvider>
      </body>
    </html>
  );
}
