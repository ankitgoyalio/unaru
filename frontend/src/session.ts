import { z } from "zod";
export const sessionSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("signed_out") }),
  z.object({
    kind: z.literal("signed_in"),
    userId: z.string(),
    connection: z.enum([
      "active",
      "temporarily_unavailable",
      "reconnect_required",
      "pending_revocation",
      "revoked",
    ]),
    expiresAt: z.iso.datetime({ offset: true }),
  }),
]);
export type Session = z.infer<typeof sessionSchema>;
export async function getSession(): Promise<Session> {
  const response = await fetch("/api/session", { credentials: "same-origin" });
  if (!response.ok) throw new Error("session_unavailable");
  return sessionSchema.parse(await response.json());
}
export async function startLogin(): Promise<void> {
  const response = await fetch("/api/auth/login", {
    method: "POST",
    credentials: "same-origin",
  });
  if (!response.ok) throw new Error("login_unavailable");
  const result = z
    .object({ url: z.string().url() })
    .parse(await response.json());
  window.location.assign(result.url);
}
