import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  /* config options here */
  allowedDevOrigins: [
    '192.168.1.136', 
    'localhost:3001', 
    '192.168.1.136:3001', 
    'cmsvina4285.com', 
    'cmsvina4285.com:3001'
  ],
};

export default nextConfig;
