import { test, expect } from "@playwright/test";
import { readdir, readFile } from "node:fs/promises";
const secretMarkers = [
  "browser-kite-secret-marker",
  "browser-database-password-marker",
  "browser-encryption-key-marker000",
  "browser-access-token-marker",
  "browser-request-token-marker",
];
function expectNoSecrets(value: string) {
  for (const marker of secretMarkers) expect(value).not.toContain(marker);
}

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
  expect(
    await page.evaluate(() => document.documentElement.scrollWidth),
  ).toBeLessThanOrEqual(320);
});

test("complete first login crosses the real Go API and Postgres", async ({
  page,
  context,
}) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Sign in with Zerodha" }).click();
  await expect(page).toHaveURL(/\/dashboard$/);
  await page.getByRole("link", { name: "TESTOWNER Profile" }).click();
  await expect(page.getByRole("status")).toContainText("Connected to Zerodha");
  await expect(page.getByRole("link", { name: "TESTOWNER Profile" })).toBeVisible();
  const cookies = await context.cookies();
  const session = cookies.find((cookie) => cookie.name === "unaru_session");
  expect(session?.httpOnly).toBe(true);
  expect(session?.sameSite).toBe("Lax");
  expectNoSecrets(JSON.stringify(cookies));
  expectNoSecrets(
    await page.evaluate(
      () => JSON.stringify(localStorage) + JSON.stringify(sessionStorage),
    ),
  );
  await page.reload();
  await expect(page.getByRole("link", { name: "TESTOWNER Profile" })).toBeVisible();
});

test("credentials stay out of API responses, browser state and the production bundle including exchange failure", async ({ page, context }) => {
  const responses: string[] = [];
  const observed: Promise<void>[] = [];
  page.on("response", (response) => {
    if (/^\/api\/(auth|session)/.test(new URL(response.url()).pathname)) {
      observed.push((async () => {
        // Redirect bodies can be unavailable after navigation; headers still
        // cover the callback redirect and its cookies.
        const body = await response.body().catch(() => Buffer.from(""));
        responses.push(body.toString() + JSON.stringify(await response.allHeaders()));
      })());
    }
  });
  await page.goto("/");
  await page.getByRole("button", { name: "Sign in with Zerodha" }).click();
  await expect(page.getByRole("link", { name: "TESTOWNER Profile" })).toBeVisible();
  await page.getByRole("link", { name: "TESTOWNER Profile" }).click();
  await page.getByRole("button", { name: "Log out", exact: true }).click();
  await expect(page.getByRole("button", { name: "Sign in with Zerodha" })).toBeVisible();
  await page.route("**/api/test/kite?*", (route) => {
    const target = new URL(route.request().url());
    target.searchParams.set("outcome", "fail");
    return route.continue({ url: target.href });
  });
  await page.getByRole("button", { name: "Sign in with Zerodha" }).click();
  await expect(page.getByRole("alert")).toContainText("could not be completed");
  await Promise.all(observed);
  expectNoSecrets(responses.join("\n"));
  expectNoSecrets(JSON.stringify(await context.storageState()));
  expectNoSecrets(await page.evaluate(() => JSON.stringify(localStorage) + JSON.stringify(sessionStorage)));
  expectNoSecrets(await page.content());
  const assets = await readdir("dist/assets");
  for (const asset of assets) expectNoSecrets(await readFile(`dist/assets/${asset}`, "utf8"));
});
