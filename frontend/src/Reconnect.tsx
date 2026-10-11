import { useMutation } from "@tanstack/react-query";
import { z } from "zod";

async function startReconnect(): Promise<void> {
  const response = await fetch("/api/auth/reconnect", {
    method: "POST",
    credentials: "same-origin",
  });
  if (!response.ok) throw new Error("reconnect_unavailable");
  const result = z.object({ url: z.string().url() }).parse(await response.json());
  window.location.assign(result.url);
}

const reconnectErrors: Record<string, string> = {
  invalid_attempt: "This reconnection link has expired or was already used. Try again.",
  cancelled: "Reconnection was cancelled. You can try again when you are ready.",
  exchange_failed: "Zerodha reconnection could not be completed. Try again.",
  account_mismatch: "Reconnect with the Zerodha account linked to this installation.",
  service_unavailable: "Reconnection is unavailable. Try again when the service is restored.",
};

export function Reconnect({ required }: { required: boolean }) {
  const reconnect = useMutation({ mutationFn: startReconnect });
  const code = new URLSearchParams(window.location.search).get("error");
  const message = code ? reconnectErrors[code] : undefined;
  if (!required && !message) return null;
  return (
    <div>
      <p>You are still signed in to your dashboard. Reconnect to restore access to fresh Zerodha data.</p>
      {message && <p role="alert" className="error">{message}</p>}
      {reconnect.isError && <p role="alert" className="error">Reconnection could not start. Check the backend connection, then try again.</p>}
      <button className="primary zerodha-action" aria-label={reconnect.isPending ? "Opening Zerodha…" : "Reconnect with Zerodha"} disabled={reconnect.isPending} onClick={() => reconnect.mutate()}>
        <span className="zerodha-action-label" aria-hidden="true">
          {reconnect.isPending ? "Opening" : "Reconnect with"}
          <img src="/brands/zerodha.svg" alt="" width="609" height="80" />
        </span>
      </button>
    </div>
  );
}
