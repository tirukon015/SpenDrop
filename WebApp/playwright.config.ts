import { defineConfig, devices } from "@playwright/test";

// End-to-end tests against the production build in DEMO mode (synthetic data in the browser, no Supabase).
// Run: npm run test:e2e   (builds + starts the app on :3100 automatically, or reuses a running one)
export default defineConfig({
  testDir: "tests/e2e",
  timeout: 60_000,
  fullyParallel: true,
  reporter: [["list"]],
  // E2E_BASE_URL=https://spendrop.vercel.app npx playwright test -g @public  → checks the live site (no sign-in).
  use: { baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3100", trace: "retain-on-failure" },
  webServer: process.env.E2E_BASE_URL ? undefined : {
    command: "NEXT_PUBLIC_SPENDROP_DEMO=1 npm run build && NEXT_PUBLIC_SPENDROP_DEMO=1 npx next start -p 3100",
    url: "http://localhost:3100/login",
    reuseExistingServer: true,
    timeout: 300_000,
  },
  projects: [
    { name: "phone", use: { ...devices["iPhone 15"], browserName: "chromium" } },
    { name: "tablet", use: { viewport: { width: 820, height: 1180 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 } },
    { name: "laptop", use: { viewport: { width: 1366, height: 900 } } },
    { name: "desktop", use: { viewport: { width: 1920, height: 1080 } } },
  ],
});
