import { useMutation } from "@tanstack/react-query";
import { z } from "zod";
import {
  errorClasses,
  brokerButtonClasses,
  brokerLabelClasses,
  brokerLogoClasses,
} from "./ui";

async function startReconnect(): Promise<void> {
  const response = await fetch("/api/auth/reconnect", {
    method: "POST",
    credentials: "same-origin",
  });
  if (!response.ok) throw new Error("reconnect_unavailable");
  const result = z
    .object({ url: z.string().url() })
    .parse(await response.json());
  window.location.assign(result.url);
}

const reconnectErrors: Record<string, string> = {
  invalid_attempt:
    "This reconnection link has expired or was already used. Try again.",
  cancelled:
    "Reconnection was cancelled. You can try again when you are ready.",
  exchange_failed: "Zerodha reconnection could not be completed. Try again.",
  account_mismatch:
    "Reconnect with the Zerodha account linked to this installation.",
  service_unavailable:
    "Reconnection is unavailable. Try again when the service is restored.",
};

export function Reconnect({ required }: { required: boolean }) {
  const reconnect = useMutation({ mutationFn: startReconnect });
  const code = new URLSearchParams(window.location.search).get("error");
  const message = code ? reconnectErrors[code] : undefined;
  if (!required && !message) return null;
  return (
    <div className="flex flex-col gap-4 mbs-4">
      <p className="text-muted text-[0.875rem]">
        You're still signed in to Unaru. Sign in to Zerodha again to restore the
        connection.
      </p>
      {message && (
        <p role="alert" className={errorClasses}>
          {message}
        </p>
      )}
      {reconnect.isError && (
        <p role="alert" className={errorClasses}>
          Reconnection could not start. Check that Unaru is running, then try
          again.
        </p>
      )}
      <button
        className={brokerButtonClasses}
        aria-label={
          reconnect.isPending ? "Opening Zerodha…" : "Reconnect with Zerodha"
        }
        disabled={reconnect.isPending}
        onClick={() => reconnect.mutate()}
      >
        <span className={brokerLabelClasses} aria-hidden="true">
          {reconnect.isPending ? "Opening" : "Reconnect with"}
          <img
            className={brokerLogoClasses}
            src="/brands/zerodha.svg"
            alt=""
            width="609"
            height="80"
          />
        </span>
      </button>
      {reconnect.isPending && (
        <p className="text-muted text-[0.8rem]" role="status">
          Opening Zerodha to reconnect…
        </p>
      )}
    </div>
  );
}
