import { useMutation, useQuery } from "@tanstack/react-query";
import { getSession, startLogin } from "./session";
import { AuthenticatedLayout } from "./AuthenticatedLayout";
import {
  wordmarkClasses,
  shellClasses,
  accountPanelClasses,
  errorClasses,
  brokerButtonClasses,
  brokerLabelClasses,
  brokerLogoClasses,
} from "./ui";

const errors: Record<string, string> = {
  invalid_attempt:
    "This sign-in link has expired or was already used. Start again.",
  cancelled: "Sign-in was cancelled. You can try again when you are ready.",
  exchange_failed: "Zerodha sign-in could not be completed. Try again.",
  account_mismatch:
    "Sign in with the Zerodha account linked to this installation.",
  service_unavailable:
    "Sign-in is unavailable. Check that Unaru is running, then try again.",
};
function Login() {
  const login = useMutation({ mutationFn: startLogin });
  const errorCode = new URLSearchParams(window.location.search).get("error");
  return (
    <div className={shellClasses}>
      <header>
        <span className={wordmarkClasses}>unaru.</span>
      </header>
      <main className={accountPanelClasses}>
        <div className="text-center mbe-12">
          <h1>Welcome to Unaru</h1>
          <p className="text-muted mbs-2">
            Sign in to access your account dashboard.
          </p>
        </div>
        <div className="flex flex-col gap-4">
          {errorCode && (
            <p role="alert" className={errorClasses}>
              {errors[errorCode] ??
                "Sign-in could not be completed. Try again."}
            </p>
          )}
          {login.isError && (
            <p role="alert" className={errorClasses}>
              Sign-in could not start. Check that Unaru is running, then try
              again.
            </p>
          )}
          <button
            className={brokerButtonClasses}
            aria-label={
              login.isPending ? "Opening Zerodha…" : "Sign in with Zerodha"
            }
            onClick={() => login.mutate()}
            disabled={login.isPending}
          >
            <span className={brokerLabelClasses} aria-hidden="true">
              {login.isPending ? "Opening" : "Sign in with"}
              <img
                className={brokerLogoClasses}
                src="/brands/zerodha.svg"
                alt=""
                width="609"
                height="80"
              />
            </span>
          </button>
          {login.isPending && (
            <p className="text-[0.8rem] text-muted text-center" role="status">
              Opening Zerodha sign-in…
            </p>
          )}
        </div>
        <p className="text-[0.875rem] text-muted text-center mbs-4">
          Don't have a Zerodha account?{" "}
          <a
            className="inline-block py-2 font-medium"
            href="https://zerodha.com/open-account?c=SH1331"
          >
            Sign up
          </a>
        </p>
      </main>
      <footer className="text-center text-muted text-[0.75rem]">
        Your account dashboard, connected to Zerodha.
      </footer>
    </div>
  );
}
export function App() {
  const session = useQuery({
    queryKey: ["session"],
    queryFn: getSession,
    refetchOnMount: "always",
    refetchOnWindowFocus: "always",
    refetchInterval: (query) => {
      const current = query.state.data;
      return current?.kind === "signed_in"
        ? Math.max(
            1000,
            Math.min(2_147_483_647, Date.parse(current.expiresAt) - Date.now()),
          )
        : false;
    },
  });
  if (session.isPending || session.isFetching)
    return (
      <div className={shellClasses}>
        <header>
          <span className={wordmarkClasses}>unaru.</span>
        </header>
        <main className={`${accountPanelClasses} text-center`} role="status">
          Opening your dashboard…
        </main>
      </div>
    );
  if (session.isError)
    return (
      <div className={shellClasses}>
        <header>
          <span className={wordmarkClasses}>unaru.</span>
        </header>
        <main className={`${accountPanelClasses} text-center`}>
          <h1>Dashboard unavailable</h1>
          <p className="text-muted mbs-4 mbe-8">
            Your session could not load. Check that Unaru is running, then try
            again.
          </p>
          <button onClick={() => session.refetch()}>Try again</button>
        </main>
      </div>
    );
  if (session.data.kind === "signed_out") return <Login />;
  return <AuthenticatedLayout session={session.data} refresh={() => session.refetch()} />;
}
