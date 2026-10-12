import { useState } from "react";
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
  service_unavailable:
    "Reconnection could not be completed. Try again.",
};

export function Reconnect({
  required,
  active,
  userId,
}: {
  required: boolean;
  active: boolean;
  userId: string;
}) {
  const [logoAvailable, setLogoAvailable] = useState(true);
  const reconnect = useMutation({ mutationFn: startReconnect });
  const code = new URLSearchParams(window.location.search).get("error");
  const message =
    code === "account_mismatch"
      ? `Use Zerodha account ${userId} to reconnect.`
      : code
        ? reconnectErrors[code]
        : undefined;
  if (!required && !message) return null;
  return (
    <div className="profile-actions flex flex-col items-start gap-4 mbs-4">
      <p className="text-muted text-[0.875rem]">
        {active
          ? "The reconnection attempt failed. Your existing Zerodha connection is still active."
          : required
            ? "You're still signed in to Unaru. Sign in to Zerodha again to restore the connection."
            : "The reconnection attempt failed. Check the connection before trying again."}
      </p>
      {message && (
        <p role="alert" className={errorClasses}>
          {message}
        </p>
      )}
      {reconnect.isError && (
        <p role="alert" className={errorClasses}>
          Reconnection could not start. Try again.
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
          {logoAvailable ? (
            <img
              className={brokerLogoClasses}
              src="/brands/zerodha.svg"
              onError={() => setLogoAvailable(false)}
              alt=""
              width="609"
              height="80"
            />
          ) : (
            <span> Zerodha</span>
          )}
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
