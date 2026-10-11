import { test, expect } from "@playwright/test";

test("keyboard logout clears dashboard access and stale cookies", async ({ page, context }) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Sign in with Zerodha" }).click();
  await expect(page).toHaveURL(/\/dashboard$/);
  const oldCookies = await context.cookies();
  const logout = page.getByRole("button", { name: "Log out", exact: true });
  await logout.focus();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("button", { name: "Sign in with Zerodha" })).toBeVisible();
  expect((await context.cookies()).some(cookie => cookie.name === "unaru_session")).toBe(false);
  await context.addCookies(oldCookies);
  await page.reload();
  await expect(page.getByRole("button", { name: "Sign in with Zerodha" })).toBeVisible();
});
