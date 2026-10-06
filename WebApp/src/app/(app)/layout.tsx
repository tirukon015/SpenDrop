import { Suspense } from "react";
import { AppShell } from "@/components/app-shell";
import { BrandMark } from "@/components/brand";
import { DataProvider } from "@/components/providers/data-provider";
import { ToastProvider } from "@/components/ui/toast";

function AppLoading() {
  return (
    <div role="status" aria-label="Loading SpenDrop" className="flex min-h-dvh flex-col items-center justify-center gap-3">
      <BrandMark size={48} className="animate-pulse" />
      <span className="text-sm text-label-2">Loading SpenDrop…</span>
    </div>
  );
}

/**
 * Everything behind sign-in. proxy.ts redirects signed-out visitors; RLS in the database protects the data itself.
 * Rendered per request and streamed behind Suspense (Cache Components: authenticated UI is never prerendered).
 */
export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <Suspense fallback={<AppLoading />}>
      <DataProvider>
        <ToastProvider>
          <AppShell>{children}</AppShell>
        </ToastProvider>
      </DataProvider>
    </Suspense>
  );
}
