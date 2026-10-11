import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useNavigate } from "@tanstack/react-router";

export function Logout() {
  const client = useQueryClient();
  const navigate = useNavigate();
  const logout = useMutation({
    mutationFn: async () => {
      const response = await fetch("/api/auth/logout", {
        method: "POST",
        credentials: "same-origin",
      });
      if (!response.ok) throw new Error("logout_unavailable");
    },
    onSuccess: async () => {
      await client.cancelQueries({ queryKey: ["session"] });
      client.removeQueries({ predicate: query => query.queryKey[0] !== "session" });
      client.setQueryData(["session"], { kind: "signed_out" });
      await navigate({ to: "/", replace: true });
    },
  });
  return (
    <>
      <button onClick={() => logout.mutate()} disabled={logout.isPending}>
        {logout.isPending ? "Logging out…" : "Log out"}
      </button>
      {logout.isError && (
        <p role="alert">Logout could not finish. Check your connection and try again.</p>
      )}
    </>
  );
}
