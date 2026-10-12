import { test, expect } from "@playwright/test";

const signedIn = {
  kind: "signed_in",
  userId: "UI-TEST",
  connection: "reconnect_required",
  expiresAt: new Date(Date.now() + 86400000).toISOString(),
};

for (const screen of ["sign-in", "reconnect"]) {
  test(`broker buttons reflow with enlarged and spaced text on ${screen}`, async ({ page }) => {
    await page.route("**/api/session", (route) => route.fulfill({
      json: screen === "sign-in" ? { kind: "signed_out" } : signedIn,
    }));
    await page.setViewportSize({ width: 320, height: 800 });
    await page.goto(screen === "sign-in" ? "/" : "/profile");
    const button = page.getByRole("button", {
      name: screen === "sign-in" ? "Sign in with Zerodha" : "Reconnect with Zerodha",
    });
    await expect(button).toBeVisible();
    await page.addStyleTag({ content: `
      html { font-size: 200%; }
      * { line-height: 1.5 !important; letter-spacing: 0.12em !important; word-spacing: 0.16em !important; }
      p { margin-block-end: 2em !important; }
    ` });
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(320);
    const buttonBounds = await button.boundingBox();
    const logoBounds = await button.locator("img").boundingBox();
    expect(buttonBounds).not.toBeNull();
    expect(logoBounds).not.toBeNull();
    if (buttonBounds && logoBounds) {
      expect(logoBounds.x).toBeGreaterThanOrEqual(buttonBounds.x);
      expect(logoBounds.x + logoBounds.width).toBeLessThanOrEqual(buttonBounds.x + buttonBounds.width);
      expect(logoBounds.y + logoBounds.height).toBeLessThanOrEqual(buttonBounds.y + buttonBounds.height);
    }
    await page.emulateMedia({ forcedColors: "active", reducedMotion: "reduce" });
    await button.focus();
    await expect(button).toBeFocused();
    expect(await button.evaluate((element) => getComputedStyle(element).outlineStyle)).toBe("solid");
    expect(await button.evaluate((element) => parseFloat(getComputedStyle(element).outlineWidth))).toBeGreaterThanOrEqual(2);
  });
}

for (const action of [
  { name: "Sign in with Zerodha", pending: "Opening Zerodha…", endpoint: "login", status: "Opening Zerodha sign-in…", error: "Sign-in could not start", session: { kind: "signed_out" } },
  { name: "Reconnect with Zerodha", pending: "Opening Zerodha…", endpoint: "reconnect", status: "Opening Zerodha to reconnect…", error: "Reconnection could not start", session: signedIn },
  { name: "Log out", pending: "Logging out…", endpoint: "logout", status: "Logging out of Unaru…", error: "Could not log out", session: signedIn },
]) {
  test(`authentication actions announce progress and allow retry for ${action.endpoint}`, async ({ page }) => {
    await page.route("**/api/session", (route) => route.fulfill({ json: action.session }));
    let release: (() => void) | undefined;
    await page.route(`**/api/auth/${action.endpoint}`, async (route) => {
      await new Promise<void>((resolve) => { release = resolve; });
      await route.fulfill({ status: 503, json: { error: "service_unavailable" } });
    });
    await page.goto(action.endpoint === "login" ? "/" : "/profile");
    await page.getByRole("button", { name: action.name, exact: true }).focus();
    await page.keyboard.press("Enter");
    await expect(page.getByRole("button", { name: action.pending, exact: true })).toBeDisabled();
    await expect(page.getByRole("status").filter({ hasText: action.status })).toBeVisible();
    await expect.poll(() => Boolean(release)).toBe(true);
    release?.();
    await expect(page.getByRole("alert")).toContainText(action.error);
    await expect(page.getByRole("button", { name: action.name, exact: true })).toBeEnabled();
  });
}
