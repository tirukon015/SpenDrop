import { WifiOff } from "lucide-react";
import Link from "next/link";

export const metadata = { title: "Offline" };

export default function OfflinePage() {
  return (
    <main id="main" className="flex min-h-dvh flex-col items-center justify-center gap-3 p-6 text-center">
      <WifiOff aria-hidden className="size-12 text-label-3" />
      <h1 className="text-2xl font-bold">You&apos;re offline</h1>
      <p className="max-w-sm text-label-2">SpenDrop needs a connection to open this page. Your data is safe — reconnect and try again.</p>
      <Link href="/" className="mt-2 rounded-control bg-[var(--sd-accent-fill)] px-4 py-2.5 font-semibold text-white">Try again</Link>
    </main>
  );
}
