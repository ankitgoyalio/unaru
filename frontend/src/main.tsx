import React from "react";
import { createRoot } from "react-dom/client";
import {
  QueryClient,
  QueryClientProvider,
  useMutation,
  useQuery,
} from "@tanstack/react-query";
import {
  createRootRoute,
  createRoute,
  createRouter,
  RouterProvider,
  Outlet,
} from "@tanstack/react-router";
import { getSession, startLogin } from "./session";
import "./styles.css";
import { Logout } from "./Logout";
import { Reconnect } from "./Reconnect";
const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, staleTime: 0 } },
});
const errors: Record<string, string> = {
  invalid_attempt:
    "This sign-in link has expired or was already used. Start again.",
  cancelled: "Sign-in was cancelled. You can try again when you are ready.",
  exchange_failed: "Zerodha sign-in could not be completed. Try again.",
  account_mismatch:
    "Sign in with the Zerodha account linked to this installation.",
  service_unavailable:
    "The dashboard is unavailable. Check the backend and database, then try again.",
};
function Login() {
  const login = useMutation({ mutationFn: startLogin });
  const errorCode = new URLSearchParams(window.location.search).get("error");
  return (
    <main className="login-layout">
      <section className="signin">
        <a className="wordmark" href="/" tabIndex={-1}>
          unaru<span aria-hidden="true">↗</span>
        </a>
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
              Sign-in could not start. Check that your backend is running and
              configured, then try again.
            </p>
          )}
          <button
            className="primary"
            onClick={() => login.mutate()}
            disabled={login.isPending}
          >
            {login.isPending ? "Opening Zerodha…" : "Sign in with Zerodha"}
            <span aria-hidden="true">↗</span>
          </button>
          <p className="provider-note">You'll complete sign-in on Zerodha.</p>
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
  const session = useQuery({ queryKey: ["session"], queryFn: getSession });
  if (session.isPending)
    return (
      <main className="status-page" role="status">
        Opening your dashboard…
      </main>
    );
  if (session.isError)
    return (
      <main className="status-page">
        <h1>Dashboard unavailable</h1>
        <p>Check the backend and database connection, then try again.</p>
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
            : "Zerodha reconnection required"}
        </p>
        <Reconnect required={session.data.connection !== "active"} />
        <p>Your investment dashboard is ready.</p>
        <Logout />
      </section>
    </main>
  );
}
const rootRoute = createRootRoute({ component: Outlet });
const index = createRoute({
  getParentRoute: () => rootRoute,
  path: "/",
  component: App,
});
const dashboard = createRoute({
  getParentRoute: () => rootRoute,
  path: "/dashboard",
  component: App,
});
const router = createRouter({
  routeTree: rootRoute.addChildren([index, dashboard]),
});
declare module "@tanstack/react-router" {
  interface Register {
    router: typeof router;
  }
}
const root = document.getElementById("root");
if (!root) throw new Error("Missing application root");
createRoot(root).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </React.StrictMode>,
);
