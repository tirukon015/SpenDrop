import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

// Signed-out checks that are safe to run against production: no account is created or used.
test.describe("@public", () => {
  test("signed-out visitors are sent to sign-in, keeping where they were going", async ({ page }) => {
    await page.goto("/transactions");
    await page.waitForLoadState("networkidle");
    if (await page.getByRole("note").filter({ hasText: "Demo" }).count()) test.skip(true, "demo build has no sign-in");
    await expect(page).toHaveURL(/\/login(\?next=%2Ftransactions)?$/);
    await expect(page.getByRole("heading", { name: "SpenDrop" })).toBeVisible();
  });

  test("sign-in page renders, fits the screen and passes axe", async ({ page }) => {
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto("/login");
    await expect(page.getByRole("button", { name: /Continue with Google|Open the demo/ }).or(page.getByRole("link", { name: "Open the demo" }))).toBeVisible();
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
    expect(overflow).toBeLessThanOrEqual(1);
    const axe = await new AxeBuilder({ page }).disableRules(["region"]).analyze();
    expect(axe.violations.filter((v) => v.impact === "serious" || v.impact === "critical").map((v) => v.id)).toEqual([]);
    expect(errors).toEqual([]);
  });

  test("email form validates before contacting the server", async ({ page }) => {
    await page.goto("/login");
    await page.getByRole("button", { name: /Continue with Google|Open the demo/ }).or(page.getByRole("link", { name: "Open the demo" })).waitFor();
    const email = page.getByLabel("Email");
    if ((await email.count()) === 0) test.skip(true, "demo build has no sign-in form");
    await email.fill("not-an-email");
    await page.getByLabel("Password", { exact: true }).fill("short");
    await page.getByRole("button", { name: "Sign In", exact: true }).click();
    await expect(page.getByText("Enter a valid email address.")).toBeVisible();
  });

  test("offline page and manifest are available", async ({ page, request }) => {
    await page.goto("/offline");
    await expect(page.getByRole("heading", { name: "You're offline" })).toBeVisible();
    const manifest = await (await request.get("/manifest.webmanifest")).json();
    expect(manifest).toMatchObject({ name: "SpenDrop", display: "standalone", start_url: "/" });
  });
});
