import React from "react";
import { createRoot } from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  createRootRoute,
  createRoute,
  createRouter,
  RouterProvider,
  Outlet,
} from "@tanstack/react-router";
import { App } from "./App";
import "./styles.css";

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, staleTime: 0 } },
});
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
const portfolio = createRoute({
  getParentRoute: () => rootRoute,
  path: "/portfolio",
  component: App,
});
const holdings = createRoute({
  getParentRoute: () => rootRoute,
  path: "/holdings",
  component: App,
});
const transactions = createRoute({
  getParentRoute: () => rootRoute,
  path: "/transactions",
  component: App,
});
const reports = createRoute({
  getParentRoute: () => rootRoute,
  path: "/reports",
  component: App,
});
const profile = createRoute({
  getParentRoute: () => rootRoute,
  path: "/profile",
  component: App,
});
const router = createRouter({
  routeTree: rootRoute.addChildren([
    index,
    dashboard,
    portfolio,
    holdings,
    transactions,
    reports,
    profile,
  ]),
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
