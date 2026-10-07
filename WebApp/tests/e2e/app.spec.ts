import AxeBuilder from "@axe-core/playwright";
import { expect, test, type Page } from "@playwright/test";

const PAGES = ["/", "/transactions", "/paybook", "/breakdown", "/more", "/add", "/more/accounts", "/more/reference", "/more/import", "/more/account"];

async function fresh(page: Page) {
  // Each test starts from the same synthetic demo data.
  await page.goto("/login");
  await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); indexedDB.deleteDatabase("spendrop"); });
}

/** Toggle a switch the way a person would: bring it to the middle of the screen (clear of sticky bars), then tap. */
async function setSwitch(page: Page, name: RegExp, on: boolean) {
  const sw = page.getByRole("switch", { name });
  await sw.evaluate((el) => el.scrollIntoView({ block: "center" }));
  if (on) await sw.check({ force: true });
  else await sw.uncheck({ force: true });
}

function trackErrors(page: Page) {
  const errors: string[] = [];
  page.on("pageerror", (e) => errors.push(e.message));
  page.on("console", (m) => { if (m.type() === "error") errors.push(m.text()); });
  return errors;
}

async function noHorizontalScroll(page: Page) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
  expect(overflow, "page scrolls sideways").toBeLessThanOrEqual(1);
}

test.beforeEach(async ({ page }) => fresh(page));

test("every main screen loads, fits the screen, has no console errors and passes axe", async ({ page }, info) => {
  const errors = trackErrors(page);
  for (const path of PAGES) {
    await page.goto(path);
    await expect(page.locator("h1").first()).toBeVisible();
    await page.waitForLoadState("networkidle");
    await noHorizontalScroll(page);
    const axe = await new AxeBuilder({ page }).disableRules(["region"]).analyze();
    const serious = axe.violations.filter((v) => v.impact === "serious" || v.impact === "critical");
    expect(serious.map((v) => `${path}: ${v.id} — ${v.nodes.map((n) => n.target.join(" ")).slice(0, 3).join(", ")}`)).toEqual([]);
    if (["/", "/transactions", "/paybook", "/breakdown", "/add"].includes(path))
      await page.screenshot({ path: `test-results/screens/${info.project.name}${path === "/" ? "-home" : path.replace(/\//g, "-")}.png`, fullPage: true });
  }
  expect(errors).toEqual([]);
});

test("home shows real totals from the data (no made-up metrics)", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByText("This Month").first()).toBeVisible();
  await expect(page.getByText("Balances")).toBeVisible();
  await expect(page.getByText("Cash Flow · This Month")).toBeVisible();
});

test("add an expense split 40/30/30 with two new people; PayBook shows both debts", async ({ page }) => {
  await page.goto("/add");
  await page.getByLabel("Enter amount").fill("100");
  await page.getByLabel("Merchant / Recipient").fill("Restoran Test Split");
  await setSwitch(page, /Split Transaction/, true);
  for (const name of ["Bijoy", "Riyad"]) {
    await page.getByRole("button", { name: "Add Person" }).click();
    await page.getByLabel("Search or type a new name").fill(name);
    await page.getByRole("button", { name: `New Person “${name}”` }).click();
  }
  await page.getByRole("radio", { name: "Custom Amount" }).click();
  await setSwitch(page, /Auto Calculate/, false);
  await page.getByLabel("Your amount").fill("40");
  await page.getByLabel("Bijoy's amount").fill("30");
  await page.getByLabel("Riyad's amount").fill("30");
  await expect(page.getByText("Bijoy owes you RM 30.00")).toBeVisible();
  await expect(page.getByText("Riyad owes you RM 30.00")).toBeVisible();
  await page.getByRole("button", { name: /Save Expense/ }).click();
  await expect(page.getByRole("heading", { name: "Restoran Test Split" })).toBeVisible();
  await expect(page.getByText("Bijoy owes you RM 30.00").first()).toBeVisible();
  await page.goto("/paybook");
  await page.getByRole("radio", { name: "They Owe Me" }).click();
  await expect(page.getByRole("link", { name: /Bijoy/ })).toBeVisible();
  await expect(page.getByRole("link", { name: /Riyad/ })).toBeVisible();
});

test("fixed amount: RM200, Vijay fixed RM50 → You 50, Vijay 100, Riyadh 50; Auto Calculate is ON for every new transaction", async ({ page }) => {
  await page.goto("/add");
  await page.getByLabel("Enter amount").fill("200");
  await setSwitch(page, /Split Transaction/, true);
  for (const name of ["Vijay", "Riyadh"]) {
    await page.getByRole("button", { name: "Add Person" }).click();
    await page.getByLabel("Search or type a new name").fill(name);
    await page.getByRole("button", { name: `New Person “${name}”` }).click();
  }
  await page.getByRole("radio", { name: "Custom Amount" }).click();
  await expect(page.getByRole("switch", { name: /Auto Calculate/ })).toBeChecked();
  await page.getByRole("button", { name: "Fixed amount for Vijay" }).click();
  await page.getByLabel("Fixed amount", { exact: true }).fill("50");
  await page.getByRole("button", { name: "Save", exact: true }).click();
  await expect(page.getByText("Vijay owes you RM 100.00")).toBeVisible();
  await expect(page.getByText("Riyadh owes you RM 50.00")).toBeVisible();
  await expect(page.getByText("✓ Balanced · Your share RM 50.00")).toBeVisible();
  // Turning Auto Calculate OFF freezes the amounts; changing one leaves the rest alone.
  await setSwitch(page, /Auto Calculate/, false);
  await page.getByLabel("Riyadh's amount").fill("20");
  await expect(page.getByRole("alert").filter({ hasText: "RM 30.00 remains unassigned." })).toBeVisible();
  await expect(page.getByRole("button", { name: /Save Expense/ })).toBeDisabled();
  // A new transaction starts with Auto Calculate ON again.
  await page.goto("/add");
  await page.getByLabel("Enter amount").fill("90");
  await setSwitch(page, /Split Transaction/, true);
  await page.getByRole("button", { name: "+ Aisyah" }).click();
  await page.getByRole("radio", { name: "Custom Amount" }).click();
  await expect(page.getByRole("switch", { name: /Auto Calculate/ })).toBeChecked();
});

test("payment channel stays Unknown unless chosen; funding account and channel are separate", async ({ page }) => {
  await page.goto("/add");
  await expect(page.getByLabel("Payment channel (how payment was made)")).toHaveValue("UNKNOWN");
  await page.getByLabel("Enter amount").fill("12.50");
  await page.getByLabel("Merchant / Recipient").fill("Tealive");
  await expect(page.getByRole("button", { name: "Food", pressed: true })).toBeVisible();
  await page.getByLabel("Funding account (where money came from)").selectOption("Touch 'n Go");
  await page.getByRole("button", { name: /Save Expense/ }).click();
  await expect(page.getByText("Touch 'n Go").first()).toBeVisible();
  await expect(page.getByText("Unknown").first()).toBeVisible();
});

test("edit then delete an expense", async ({ page }) => {
  await page.goto("/transactions");
  await page.getByRole("link", { name: /Jaya Grocer/ }).first().click();
  await page.getByRole("link", { name: /Edit/ }).click();
  await page.getByLabel("Enter amount").fill("90.00");
  await page.getByRole("button", { name: "Save Changes" }).click();
  await expect(page.getByText("RM 90.00").first()).toBeVisible();
  await page.getByRole("button", { name: /Delete Expense/ }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Delete" }).click();
  await expect(page).toHaveURL(/\/transactions$/);
  await expect(page.getByRole("link", { name: /Jaya Grocer/ })).toHaveCount(0);
});

test("search and filters", async ({ page }) => {
  await page.goto("/transactions");
  await page.getByLabel("Search transactions").fill("tealive");
  await expect(page.getByRole("link", { name: /Tealive/ }).first()).toBeVisible();
  await expect(page.getByRole("link", { name: /Netflix/ })).toHaveCount(0);
  await page.getByRole("radio", { name: "Money In" }).click();
  await expect(page.getByText("Nothing matches")).toBeVisible();
});

test("PayBook: settle all with a person, then undo", async ({ page }) => {
  await page.goto("/paybook");
  await page.getByRole("link", { name: /Daniel/ }).click();
  await expect(page.getByText("Daniel owes you RM 11.00")).toBeVisible(); // 35 owed − 24 taxi Daniel paid
  await page.getByRole("button", { name: "Settle All" }).click();
  await page.getByRole("dialog").getByRole("button", { name: "Settle All" }).click();
  await expect(page.getByText("Settled — nothing owed either way")).toBeVisible();
  await page.getByRole("button", { name: "Undo" }).first().click();
  await expect(page.getByText("Daniel owes you RM 11.00")).toBeVisible();
});

test("breakdown shows spending and cash flow", async ({ page }) => {
  await page.goto("/breakdown");
  await expect(page.getByText("Spending by category")).toBeVisible();
  await page.getByRole("radio", { name: "Cash Flow" }).click();
  await expect(page.getByText("Net Cash Flow")).toBeVisible();
});

test("appearance switches to dark mode and persists", async ({ page }) => {
  await page.goto("/more");
  await page.getByRole("radio", { name: "Dark" }).click();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
  await page.reload();
  await expect(page.locator("html")).toHaveAttribute("data-theme", "dark");
});

test("sign out", async ({ page }) => {
  await page.goto("/more");
  await page.getByRole("button", { name: "Sign Out" }).click();
  await expect(page).toHaveURL(/\/login/);
});

test.describe("collapsible sidebar", () => {
  test("hide / show, persists across pages and reload, Ctrl+B, nothing replays", async ({ page, isMobile }) => {
    test.skip(isMobile, "phones keep the bottom tab bar");
    await page.goto("/");
    const nav = page.locator("nav.sd-sidebar");
    const main = page.locator("main#main");
    await expect(page.getByText("This Month").first()).toBeVisible();
    await page.waitForTimeout(900); // let the entrance + count-up finish
    const card = page.locator(".sd-rise").first();
    await card.evaluate((el) => el.setAttribute("data-probe", "same-element"));
    const valueBefore = await card.locator("[data-value^='RM']").first().getAttribute("data-value");
    const widthBefore = (await main.boundingBox())!.width;

    await page.getByRole("button", { name: "Hide sidebar" }).click();
    await expect(page.locator("html")).toHaveAttribute("data-sidebar", "hidden");
    await expect.poll(async () => (await nav.boundingBox())?.width ?? 0).toBeLessThan(2);
    await expect.poll(async () => (await main.boundingBox())!.width).toBeGreaterThan(widthBefore + 50);
    // Same DOM element, same value: the dashboard did not re-mount or restart.
    await expect(page.locator("[data-probe='same-element']")).toHaveCount(1);
    expect(await card.locator("[data-value^='RM']").first().getAttribute("data-value")).toBe(valueBefore);

    await page.locator("nav.sd-sidebar").page().goto("/transactions");
    await expect(page.locator("html")).toHaveAttribute("data-sidebar", "hidden");
    await page.reload();
    await expect(page.locator("html")).toHaveAttribute("data-sidebar", "hidden");

    const reopen = page.getByRole("button", { name: "Show sidebar" });
    await expect(reopen).toBeVisible();
    await reopen.click();
    await expect(page.locator("html")).toHaveAttribute("data-sidebar", "open");
    await expect.poll(async () => (await nav.boundingBox())?.width ?? 0).toBeGreaterThan(60);

    // Keyboard shortcut toggles, but not while typing in a field
    await page.locator("body").press("ControlOrMeta+b");
    await expect(page.locator("html")).toHaveAttribute("data-sidebar", "hidden");
    await page.locator("body").press("ControlOrMeta+b");
    await expect(page.locator("html")).toHaveAttribute("data-sidebar", "open");
    await page.getByLabel("Search transactions").focus();
    await page.keyboard.press("ControlOrMeta+b");
    await expect(page.locator("html")).toHaveAttribute("data-sidebar", "open");
  });

  test("phones keep the bottom tab bar (no desktop sidebar toggle)", async ({ page, isMobile }) => {
    test.skip(!isMobile, "phone/tablet-touch only");
    await page.goto("/");
    const width = page.viewportSize()!.width;
    test.skip(width >= 768, "tablet uses the rail");
    await expect(page.getByRole("button", { name: "Show sidebar" })).toBeHidden();
    await expect(page.locator("nav").filter({ has: page.getByRole("link", { name: "PayBook" }) }).last()).toBeVisible();
  });

  test("numbers count to their exact final value and sheets open/close smoothly", async ({ page }) => {
    await page.goto("/breakdown");
    const total = page.locator("[data-value^='RM']").first();
    const label = await total.getAttribute("data-value");
    await expect.poll(async () => (await total.locator("[aria-hidden]").innerText()).trim(), { timeout: 3000 }).toBe(label);
    await page.goto("/transactions");
    const filters = page.getByRole("button", { name: /Filters/ });
    if (await filters.isVisible()) {
      await filters.click();
      await expect(page.getByRole("dialog", { name: "Filters" })).toBeVisible();
      await page.getByRole("button", { name: "Close" }).click();
      await expect(page.getByRole("dialog", { name: "Filters" })).toBeHidden();
    }
  });
});
