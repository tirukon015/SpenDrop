"use client";

import { CircleCheck, CircleAlert } from "lucide-react";
import { createContext, useCallback, useContext, useState, type ReactNode } from "react";

type Toast = { id: number; message: string; tone: "success" | "error"; action?: { label: string; run: () => void } };
const ToastContext = createContext<(message: string, opts?: { tone?: Toast["tone"]; action?: Toast["action"] }) => void>(() => {});

export const useToast = () => useContext(ToastContext);

/** Small, polite status messages (aria-live) for saves, undo and errors. */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const show = useCallback((message: string, opts: { tone?: Toast["tone"]; action?: Toast["action"] } = {}) => {
    const id = Date.now() + Math.random();
    setToasts((t) => [...t.slice(-2), { id, message, tone: opts.tone ?? "success", action: opts.action }]);
    window.setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), opts.action ? 7000 : 3500);
  }, []);
  return (
    <ToastContext.Provider value={show}>
      {children}
      <div aria-live="polite" className="pointer-events-none fixed inset-x-0 bottom-[calc(76px+env(safe-area-inset-bottom))] z-50 flex flex-col items-center gap-2 px-4 md:bottom-6">
        {toasts.map((t) => (
          <div key={t.id} role={t.tone === "error" ? "alert" : "status"}
            className="animate-sheet pointer-events-auto flex max-w-md items-center gap-3 rounded-2xl bg-[#1c1c1e] px-4 py-3 text-sm text-white shadow-lg dark:bg-[#3a3a3c]">
            {t.tone === "error" ? <CircleAlert aria-hidden className="size-4 shrink-0 text-[#ff9f0a]" /> : <CircleCheck aria-hidden className="size-4 shrink-0 text-[#30d158]" />}
            <span className="flex-1">{t.message}</span>
            {t.action && (
              <button type="button" className="font-semibold text-[#64d2ff]" onClick={() => { t.action!.run(); setToasts((x) => x.filter((y) => y.id !== t.id)); }}>
                {t.action.label}
              </button>
            )}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}
