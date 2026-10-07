// SpenDrop AI preferences, kept on this device like the other display preferences (appearance, sidebar). They change
// presentation only — never who the user is or what data the AI can read (that comes from the signed-in session and
// Row Level Security on the server). Stored as one object so future AI settings can be added with their own default.
import { useStored } from "@/lib/use-stored";

export const AI_SETTINGS_KEY = "spendrop-ai-settings";

export interface AiSettings {
  /** The floating SpenDrop AI robot (a shortcut to Ask SpenDrop). */
  floatingAssistant: boolean;
  /** Use the user's first name in SpenDrop AI screens (greeting, tooltip). Presentation only. */
  showMyName: boolean;
}

export const DEFAULT_AI_SETTINGS: AiSettings = { floatingAssistant: true, showMyName: true };

export function useAiSettings(): [AiSettings, (patch: Partial<AiSettings>) => void] {
  const [settings, store] = useStored<AiSettings>("local", AI_SETTINGS_KEY, DEFAULT_AI_SETTINGS);
  return [settings, (patch) => store({ ...settings, ...patch })];
}

/** A friendly first name: the profile name's first word, else the email's local part without digits ("rukon6950" → "Rukon"). */
export function firstName(displayName: string | null | undefined, email: string | null | undefined): string | null {
  const fromName = displayName?.trim().split(/\s+/)[0];
  if (fromName) return fromName.slice(0, 24);
  const local = email?.split("@")[0]?.split(/[._+-]/)[0]?.replace(/\d+$/, "");
  if (!local || local.length < 2 || !/^\p{L}+$/u.test(local)) return null;
  return (local.charAt(0).toUpperCase() + local.slice(1)).slice(0, 24);
}
