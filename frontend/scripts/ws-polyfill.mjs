// Server-only polyfill preloaded via `node --import`.
// @supabase/supabase-js (realtime-js) references a global WebSocket at client
// construction time. Node 20 (Emergent base image) has no global WebSocket, so
// we install the `ws` implementation. Preloading here keeps it entirely out of
// the client bundle and guarantees it runs before any SSR/server-function code.
import WebSocket from "ws";
if (typeof globalThis.WebSocket === "undefined") {
  globalThis.WebSocket = WebSocket;
}
