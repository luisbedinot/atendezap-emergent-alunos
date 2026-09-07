// Emergent start wrapper.
// Loads /app/frontend/.env into process.env BEFORE starting Vite so that the
// SSR runtime and TanStack server functions can read server-only secrets
// (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, ...) from process.env.
// Only VITE_* values ever reach the browser bundle; these server keys do not.
import { readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import path from "node:path";
import { pathToFileURL } from "node:url";

const cwd = process.cwd();
try {
  const txt = readFileSync(path.resolve(cwd, ".env"), "utf8");
  for (const raw of txt.split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const eq = line.indexOf("=");
    if (eq === -1) continue;
    const key = line.slice(0, eq).trim();
    let val = line.slice(eq + 1).trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    if (key && process.env[key] === undefined) process.env[key] = val;
  }
} catch (e) {
  console.warn("[start] could not read .env:", e?.message);
}

const viteBin = path.resolve(cwd, "node_modules/vite/bin/vite.js");
const polyfill = pathToFileURL(path.resolve(cwd, "scripts/ws-polyfill.mjs")).href;
const host = process.env.HOST || "0.0.0.0";
const port = process.env.PORT || "3000";
const child = spawn(process.execPath, ["--import", polyfill, viteBin, "dev", "--host", host, "--port", port], {
  stdio: "inherit",
  env: process.env,
});
child.on("exit", (code) => process.exit(code ?? 0));
