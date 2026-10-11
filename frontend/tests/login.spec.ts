import { test, expect } from "@playwright/test";
test("sign-in supports keyboard, exact referral and narrow screens", async ({
  page,
}) => {
  await page.route("**/api/session", (route) =>
    route.fulfill({ json: { kind: "signed_out" } }),
  );
  await page.route("**/api/auth/login", (route) =>
    route.fulfill({ status: 503, json: { error: "service_unavailable" } }),
  );
  await page.goto("/");
  const login = page.getByRole("button", { name: "Sign in with Zerodha" });
  await expect(login).toBeVisible();
  await expect(page.getByRole("link", { name: "Sign up" })).toHaveAttribute(
    "href",
    "https://zerodha.com/open-account?c=SH1331",
  );
  await page.keyboard.press("Tab");
  await expect(login).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(page.getByRole("alert")).toContainText("could not start");
  await page.setViewportSize({ width: 320, height: 640 });
  await expect(login).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(
    320,
  );
});

test("complete first login crosses the real Go API and Postgres", async ({
  page,
  context,
}) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Sign in with Zerodha" }).click();
  await expect(page).toHaveURL(/\/dashboard$/);
  await expect(page.getByRole("status")).toContainText("Connected to Zerodha");
  await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
  const cookies = await context.cookies();
  const session = cookies.find((cookie) => cookie.name === "unaru_session");
  expect(session?.httpOnly).toBe(true);
  expect(session?.sameSite).toBe("Lax");
  expect(session?.value).not.toContain("secret");
  expect(
    await page.evaluate(
      () => JSON.stringify(localStorage) + JSON.stringify(sessionStorage),
    ),
  ).not.toContain("secret");
  await page.reload();
  await expect(page.getByText("Signed in as TESTOWNER")).toBeVisible();
});
