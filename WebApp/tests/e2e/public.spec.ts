import AxeBuilder from "@axe-core/playwright";
import { expect, test } from "@playwright/test";

// Signed-out checks that are safe to run against production: no account is created or used.
test.describe("@public", () => {
  test("signed-out visitors are sent to sign-in, keeping where they were going", async ({ page }) => {
    await page.goto("/transactions");
    await page.waitForLoadState("networkidle");
    if (await page.getByRole("note").filter({ hasText: "Demo" }).count()) test.skip(true, "demo build has no sign-in");
    await expect(page).toHaveURL(/\/login(\?next=%2Ftransactions)?$/);
    await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
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

  test("sign-in screens: password eye, Create Account, Forgot Password, validation (no requests sent)", async ({ page }) => {
    await page.goto("/login");
    await page.getByRole("button", { name: /Continue with Google|Open the demo/ }).or(page.getByRole("link", { name: "Open the demo" })).waitFor();
    if ((await page.getByLabel("Email").count()) === 0) test.skip(true, "demo build has no sign-in form");
    const password = page.getByLabel("Password", { exact: true });
    await password.fill("secret-pass");
    await expect(password).toHaveAttribute("type", "password");
    await page.getByRole("button", { name: "Show password" }).click();
    await expect(password).toHaveAttribute("type", "text");
    await expect(page.getByRole("button", { name: "Hide password" })).toHaveAttribute("aria-pressed", "true");

    // Create Account (desktop: the panels slide; phone: the link under the form)
    const toSignUp = page.getByRole("button", { name: /Start using SpenDrop|Create account/ }).filter({ visible: true }).first();
    await toSignUp.click();
    await expect(page.getByRole("heading", { name: "Create your account" })).toBeVisible();
    await page.getByLabel("Email").fill("someone@example.com");
    await page.getByLabel("Password", { exact: true }).fill("password-one");
    await page.getByLabel("Confirm password").fill("password-two");
    await page.getByRole("button", { name: "Create Account", exact: true }).click();
    await expect(page.getByText("Passwords don't match.")).toBeVisible();
    await expect(page).toHaveURL(/mode=signup/);

    // Back to Sign In, then Forgot Password
    await page.getByRole("button", { name: /^(Sign In|Sign in)$/ }).filter({ visible: true }).first().click();
    await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
    await page.getByRole("button", { name: "Forgot password?" }).click();
    await expect(page.getByRole("heading", { name: "Reset your password" })).toBeVisible();
    await page.getByLabel("Email").fill("not-an-email"); // invalid on purpose: nothing may be sent to the server
    await page.getByRole("button", { name: "Send Reset Link" }).click();
    await expect(page.getByText("Enter a valid email address.")).toBeVisible();
    await page.getByRole("button", { name: /Back to Sign In|^Sign in$/ }).filter({ visible: true }).first().click();
    await expect(page.getByRole("heading", { name: "Sign in" })).toBeVisible();
  });

  test("keyboard: Google, then email, password, show-password, forgot, submit", async ({ page, isMobile }) => {
    test.skip(isMobile, "keyboard order checked on desktop");
    await page.goto("/login");
    await page.getByRole("button", { name: /Continue with Google|Open the demo/ }).or(page.getByRole("link", { name: "Open the demo" })).waitFor();
    if ((await page.getByLabel("Email").count()) === 0) test.skip(true, "demo build has no sign-in form");
    await page.getByRole("button", { name: "Continue with Google" }).focus();
    await page.keyboard.press("Tab");
    await expect(page.getByLabel("Email")).toBeFocused();
    await page.keyboard.press("Tab");
    await expect(page.getByLabel("Password", { exact: true })).toBeFocused();
  });

  test("reduced motion turns the slide off", async ({ browser }) => {
    const ctx = await browser.newContext({ reducedMotion: "reduce", viewport: { width: 1280, height: 860 } });
    const page = await ctx.newPage();
    await page.goto("/login");
    const panel = page.locator("section").first();
    await panel.waitFor();
    const duration = await panel.evaluate((el) => parseFloat(getComputedStyle(el).transitionDuration) || 0);
    expect(duration).toBeLessThan(0.05);
    await ctx.close();
  });

  test("offline page and manifest are available", async ({ page, request }) => {
    await page.goto("/offline");
    await expect(page.getByRole("heading", { name: "You're offline" })).toBeVisible();
    const manifest = await (await request.get("/manifest.webmanifest")).json();
    expect(manifest).toMatchObject({ name: "SpenDrop", display: "standalone", start_url: "/" });
  });
});
