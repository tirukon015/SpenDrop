"use client";

import { Page, PageHeader } from "@/components/app-shell";
import { TransactionForm } from "@/components/transaction-form";

export default function AddPage() {
  return (
    <>
      <PageHeader title="Add Transaction" back={{ href: "/transactions", label: "Transactions" }} />
      <Page className="max-w-3xl"><TransactionForm /></Page>
    </>
  );
}
