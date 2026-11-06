import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Auth input and token-bearing URLs must never enter development request logs.
  logging: false,
  async headers() {
    return ["/login", "/account/:path*", "/auth/:path*"].map((source) => ({
      source,
      headers: [
        { key: "Cache-Control", value: "private, no-store, max-age=0, must-revalidate" },
        { key: "Expires", value: "0" },
        { key: "Pragma", value: "no-cache" },
        { key: "Referrer-Policy", value: source === "/auth/:path*" ? "strict-origin" : "no-referrer" },
      ],
    }));
  },
  turbopack: {
    rules: {
      "*.css": {
        loaders: ["@tailwindcss/turbopack"],
        as: "*.css",
      },
    },
  },
};

export default nextConfig;
