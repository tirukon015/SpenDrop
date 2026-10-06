// Appearance like iOS Settings → Appearance: System (default), Light, Dark. Stored per browser.
export type Appearance = "system" | "light" | "dark";
export const APPEARANCE_KEY = "spendrop-appearance";

/** Inline script: resolves the stored choice (or the system setting) into html[data-theme] before paint. */
export const themeScript = `(function(){try{var a=(localStorage.getItem('${APPEARANCE_KEY}')||'system').replace(/"/g,'');var d=a==='dark'||(a==='system'&&matchMedia('(prefers-color-scheme: dark)').matches);document.documentElement.dataset.theme=d?'dark':'light';}catch(e){document.documentElement.dataset.theme='light';}})();`;

export function applyAppearance(appearance: Appearance) {
  const dark = appearance === "dark" || (appearance === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.dataset.theme = dark ? "dark" : "light";
  document.querySelector('meta[name="theme-color"]')?.setAttribute("content", dark ? "#000000" : "#f2f2f7");
}

export function readAppearance(): Appearance {
  try {
    const raw = localStorage.getItem(APPEARANCE_KEY) ?? "";
    const value = raw.startsWith('"') ? JSON.parse(raw) : raw;
    return value === "light" || value === "dark" ? value : "system";
  } catch {
    return "system";
  }
}

export function saveAppearance(appearance: Appearance) {
  try {
    localStorage.setItem(APPEARANCE_KEY, JSON.stringify(appearance));
  } catch {}
  window.dispatchEvent(new CustomEvent("spendrop-storage", { detail: APPEARANCE_KEY }));
  applyAppearance(appearance);
}
