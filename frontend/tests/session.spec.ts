import { test, expect } from "@playwright/test";

test("persisted cookie restores identity in a new browser process", async ({ page, context, browser }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Sign in with Zerodha" }).click();
  await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
  const state = await context.storageState();
  const cookie = state.cookies.find((item) => item.name === "unaru_session");
  expect(cookie?.expires).toBeGreaterThan(Date.now() / 1000 + 29 * 86400);
  await context.close();
  const restarted = await browser.browserType().launch();
  try {
    const returning = await restarted.newContext({ storageState: state });
    const restored = await returning.newPage();
    await restored.goto("http://127.0.0.1:5173/dashboard");
    await expect(restored.getByText("Signed in as TESTOWNER")).toBeVisible();
    await expect(restored.getByRole("status")).toContainText("Connected to Zerodha");
  } finally {
    await restarted.close();
  }
});

test("status refresh hides stale dashboard identity and restores sign-in", async ({ page }) => {
  let kind: "signed_in" | "signed_out" = "signed_in";
  let release: (() => void) | undefined;
  await page.route("**/api/session", async (route) => {
    if (kind === "signed_out") await new Promise<void>((resolve) => { release = resolve; });
    await route.fulfill({ json: kind === "signed_in" ? {
      kind, userId: "TESTOWNER", connection: "active", expiresAt: new Date(Date.now() + 86400000).toISOString(),
    } : { kind } });
  });
  await page.goto("/dashboard");
  await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
  kind = "signed_out";
  await page.evaluate(() => window.dispatchEvent(new Event("visibilitychange")));
  await expect(page.getByRole("status")).toContainText("Opening your dashboard");
  await expect(page.getByText("Signed in as TESTOWNER")).toHaveCount(0);
  release?.();
  await expect(page.getByRole("button", { name: "Sign in with Zerodha" })).toBeVisible();
  await expect(page.getByText("Signed in as TESTOWNER")).toHaveCount(0);
});

test("database outage shows recovery and keeps authenticated content hidden", async ({ page }) => {
  let unavailable = true;
  await page.route("**/api/session", (route) => route.fulfill(unavailable
    ? { status: 503, json: { error: "service_unavailable" } }
    : { json: { kind: "signed_out" } }));
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "Dashboard unavailable" })).toBeVisible();
  await expect(page.getByText("Signed in as TESTOWNER")).toHaveCount(0);
  unavailable = false;
  await page.getByRole("button", { name: "Try again" }).click();
  await expect(page.getByRole("button", { name: "Sign in with Zerodha" })).toBeVisible();
});


test("absolute session expiry returns an open dashboard to sign-in", async ({ page }) => {
  const expires = Date.now() + 1500;
  await page.route("**/api/session", (route) => route.fulfill({ json: Date.now() < expires
    ? { kind: "signed_in", userId: "TESTOWNER", connection: "active", expiresAt: new Date(expires).toISOString() }
    : { kind: "signed_out" } }));
  await page.goto("/dashboard");
  await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
  await expect(page.getByRole("button", { name: "Sign in with Zerodha" })).toBeVisible();
});

test("invalid API expiry shows recovery instead of an authenticated dashboard", async ({ page }) => {
  await page.route("**/api/session", (route) => route.fulfill({ json: {
    kind: "signed_in", userId: "TESTOWNER", connection: "active", expiresAt: "invalid-date",
  } }));
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "Dashboard unavailable" })).toBeVisible();
  await expect(page.getByText("Signed in as TESTOWNER")).toHaveCount(0);
});

test("temporary broker outage preserves identity and recovers without reconnection", async ({ page }) => {
  let connection = "temporarily_unavailable";
  await page.route("**/api/session", (route) => route.fulfill({ json: {
    kind: "signed_in", userId: "TESTOWNER", connection,
    expiresAt: new Date(Date.now() + 86400000).toISOString(),
  } }));
  await page.goto("/dashboard");
  await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
  await expect(page.getByRole("status")).toContainText("Zerodha is temporarily unavailable");
  await expect(page.getByRole("button", { name: "Reconnect Zerodha", exact: true })).toHaveCount(0);
  connection = "active";
  await page.getByRole("button", { name: "Check connection" }).click();
  await expect(page.getByRole("status")).toContainText("Connected to Zerodha");
});
