import { defineConfig } from "@playwright/test";
export default defineConfig({
  testDir: "./tests",
  // Browser scenarios share one single-account installation and fake broker.
  workers: 1,
  use: { baseURL: "http://127.0.0.1:5173", headless: true },
  webServer: [
    {
      command: "cd ../backend && go run ./cmd/testserver",
      url: "http://127.0.0.1:8080/api/session",
      reuseExistingServer: false,
    },
    {
      command: "pnpm dev",
      url: "http://127.0.0.1:5173",
      reuseExistingServer: false,
    },
  ],
  projects: [{ name: "chromium", use: { browserName: "chromium" } }],
});
