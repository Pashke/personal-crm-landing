// @ts-check
import { defineConfig, fontProviders } from "astro/config";
import tailwindcss from "@tailwindcss/vite";

// Fonts are downloaded from Google Fonts at build time and served with the site.
const google = fontProviders.google();
const fontDefaults = { provider: google, styles: ["normal"], subsets: ["cyrillic", "latin"] };

export default defineConfig({
  fonts: [
    { ...fontDefaults, name: "Oswald", cssVariable: "--font-oswald", weights: [500, 700], fallbacks: ["sans-serif"] },
    { ...fontDefaults, name: "PT Serif", cssVariable: "--font-pt-serif", weights: [400, 700], fallbacks: ["serif"] },
    { ...fontDefaults, name: "Caveat", cssVariable: "--font-caveat", weights: [500], fallbacks: ["cursive"] },
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
