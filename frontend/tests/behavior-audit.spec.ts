import { test, expect } from "@playwright/test";

const signedIn = {
  kind: "signed_in", userId: "AUDITOWNER", displayName: "Ankit Goyal",
  connection: "temporarily_unavailable", expiresAt: new Date(Date.now() + 86400000).toISOString(),
};

test("connection verification hides private details and restores logical focus", async ({ page }) => {
  let checking = false;
  let release: (() => void) | undefined;
  await page.route("**/api/session", async (route) => {
    if (checking) await new Promise<void>((resolve) => { release = resolve; });
    await route.fulfill({ json: signedIn });
  });
  await page.goto("/profile");
  await expect(page.getByRole("button", { name: "Check connection" })).toBeVisible();
  checking = true;
  await page.getByRole("button", { name: "Check connection" }).click();
  await expect(page.getByRole("status")).toContainText("Checking your connection");
  await expect(page.getByText("Ankit Goyal", { exact: true })).toHaveCount(0);
  await expect(page.getByText("AUDITOWNER", { exact: true })).toHaveCount(0);
  await expect.poll(() => Boolean(release)).toBe(true);
  release?.();
  await expect(page.getByRole("heading", { name: "Profile", exact: true })).toBeFocused();
});

test("background verification preserves the open drawer and its focused destination", async ({ page }) => {
  let checking = false;
  let release: (() => void) | undefined;
  await page.route("**/api/session", async (route) => {
    if (checking) await new Promise<void>((resolve) => { release = resolve; });
    await route.fulfill({ json: signedIn });
  });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/profile");
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  const drawer = page.getByRole("dialog", { name: "Navigation" });
  const reports = drawer.getByRole("link", { name: "Reports", exact: true });
  await reports.focus();
  checking = true;
  await page.evaluate(() => window.dispatchEvent(new Event("visibilitychange")));
  await expect.poll(() => Boolean(release)).toBe(true);
  await expect(page.getByText("Ankit Goyal", { exact: true })).toHaveCount(0);
  await expect(drawer).toBeVisible();
  await expect(reports).toBeFocused();
  release?.();
  await expect(drawer.getByRole("link", { name: "Ankit Goyal Profile" })).toBeVisible();
  await expect(reports).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(drawer).not.toBeVisible();
  await expect(page.getByRole("heading", { name: "Reports", exact: true })).toBeFocused();
  await expect(page).toHaveTitle("Reports · Unaru");
});

test("failed reconnection preserves the active connection and names the expected account", async ({ page }) => {
  await page.route("**/api/session", (route) => route.fulfill({ json: { ...signedIn, connection: "active" } }));
  await page.goto("/profile?error=account_mismatch");
  await expect(page.getByRole("status")).toHaveText("Connected to Zerodha");
  await expect(page.getByText("The reconnection attempt failed. Your existing Zerodha connection is still active.")).toBeVisible();
  await expect(page.getByRole("alert")).toHaveText("Use Zerodha account AUDITOWNER to reconnect.");
  await expect(page.getByText(/restore the connection/)).toHaveCount(0);
});

for (const screen of ["sign-in", "reconnect"]) {
  test(`provider action remains readable after an image failure on ${screen}`, async ({ page }) => {
    await page.route("**/api/session", (route) => route.fulfill({ json: screen === "sign-in" ? { kind: "signed_out" } : { ...signedIn, connection: "reconnect_required" } }));
    await page.route("**/brands/zerodha.svg", (route) => route.abort());
    await page.goto(screen === "sign-in" ? "/" : "/profile");
    const name = screen === "sign-in" ? "Sign in with Zerodha" : "Reconnect with Zerodha";
    await expect(page.getByRole("button", { name, exact: true })).toHaveText(name);
    if (screen === "sign-in") await expect(page).toHaveTitle("Sign in · Unaru");
  });
}

test("logout updates the page title to sign-in", async ({ page }) => {
  let loggedOut = false;
  await page.route("**/api/session", (route) => route.fulfill({ json: loggedOut ? { kind: "signed_out" } : signedIn }));
  await page.route("**/api/auth/logout", (route) => {
    loggedOut = true;
    return route.fulfill({ status: 204 });
  });
  await page.goto("/profile");
  await expect(page).toHaveTitle("Profile · Unaru");
  await page.getByRole("button", { name: "Log out", exact: true }).click();
  await expect(page.getByRole("heading", { name: "Welcome to Unaru" })).toBeVisible();
  await expect(page).toHaveTitle("Sign in · Unaru");
});
