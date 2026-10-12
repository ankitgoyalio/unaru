import { test, expect } from "@playwright/test";

for (const identity of [
  { displayName: "Ankit Goyal", label: "Ankit Goyal" },
  { displayName: undefined, label: "NAMEOWNER" },
  { displayName: "", label: "NAMEOWNER" },
  { displayName: " \t ", label: "NAMEOWNER" },
]) {
  for (const connection of ["active", "reconnect_required"]) {
    test(`identity ${JSON.stringify(identity.displayName)} remains visible with ${connection}`, async ({ page }) => {
      await page.route("**/api/session", (route) => route.fulfill({
        json: {
          kind: "signed_in",
          userId: "NAMEOWNER",
          displayName: identity.displayName,
          connection,
          expiresAt: new Date(Date.now() + 86400000).toISOString(),
        },
      }));
      await page.goto("/dashboard");
      const account = page.getByRole("link", { name: `${identity.label} Profile`, exact: true });
      await expect(account).toBeVisible();
      await account.click();
      await expect(page.getByRole("heading", { name: "Profile", exact: true })).toBeVisible();
      const details = page.getByRole("region", { name: "Account details" });
      await expect(details.getByText(identity.label, { exact: true }).first()).toBeVisible();
      await expect(details.getByText("NAMEOWNER", { exact: true }).last()).toBeVisible();
      await expect(details.getByText("Name", { exact: true })).toBeVisible();
      if (connection === "reconnect_required") {
        await expect(page.getByRole("button", { name: "Reconnect with Zerodha" })).toBeVisible();
      }
      await page.reload();
      await expect(account).toBeVisible();
    });
  }
}
