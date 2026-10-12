import { useMutation, useQueryClient } from "@tanstack/react-query";
import { errorClasses } from "./ui";
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
      client.removeQueries({
        predicate: (query) => query.queryKey[0] !== "session",
      });
      client.setQueryData(["session"], { kind: "signed_out" });
      await navigate({ to: "/", replace: true });
    },
  });
  return (
    <div className="flex flex-col items-start gap-4">
      <button
        className="bg-paper text-ink border-line fine-hover:bg-soft fine-hover:text-ink"
        onClick={() => logout.mutate()}
        disabled={logout.isPending}
      >
        {logout.isPending ? "Logging out…" : "Log out"}
      </button>
      {logout.isPending && (
        <p className="text-muted text-[0.8rem]" role="status">
          Logging out of Unaru…
        </p>
      )}
      {logout.isError && (
        <p className={errorClasses} role="alert">
          Could not log out. Check your connection and try again.
        </p>
      )}
    </div>
  );
}
