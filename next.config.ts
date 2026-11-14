import type { NextConfig } from "next";

// Standard static export. No ChatGPT runtime is required to serve this build.
const config: NextConfig = {
  output: "export",
  trailingSlash: true,
  images: { unoptimized: true },
};

export default config;
