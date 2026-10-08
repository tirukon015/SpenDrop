"use client";

// The floating SpenDrop AI robot: only a shortcut to the existing Ask SpenDrop screen (/ask). It has no chat, AI or
// state of its own. Shown on signed-in app screens once the user's data source is ready (never on sign-in, never
// flashing while the session loads), hidden while typing on a phone (the keyboard is up), on screens with their own
// bottom controls (Add, Ask) and whenever a modal sheet is open (CSS: body:has(dialog[open])).
import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { useData } from "@/components/providers/data-provider";
import { firstName, useAiSettings } from "@/lib/ai-settings";

/** Screens where the robot would cover the screen's own controls. */
const HIDDEN_ON = [/^\/ask(\/|$)/, /^\/add(\/|$)/];

/** True while a text field has focus on a touch device (the on-screen keyboard is likely up). */
function useTyping() {
  const [typing, setTyping] = useState(false);
  useEffect(() => {
    const coarse = window.matchMedia("(pointer: coarse)");
    const isField = (el: EventTarget | null) =>
      el instanceof HTMLElement && (el.isContentEditable || el.tagName === "TEXTAREA" || el.tagName === "SELECT" || (el.tagName === "INPUT" && !["checkbox", "radio", "button", "submit", "range"].includes((el as HTMLInputElement).type)));
    const onIn = (e: FocusEvent) => { if (coarse.matches && isField(e.target)) setTyping(true); };
    const onOut = () => setTyping(false);
    document.addEventListener("focusin", onIn);
    document.addEventListener("focusout", onOut);
    return () => { document.removeEventListener("focusin", onIn); document.removeEventListener("focusout", onOut); };
  }, []);
  return typing;
}

export function FloatingSpenDropAI() {
  const pathname = usePathname();
  const { source } = useData();
  const [settings] = useAiSettings();
  const typing = useTyping();
  if (!source || !settings.floatingAssistant || typing || HIDDEN_ON.some((r) => r.test(pathname))) return null;
  const name = settings.showMyName ? firstName(source.displayName, source.email) : null;
  const tip = name ? `Hi ${name} — ask SpenDrop AI` : "Ask SpenDrop AI";
  return (
    <Link href="/ask" aria-label="Ask SpenDrop AI" data-tip={tip} data-tip-side="left" className="sd-robot sd-tip" prefetch>
      <span className="sd-robot-float">
        <Image src="/ai/spendrop-robot.webp" alt="" width={254} height={288} priority={false} draggable={false} className="sd-robot-img" />
      </span>
    </Link>
  );
}
