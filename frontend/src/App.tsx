import { useMutation, useQuery } from "@tanstack/react-query";
import { getSession, startLogin } from "./session";
import { Logout } from "./Logout";
import { Reconnect } from "./Reconnect";

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
    <main className="login-layout">
      <section className="signin">
        <span className="wordmark">
          unaru<span aria-hidden="true">↗</span>
        </span>
        <div className="signin-content">
          <p className="eyebrow">YOUR INVESTMENTS, IN VIEW</p>
          <h1>Welcome to Unaru</h1>
          <p className="intro">
            A clearer view of your investments.
            <br />
            Start with your Zerodha account.
          </p>
          {errorCode && (
            <p role="alert" className="error">
              {errors[errorCode] ??
                "Sign-in could not be completed. Please try again."}
            </p>
          )}
          {login.isError && (
            <p role="alert" className="error">
              Sign-in could not start. Check that Unaru is running, then try again.
            </p>
          )}
          <button
            className="primary zerodha-action"
            aria-label={
              login.isPending ? "Opening Zerodha…" : "Sign in with Zerodha"
            }
            onClick={() => login.mutate()}
            disabled={login.isPending}
          >
            <span className="zerodha-action-label" aria-hidden="true">
              {login.isPending ? "Opening" : "Sign in with"}
              <img src="/brands/zerodha.svg" alt="Zerodha" width="609" height="80" />
            </span>
            <span aria-hidden="true">↗</span>
          </button>
          <p className="provider-note" role="status">
            {login.isPending
              ? "Opening Zerodha sign-in…"
              : "You'll complete sign-in on Zerodha."}
          </p>
          <p className="signup">
            Don't have a Zerodha account yet?{" "}
            <a href="https://zerodha.com/open-account?c=SH1331">Sign up</a>
          </p>
        </div>
        <p className="signin-footer">Your dashboard. Your account.</p>
      </section>
      <aside className="artwork" aria-label="Investment illustration">
        <div className="art-caption">
          <span className="eyebrow">A LITTLE PERSPECTIVE</span>
          <h2>See the bigger picture.</h2>
          <p>
            One place to begin understanding
            <br />
            your investment journey.
          </p>
        </div>
        <svg
          className="investment-art"
          viewBox="0 0 600 500"
          aria-hidden="true"
        >
          <defs>
            <pattern
              id="grid"
              width="32"
              height="32"
              patternUnits="userSpaceOnUse"
            >
              <path
                d="M 32 0 L 0 0 0 32"
                fill="none"
                stroke="currentColor"
                strokeOpacity=".12"
              />
            </pattern>
          </defs>
          <rect width="600" height="500" fill="url(#grid)" />
          <circle
            cx="300"
            cy="250"
            r="190"
            fill="none"
            stroke="currentColor"
            strokeOpacity=".15"
          />
          <circle
            cx="300"
            cy="250"
            r="135"
            fill="none"
            stroke="currentColor"
            strokeOpacity=".2"
          />
          <path
            d="M115 355 L195 275 L265 306 L347 197 L415 224 L490 120"
            fill="none"
            stroke="currentColor"
            strokeWidth="5"
          />
          <path
            d="M464 120 H490 V147"
            fill="none"
            stroke="currentColor"
            strokeWidth="5"
          />
          <g fill="currentColor">
            <circle cx="195" cy="275" r="7" />
            <circle cx="265" cy="306" r="7" />
            <circle cx="347" cy="197" r="7" />
            <circle cx="415" cy="224" r="7" />
          </g>
          <rect
            x="150"
            y="365"
            width="300"
            height="3"
            fill="currentColor"
            opacity=".35"
          />
        </svg>
        <p className="art-footer">Built for a long-term view.</p>
      </aside>
    </main>
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
      <main className="status-page" role="status">
        Opening your dashboard…
      </main>
    );
  if (session.isError)
    return (
      <main className="status-page">
        <h1>Dashboard unavailable</h1>
        <p>Your session could not load. Check that Unaru is running, then try again.</p>
        <button onClick={() => session.refetch()}>Try again</button>
      </main>
    );
  if (session.data.kind === "signed_out") return <Login />;
  return (
    <main className="dashboard">
      <a className="wordmark" href="/dashboard">
        unaru<span aria-hidden="true">↗</span>
      </a>
      <section>
        <p className="eyebrow">YOUR DASHBOARD</p>
        <h1>Welcome back</h1>
        <p>Signed in as {session.data.userId}</p>
        <p className="connection" role="status">
          {session.data.connection === "active"
            ? "Connected to Zerodha"
            : session.data.connection === "temporarily_unavailable"
              ? "Zerodha is temporarily unavailable"
              : "Zerodha reconnection required"}
        </p>
        {session.data.connection === "temporarily_unavailable" && (
          <>
            <p>You are still signed in to Unaru. Check the Zerodha connection again.</p>
            <button onClick={() => session.refetch()}>Check connection</button>
          </>
        )}
        <Reconnect
          required={
            session.data.connection !== "active" &&
            session.data.connection !== "temporarily_unavailable"
          }
        />
        <Logout />
      </section>
    </main>
  );
}
