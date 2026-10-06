"use client";

// Sharing on the web: the native share sheet (Web Share API) when available, otherwise copy to the clipboard.
// Only the text the user sees is shared — never a link to private data, never a public URL.
export async function shareText(title: string, text: string): Promise<"shared" | "copied" | "cancelled" | "failed"> {
  try {
    if (typeof navigator !== "undefined" && navigator.share) {
      await navigator.share({ title, text });
      return "shared";
    }
  } catch (e) {
    if (e instanceof DOMException && e.name === "AbortError") return "cancelled";
  }
  try {
    await navigator.clipboard.writeText(text);
    return "copied";
  } catch {
    return "failed";
  }
}
