import { test, expect } from "@playwright/test";

test("investment destinations persist navigation through direct entry, refresh and history", async ({
  page,
}) => {
  await page.route("**/api/session", (route) =>
    route.fulfill({
      json: {
        kind: "signed_in",
        userId: "NAVOWNER",
        connection: "active",
        expiresAt: new Date(Date.now() + 86400000).toISOString(),
      },
    }),
  );
  await page.goto("/dashboard");
  for (const name of [
    "Dashboard",
    "Portfolio",
    "Holdings",
    "Transactions",
    "Reports",
  ]) {
    await page
      .getByRole("navigation", { name: "Investment navigation" })
      .getByRole("link", { name, exact: true })
      .click();
    await expect(page).toHaveURL(new RegExp(`/${name.toLowerCase()}$`));
    await expect(
      page.getByRole("heading", { name, exact: true }),
    ).toBeVisible();
    await expect(
      page.getByText("Investment content is not available yet."),
    ).toBeVisible();
    await expect(page.getByRole("link", { name, exact: true })).toHaveAttribute(
      "aria-current",
      "page",
    );
    await page.reload();
    await expect(
      page.getByRole("heading", { name, exact: true }),
    ).toBeVisible();
  }
  await page.goBack();
  await expect(
    page.getByRole("heading", { name: "Transactions", exact: true }),
  ).toBeVisible();
  await page.goForward();
  await expect(
    page.getByRole("heading", { name: "Reports", exact: true }),
  ).toBeVisible();
  await page.getByRole("link", { name: "NAVOWNER Profile" }).click();
  await expect(page).toHaveURL(/\/profile$/);
  await expect(
    page.getByRole("heading", { name: "Profile", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText("Zerodha user ID", { exact: true }),
  ).toBeVisible();
  await expect(page.getByRole("status")).toContainText("Connected to Zerodha");
});

for (const path of [
  "/",
  "/dashboard",
  "/portfolio",
  "/holdings",
  "/transactions",
  "/reports",
  "/profile",
]) {
  test(`signed-out direct entry to ${path} presents sign-in`, async ({
    page,
  }) => {
    await page.route("**/api/session", (route) =>
      route.fulfill({ json: { kind: "signed_out" } }),
    );
    await page.goto(path);
    await expect(
      page.getByRole("button", { name: "Sign in with Zerodha" }),
    ).toBeVisible();
    await expect(page.getByRole("navigation")).toHaveCount(0);
  });
}

test("navigation and Profile preserve access after broker expiry, with keyboard focus and text reflow", async ({
  page,
}) => {
  await page.route("**/api/session", (route) =>
    route.fulfill({
      json: {
        kind: "signed_in",
        userId: "NAVOWNER",
        connection: "reconnect_required",
        expiresAt: new Date(Date.now() + 86400000).toISOString(),
      },
    }),
  );
  await page.goto("/profile");
  await expect(
    page.getByRole("button", { name: "Reconnect with Zerodha" }),
  ).toBeVisible();
  const account = page.getByRole("link", { name: "NAVOWNER Profile" });
  const accountBounds = await account.boundingBox();
  expect(accountBounds?.y).toBeGreaterThan(550);
  const holdings = page.getByRole("link", { name: "Holdings", exact: true });
  await page.emulateMedia({ forcedColors: "active", reducedMotion: "reduce" });
  await holdings.focus();
  await expect(holdings).toBeFocused();
  expect(
    await holdings.evaluate(
      (element) => getComputedStyle(element).outlineStyle,
    ),
  ).toBe("solid");
  await page.keyboard.press("Enter");
  await expect(
    page.getByRole("heading", { name: "Holdings", exact: true }),
  ).toBeVisible();
  await expect(holdings).toHaveAttribute("aria-current", "page");
  await account.click();
  await page.setViewportSize({ width: 320, height: 800 });
  await page.addStyleTag({
    content:
      "html { font-size: 200%; } * { line-height: 1.5 !important; letter-spacing: 0.12em !important; word-spacing: 0.16em !important; }",
  });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(
    320,
  );
  await page
    .getByRole("button", { name: "Reconnect with Zerodha" })
    .scrollIntoViewIfNeeded();
  await expect(
    page.getByRole("button", { name: "Reconnect with Zerodha" }),
  ).toBeInViewport();
});
