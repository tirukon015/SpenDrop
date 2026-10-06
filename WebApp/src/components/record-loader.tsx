"use client";

import { SearchX } from "lucide-react";
import { useData } from "@/components/providers/data-provider";
import { ButtonLink, Card, EmptyState, ListSkeleton } from "@/components/ui/primitives";

/** Waits for data, then shows "not found" for unknown or deleted ids. */
export function RecordGate({ found, children }: { found: boolean; children: React.ReactNode }) {
  const { status } = useData();
  if (found) return <>{children}</>;
  if (status === "loading" || status === "syncing") return <Card className="mx-4 p-0 md:mx-8"><ListSkeleton rows={3} /></Card>;
  return (
    <Card className="mx-4 md:mx-8">
      <EmptyState icon={SearchX} title="Not found" message="This record doesn't exist or was deleted." action={<ButtonLink href="/transactions" variant="tinted">Back to Transactions</ButtonLink>} />
    </Card>
  );
}
