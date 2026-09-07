import { useEffect, useRef } from "react";

// Realtime fallback for the self-hosted stack.
//
// The full Supabase Realtime SERVICE is not provisioned in the local/preview
// stack, so `supabase.channel(...).subscribe()` receives no events. This hook
// provides an authenticated, company-scoped POLLING fallback: it periodically
// re-runs the same loader the screen already uses (which filters by company_id
// and is enforced by RLS), pauses when the tab is hidden, and cleans up on
// unmount.
//
// It is a POLLING FALLBACK — NOT Realtime. When a full Supabase (with Realtime)
// is connected, set VITE_REALTIME_ENABLED=true to disable polling and rely on
// the original channel subscriptions, which are preserved in the screens.
export const realtimeServiceEnabled =
  import.meta.env.VITE_REALTIME_ENABLED === "true";

export function useRealtimePolling(
  enabled: boolean,
  onTick: () => void,
  intervalMs = 5000,
) {
  const cb = useRef(onTick);
  cb.current = onTick;

  useEffect(() => {
    // Only poll when the Realtime service is NOT available and the caller is ready.
    if (realtimeServiceEnabled || !enabled) return;

    const tick = () => {
      if (typeof document === "undefined" || document.visibilityState === "visible") {
        cb.current();
      }
    };
    const timer = setInterval(tick, intervalMs);
    const onVisible = () => {
      if (document.visibilityState === "visible") cb.current();
    };
    if (typeof document !== "undefined") {
      document.addEventListener("visibilitychange", onVisible);
    }
    return () => {
      clearInterval(timer);
      if (typeof document !== "undefined") {
        document.removeEventListener("visibilitychange", onVisible);
      }
    };
  }, [enabled, intervalMs]);
}
