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
    <html lang="vi" className="dark">
      <body className={`${inter.variable} font-sans antialiased`}>
        <AuthProvider>
          <PWARegister />
          {children}
        </AuthProvider>
      </body>
    </html>
  );
}
