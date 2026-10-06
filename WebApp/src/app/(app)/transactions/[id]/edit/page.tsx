"use client";

import { useParams } from "next/navigation";
import { Page, PageHeader } from "@/components/app-shell";
import { useData } from "@/components/providers/data-provider";
import { RecordGate } from "@/components/record-loader";
import { TransactionForm } from "@/components/transaction-form";

export default function EditExpensePage() {
  const { id } = useParams<{ id: string }>();
  const { live } = useData();
  const expense = live.expenses.find((e) => e.id === id);
  return (
    <RecordGate found={Boolean(expense)}>
      <PageHeader title="Edit Expense" back={{ href: `/transactions/${id}`, label: "Back" }} />
      <Page className="max-w-3xl">{expense && <TransactionForm key={expense.id + expense.updatedAt} expense={expense} />}</Page>
    </RecordGate>
  );
}
