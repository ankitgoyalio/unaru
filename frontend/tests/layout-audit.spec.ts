import { test, expect } from "@playwright/test";

test("enlarged drawer destination labels and focus outlines fit their scroll ancestors", async ({ page }) => {
  await page.route("**/api/session", (route) => route.fulfill({ json: {
    kind: "signed_in", userId: "DRAWEROWNER",
    displayName: "VERYLONGIDENTITYWITHOUTSPACESFORREFLOW",
    connection: "reconnect_required",
    expiresAt: new Date(Date.now() + 86400000).toISOString(),
  } }));
  await page.setViewportSize({ width: 320, height: 568 });
  await page.emulateMedia({ forcedColors: "active", reducedMotion: "reduce" });
  await page.goto("/profile");
  await page.addStyleTag({ content: "html { font-size: 200%; } * { line-height: 1.5 !important; letter-spacing: 0.12em !important; word-spacing: 0.16em !important; } p { margin-block-end: 2em !important; }" });
  await page.getByRole("button", { name: "Menu", exact: true }).click();
  const drawer = page.getByRole("dialog", { name: "Navigation" });
  for (const name of ["Dashboard", "Portfolio", "Holdings", "Transactions", "Reports"]) {
    const link = drawer.getByRole("link", { name, exact: true });
    await link.focus();
    await expect(link).toBeFocused();
    const clipping = await link.evaluate((element) => {
      const bounds = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      const ring = Number.parseFloat(style.outlineWidth) + Number.parseFloat(style.outlineOffset);
      const clippedBy: string[] = [];
      for (let parent = element.parentElement; parent; parent = parent.parentElement) {
        const overflow = getComputedStyle(parent).overflowY;
        if (["auto", "scroll", "hidden", "clip"].includes(overflow)) {
          const clip = parent.getBoundingClientRect();
          if (bounds.top - ring < clip.top + parent.clientTop - 1 || bounds.bottom + ring > clip.top + parent.clientTop + parent.clientHeight + 1) clippedBy.push(parent.tagName);
        }
      }
      return clippedBy;
    });
    expect(clipping, `${name} must be readable inside each scrolling ancestor`).toEqual([]);
  }
  const account = drawer.getByRole("link", { name: "VERYLONGIDENTITYWITHOUTSPACESFORREFLOW Profile" });
  await account.focus();
  await expect(account).toBeFocused();
  await expect(account.getByText("Profile", { exact: true })).toBeInViewport();
  expect(await drawer.evaluate((element) => element.scrollWidth)).toBeLessThanOrEqual(320);
});
