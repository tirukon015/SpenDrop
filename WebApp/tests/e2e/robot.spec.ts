// The floating SpenDrop AI robot: a shortcut to /ask, never a second chat. Checked on phone / tablet / laptop /
// desktop (the Playwright projects) plus the extra phone widths 320 / 375 / 390 / 430.
import { expect, test, type Page } from "@playwright/test";

const robot = (page: Page) => page.getByRole("link", { name: "Ask SpenDrop AI" });

test.beforeEach(async ({ page }) => {
  await page.goto("/login");
  await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); indexedDB.deleteDatabase("spendrop"); });
});

const box = async (page: Page, sel: string) => page.locator(sel).first().boundingBox();
const overlaps = (a: { x: number; y: number; width: number; height: number } | null, b: { x: number; y: number; width: number; height: number } | null) =>
  !!a && !!b && a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;

test("robot: visible on app screens, never on sign-in or /ask, opens Ask SpenDrop without a reload", async ({ page }) => {
  await page.goto("/");
  await expect(robot(page)).toBeVisible();
  const img = robot(page).locator("img");
  await expect(img).toHaveAttribute("src", /spendrop-robot/);
  // the whole image is shown (object-fit: contain) inside a touch target of at least 44px
  const b = await robot(page).boundingBox();
  expect(b!.width).toBeGreaterThanOrEqual(56);
  expect(await img.evaluate((el) => getComputedStyle(el).objectFit)).toBe("contain");
  // client-side navigation (no full reload): a marker on window survives
  await page.evaluate(() => { (window as unknown as { __noReload: boolean }).__noReload = true; });
  await robot(page).click();
  await expect(page).toHaveURL(/\/ask$/);
  await expect(page.getByRole("heading", { name: "Ask SpenDrop" })).toBeVisible();
  expect(await page.evaluate(() => (window as unknown as { __noReload?: boolean }).__noReload)).toBe(true);
  await expect(robot(page)).toHaveCount(0);
  await page.goto("/add");
  await expect(robot(page)).toHaveCount(0);
  await page.goto("/login");
  await expect(robot(page)).toHaveCount(0);
});

test("robot: keyboard operable", async ({ page }, info) => {
  test.skip(info.project.name === "phone" || info.project.name === "tablet", "keyboard focus check on pointer devices");
  await page.goto("/transactions");
  await robot(page).focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL(/\/ask$/);
});

test("robot: never covers the tab bar, the Add button or the sidebar, at every width", async ({ page }, info) => {
  const widths = info.project.name === "phone" ? [320, 375, 390, 430] : [page.viewportSize()!.width];
  for (const w of widths) {
    await page.setViewportSize({ width: w, height: page.viewportSize()!.height });
    for (const path of ["/", "/transactions", "/more"]) {
      await page.goto(path);
      await expect(robot(page)).toBeVisible();
      const r = await robot(page).boundingBox();
      expect(r!.x + r!.width, `${w}px ${path}: inside the screen`).toBeLessThanOrEqual(w);
      if (w < 768) {
        expect(overlaps(r, await box(page, 'nav[aria-label="Main"]:visible')), `${w}px ${path}: tab bar`).toBe(false);
        expect(overlaps(r, await box(page, 'a[aria-label="Add transaction"]:visible')), `${w}px ${path}: Add button`).toBe(false);
      }
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      expect(overflow).toBeLessThanOrEqual(1);
    }
  }
});

test("settings: Floating AI Assistant hides the robot; Show My Name changes only what's shown", async ({ page }) => {
  await page.goto("/more");
  const floating = page.getByRole("switch", { name: /Floating AI Assistant/ });
  const name = page.getByRole("switch", { name: /Show My Name/ });
  await expect(floating).toBeChecked();
  await expect(name).toBeChecked();
  await floating.evaluate((el) => el.scrollIntoView({ block: "center" }));
  await floating.uncheck({ force: true });
  await expect(robot(page)).toHaveCount(0);
  await page.reload();
  await expect(page.getByRole("switch", { name: /Floating AI Assistant/ })).not.toBeChecked(); // remembered
  await expect(robot(page)).toHaveCount(0);

  // Show My Name: the Ask greeting uses the first name only when on
  await page.goto("/ask");
  await expect(page.getByRole("heading", { name: /^Hi Demo! Ask anything about your money/ })).toBeVisible();
  await page.goto("/more");
  await name.evaluate((el) => el.scrollIntoView({ block: "center" }));
  await name.uncheck({ force: true });
  await page.goto("/ask");
  await expect(page.getByRole("heading", { name: /^Ask anything about your money/ })).toBeVisible();
  await expect(page.getByText("Hi Demo")).toHaveCount(0);
});

test("robot: hidden while a modal sheet is open; still on top of page content otherwise", async ({ page }) => {
  await page.goto("/ask");
  await page.goto("/transactions");
  await expect(robot(page)).toBeVisible();
  await page.evaluate(() => { const d = document.createElement("dialog"); d.id = "t"; document.body.appendChild(d); d.showModal(); });
  await expect(robot(page)).toBeHidden();
  await page.evaluate(() => (document.getElementById("t") as HTMLDialogElement).close());
  await expect(robot(page)).toBeVisible();
});

test("robot: no float animation with reduced motion", async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: "reduce" });
  const page = await context.newPage();
  await page.goto("/");
  await expect(robot(page)).toBeVisible();
  expect(await robot(page).locator(".sd-robot-float").evaluate((el) => getComputedStyle(el).animationName)).toBe("none");
  await context.close();
});
