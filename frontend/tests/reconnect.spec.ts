import { test, expect } from "@playwright/test";

test("invalidated broker reconnects without replacing dashboard login", async ({ page, context }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Sign in with Zerodha" }).click();
  await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
  const before = (await context.cookies()).find(cookie => cookie.name === "unaru_session");
  await page.request.post("/api/test/invalidate");
  await page.reload();
  await expect(page.getByRole("status")).toContainText("reconnection required");
  const reconnect = page.getByRole("button", { name: "Reconnect with Zerodha" });
  await expect(reconnect).toBeVisible();
  await reconnect.focus();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("status")).toContainText("Connected to Zerodha");
  const after = (await context.cookies()).find(cookie => cookie.name === "unaru_session");
  expect(after?.value).toBe(before?.value);
  expect(after?.expires).toBe(before?.expires);
});

test("failed reconnection preserves dashboard identity and offers retry", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Sign in with Zerodha" }).click();
  await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
  await page.request.post("/api/test/invalidate");
  for (const outcome of ["cancel", "fail", "other"]) {
    await page.route("**/api/test/kite?*", async route => {
      const target = new URL(route.request().url());
      target.searchParams.set("outcome", outcome);
      await route.continue({ url: target.toString() });
    });
    await page.reload();
    await page.getByRole("button", { name: "Reconnect with Zerodha" }).click();
    await expect(page.getByRole("alert")).toBeVisible();
    await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
    await expect(page.getByRole("button", { name: "Reconnect with Zerodha" })).toBeVisible();
    await page.unroute("**/api/test/kite?*");
  }
});
