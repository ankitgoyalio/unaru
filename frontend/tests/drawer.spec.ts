import { test, expect } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.route("**/api/session", (route) =>
    route.fulfill({
      json: {
        kind: "signed_in",
        userId: "DRAWEROWNER",
        connection: "reconnect_required",
        expiresAt: new Date(Date.now() + 86400000).toISOString(),
      },
    }),
  );
});

test("mobile navigation opens a modal and restores opener focus on dismissal", async ({
  page,
}) => {
  await page.goto("/dashboard");
  const opener = page.getByRole("button", { name: "Menu", exact: true });
  await expect(opener).toHaveAttribute("aria-expanded", "false");
  await opener.focus();
  await page.keyboard.press("Enter");
  const drawer = page.getByRole("dialog", { name: "Navigation" });
  await expect(drawer).toBeVisible();
  await expect(opener).toHaveAttribute("aria-expanded", "true");
  const close = drawer.getByRole("button", { name: "Close menu" });
  await expect(close).toBeFocused();
  await page.getByRole("heading", { name: "Dashboard", exact: true }).focus();
  await expect(close).toBeFocused();
  await page.keyboard.press("Shift+Tab");
  await expect(
    drawer.getByRole("link", { name: "DRAWEROWNER Profile" }),
  ).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(close).toBeFocused();
  await page.keyboard.press("Escape");
  await expect(drawer).not.toBeVisible();
  await expect(opener).toBeFocused();
  await opener.click();
  await close.click();
  await expect(drawer).not.toBeVisible();
  await expect(opener).toBeFocused();
});

test("every mobile destination closes navigation and exposes its active state", async ({
  page,
}) => {
  await page.goto("/dashboard");
  const opener = page.getByRole("button", { name: "Menu", exact: true });
  const drawer = page.getByRole("dialog", { name: "Navigation" });
  for (const destination of [
    "Dashboard",
    "Portfolio",
    "Holdings",
    "Transactions",
    "Reports",
    "Profile",
  ]) {
    await opener.click();
    const link = drawer.getByRole("link", {
      name: destination === "Profile" ? "DRAWEROWNER Profile" : destination,
      exact: true,
    });
    await link.focus();
    await page.keyboard.press("Enter");
    await expect(drawer).not.toBeVisible();
    await expect(
      page.getByRole("heading", { name: destination, exact: true }),
    ).toBeVisible();
    await opener.click();
    await expect(link).toHaveAttribute("aria-current", "page");
    await page.keyboard.press("Escape");
  }
  await expect(
    page.getByRole("button", { name: "Reconnect with Zerodha" }),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Log out", exact: true }),
  ).toBeVisible();
  await opener.click();
  await page.setViewportSize({ width: 1280, height: 800 });
  await expect(drawer).not.toBeVisible();
  await expect(
    page.getByRole("navigation", { name: "Investment navigation" }),
  ).toBeVisible();
  await expect(opener).not.toBeVisible();
});

test("drawer keeps controls reachable with enlarged text, forced colors and long identity", async ({
  page,
}) => {
  await page.route("**/api/session", (route) =>
    route.fulfill({
      json: {
        kind: "signed_in",
        userId: "VERYLONGIDENTITYWITHOUTSPACESFORREFLOW",
        connection: "reconnect_required",
        expiresAt: new Date(Date.now() + 86400000).toISOString(),
      },
    }),
  );
  await page.setViewportSize({ width: 320, height: 568 });
  await page.emulateMedia({ forcedColors: "active", reducedMotion: "reduce" });
  await page.goto("/profile");
  await page.addStyleTag({
    content:
      "html { font-size: 200%; } * { line-height: 1.5 !important; letter-spacing: 0.12em !important; word-spacing: 0.16em !important; }",
  });
  await page.getByRole("button", { name: "Menu", exact: true }).focus();
  await page.keyboard.press("Enter");
  const drawer = page.getByRole("dialog", { name: "Navigation" });
  const close = drawer.getByRole("button", { name: "Close menu" });
  await expect(close).toBeInViewport();
  expect(
    await close.evaluate((element) => getComputedStyle(element).outlineStyle),
  ).toBe("solid");
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(
    320,
  );
  const account = drawer.getByRole("link", {
    name: "VERYLONGIDENTITYWITHOUTSPACESFORREFLOW Profile",
  });
  await account.scrollIntoViewIfNeeded();
  await expect(account).toBeInViewport();
  for (const name of [
    "Dashboard",
    "Portfolio",
    "Holdings",
    "Transactions",
    "Reports",
  ]) {
    const link = drawer.getByRole("link", { name, exact: true });
    await link.focus();
    await expect(link).toBeInViewport();
  }
  await close.click();
  await page
    .getByRole("button", { name: "Reconnect with Zerodha" })
    .scrollIntoViewIfNeeded();
  await expect(
    page.getByRole("button", { name: "Reconnect with Zerodha" }),
  ).toBeInViewport();
});
