"use client";

import { useParams } from "next/navigation";
import { Page, PageHeader } from "@/components/app-shell";
import { useData } from "@/components/providers/data-provider";
import { RecordGate } from "@/components/record-loader";
import { TransactionForm } from "@/components/transaction-form";

export default function EditMovementPage() {
  const { id } = useParams<{ id: string }>();
  const { live } = useData();
  const movement = live.movements.find((m) => m.id === id);
  return (
    <RecordGate found={Boolean(movement)}>
      <PageHeader title="Edit" back={{ href: `/transactions/m/${id}`, label: "Back" }} />
      <Page className="max-w-3xl">{movement && <TransactionForm key={movement.id + movement.updatedAt} movement={movement} />}</Page>
    </RecordGate>
  );
}
