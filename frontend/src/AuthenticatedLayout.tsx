import { useEffect, useRef, useState } from "react";
import { Link, useLocation, useNavigate } from "@tanstack/react-router";
import type { Session } from "./session";
import { Logout } from "./Logout";
import { Reconnect } from "./Reconnect";
import { wordmarkClasses } from "./ui";

const destinations = [
  {
    to: "/dashboard",
    label: "Dashboard",
    icon: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
  },
  {
    to: "/portfolio",
    label: "Portfolio",
    icon: "M3 7h18v14H3z M8 7V3h8v4 M3 12h18 M10 12v3h4v-3",
  },
  {
    to: "/holdings",
    label: "Holdings",
    icon: "M4 21V10h4v11 M10 21V3h4v18 M16 21V7h4v14",
  },
  {
    to: "/transactions",
    label: "Transactions",
    icon: "M3 7h18 M17 3l4 4-4 4 M21 17H3 M7 13l-4 4 4 4",
  },
  {
    to: "/reports",
    label: "Reports",
    icon: "M5 3h10l4 4v14H5z M14 3v5h5 M9 12h6 M9 16h6",
  },
] satisfies {
  to: "/dashboard" | "/portfolio" | "/holdings" | "/transactions" | "/reports";
  label: string;
  icon: string;
}[];

export function NavigationIcon({ path }: { path: string }) {
  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.6"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d={path} />
    </svg>
  );
}

export function InvestmentNavigation({
  identity,
  currentPath,
  onNavigate,
}: {
  identity: string;
  currentPath: string;
  onNavigate?: () => void;
}) {
  const renderDestination = (item: (typeof destinations)[number]) => (
    <Link
      key={item.to}
      to={item.to}
      onClick={onNavigate}
      className="navigation-link"
      aria-current={currentPath === item.to ? "page" : undefined}
    >
      <NavigationIcon path={item.icon} />
      {item.label}
    </Link>
  );
  return (
    <aside className="investment-sidebar">
      <Link
        className={`${wordmarkClasses} sidebar-brand`}
        to="/dashboard"
        onClick={onNavigate}
      >
        unaru.
      </Link>
      <nav aria-label="Investment navigation" className="investment-navigation">
        <p className="navigation-group">Workspace</p>
        {destinations.slice(0, 1).map(renderDestination)}
        <p className="navigation-group">Investments</p>
        {destinations.slice(1).map(renderDestination)}
      </nav>
      <Link
        to="/profile"
        onClick={onNavigate}
        className="account-link"
        aria-current={currentPath === "/profile" ? "page" : undefined}
      >
        <span className="account-avatar" aria-hidden="true">
          <NavigationIcon path="M20 21v-2a7 7 0 0 0-14 0v2 M16 7a4 4 0 1 1-8 0 4 4 0 0 1 8 0" />
        </span>
        <span className="account-identity">
          <span>{identity}</span>
          <span className="account-caption">Profile</span>
        </span>
        <span aria-hidden="true">›</span>
      </Link>
    </aside>
  );
}

function MobileNavigation({
  identity,
  currentPath,
  onDesktopDismiss,
}: {
  identity: string;
  currentPath: string;
  onDesktopDismiss: () => void;
}) {
  const drawer = useRef<HTMLDialogElement>(null);
  const opener = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const dismiss = () => drawer.current?.close();
  useEffect(() => {
    const desktop = window.matchMedia("(min-width: 48rem)");
    const onResize = () => {
      if (desktop.matches) drawer.current?.close();
    };
    desktop.addEventListener("change", onResize);
    return () => desktop.removeEventListener("change", onResize);
  }, []);
  return (
    <>
      <header className="mobile-header">
        <span className={wordmarkClasses}>unaru.</span>
        <button
          ref={opener}
          type="button"
          aria-controls="mobile-navigation"
          aria-haspopup="dialog"
          aria-expanded={open}
          onClick={() => {
            drawer.current?.showModal();
            setOpen(true);
          }}
        >
          Menu
        </button>
      </header>
      <dialog
        ref={drawer}
        id="mobile-navigation"
        className="navigation-drawer"
        aria-label="Navigation"
        onKeyDown={(event) => {
          if (event.key !== "Tab") return;
          const controls = Array.from(
            event.currentTarget.querySelectorAll<
              HTMLAnchorElement | HTMLButtonElement
            >("a[href], button:not([disabled])"),
          );
          const first = controls.at(0);
          const last = controls.at(-1);
          if (event.shiftKey && document.activeElement === first) {
            event.preventDefault();
            last?.focus();
          } else if (!event.shiftKey && document.activeElement === last) {
            event.preventDefault();
            first?.focus();
          }
        }}
        onClose={() => {
          setOpen(false);
          if (window.matchMedia("(min-width: 48rem)").matches) {
            onDesktopDismiss();
          } else {
            opener.current?.focus();
          }
        }}
      >
        <button
          type="button"
          className="drawer-close"
          autoFocus
          onClick={dismiss}
        >
          Close menu
        </button>
        <InvestmentNavigation
          identity={identity}
          currentPath={currentPath}
          onNavigate={dismiss}
        />
      </dialog>
    </>
  );
}

type SignedInSession = Extract<Session, { kind: "signed_in" }>;

export function AuthenticatedLayout({
  session,
  refresh,
}: {
  session: SignedInSession;
  refresh: () => unknown;
}) {
  const location = useLocation();
  const navigate = useNavigate();
  const path = location.pathname === "/" ? "/dashboard" : location.pathname;
  const title =
    path === "/profile"
      ? "Profile"
      : (destinations.find((item) => item.to === path)?.label ?? "Dashboard");
  const heading = useRef<HTMLHeadingElement>(null);
  const previousPath = useRef(path);
  useEffect(() => {
    document.title = `${title} · Unaru`;
    if (previousPath.current !== path) heading.current?.focus();
    previousPath.current = path;
  }, [path, title]);
  useEffect(() => {
    if (
      path === "/dashboard" &&
      new URLSearchParams(window.location.search).has("error")
    ) {
      void navigate({
        to: "/profile",
        search: {
          error: new URLSearchParams(window.location.search).get("error"),
        },
        replace: true,
      });
    }
  }, [path, navigate]);
  return (
    <div className="authenticated-shell">
      <a href="#page-content" className="skip-link">
        Skip to content
      </a>
      <MobileNavigation
        identity={session.displayName ?? session.userId}
        currentPath={path}
        onDesktopDismiss={() => heading.current?.focus()}
      />
      <div className="desktop-navigation">
        <InvestmentNavigation
          identity={session.displayName ?? session.userId}
          currentPath={path}
        />
      </div>
      <main id="page-content" className="investment-content">
        <p className="page-eyebrow">Your workspace</p>
        <h1 ref={heading} tabIndex={-1}>
          {title}
        </h1>
        {path !== "/profile" ? (
          <section
            className="placeholder-panel"
            aria-label={`${title} availability`}
          >
            <NavigationIcon
              path={
                destinations.find((item) => item.to === path)?.icon ??
                "M3 3h18v18H3z"
              }
            />
            <h2>{title} is coming soon</h2>
            <p>Investment content is not available yet.</p>
          </section>
        ) : (
          <div className="profile-content">
            <section aria-labelledby="account-title" className="profile-panel">
              <h2 id="account-title">Account details</h2>
              <dl>
                <dt>Name</dt>
                <dd>{session.displayName ?? session.userId}</dd>
                <dt>Zerodha user ID</dt>
                <dd>{session.userId}</dd>
              </dl>
            </section>
            <section
              aria-labelledby="connection-title"
              className="profile-panel"
            >
              <h2 id="connection-title">Broker connection</h2>
              <p role="status" className="connection-status">
                <span
                  aria-hidden="true"
                  className={`connection-dot ${session.connection === "active" ? "connection-active" : ""}`}
                />
                {session.connection === "active"
                  ? "Connected to Zerodha"
                  : session.connection === "temporarily_unavailable"
                    ? "Zerodha is temporarily unavailable"
                    : "Zerodha reconnection required"}
              </p>
              {session.connection === "active" && (
                <p className="text-muted">Your broker connection is active.</p>
              )}
              {session.connection === "temporarily_unavailable" && (
                <div className="flex flex-col items-start gap-4 mbs-4">
                  <p className="text-muted">
                    You're still signed in to Unaru. Check the connection to try
                    again.
                  </p>
                  <button onClick={refresh}>Check connection</button>
                </div>
              )}
              <Reconnect
                required={
                  session.connection !== "active" &&
                  session.connection !== "temporarily_unavailable"
                }
              />
            </section>
            <section className="profile-panel" aria-labelledby="session-title">
              <h2 id="session-title">Dashboard session</h2>
              <p className="text-muted mbe-6">
                Log out to end your Unaru session.
              </p>
              <Logout />
            </section>
          </div>
        )}
      </main>
    </div>
  );
}
