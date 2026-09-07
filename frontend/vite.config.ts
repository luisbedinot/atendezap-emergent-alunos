// Explicit TanStack Start + Vite config (Node 22 compatible).
//
// Replaces the @lovable.dev/vite-tanstack-config wrapper (and lovable-tagger),
// which broke under Node 22.13's require(ESM) semantics. This mirrors the
// official TanStack Start hosting guide:
//   https://tanstack.com/start/latest/docs/framework/react/guide/hosting
// Plugins preserved: tanstackStart (SSR + server functions + router codegen),
// nitro (Node server target), viteReact, tailwindcss, tsconfig path aliases,
// and the custom SSR server entry (src/server.ts). VITE_* env injection is a
// Vite default; the @ alias comes from tsconfig paths.
import { defineConfig, loadEnv } from "vite";
import tsConfigPaths from "vite-tsconfig-paths";
import tailwindcss from "@tailwindcss/vite";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import { nitro } from "nitro/vite";
import viteReact from "@vitejs/plugin-react";

// Mirror NON-VITE server-only secrets from .env into process.env for the SSR
// runtime / server functions. These are never shipped to the client bundle
// (only VITE_* are injected into the browser).
const serverEnv = loadEnv(process.env.NODE_ENV || "development", process.cwd(), "");
for (const key of [
  "SUPABASE_URL",
  "SUPABASE_PUBLISHABLE_KEY",
  "SUPABASE_SERVICE_ROLE_KEY",
  "SUPABASE_JWT_SECRET",
  "AI_PROXY_SECRET",
  "EVOLUTION_API_URL",
  "EVOLUTION_API_KEY",
  "EMERGENT_LLM_KEY",
]) {
  if (serverEnv[key] && !process.env[key]) process.env[key] = serverEnv[key];
}

export default defineConfig({
  server: {
    host: "0.0.0.0",
    port: Number(process.env.PORT) || 3000,
    strictPort: false,
    // Emergent ingress forwards an internal cluster hostname as the Host header.
    allowedHosts: true,
  },
  plugins: [
    tsConfigPaths(),
    tailwindcss(),
    tanstackStart({
      // Preserve the custom SSR error-wrapper entry.
      server: { entry: "server.ts" },
    }),
    nitro(),
    viteReact(),
  ],
});
