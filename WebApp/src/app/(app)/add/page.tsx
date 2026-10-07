"use client";

import { Images } from "lucide-react";
import { Page, PageHeader } from "@/components/app-shell";
import { TransactionForm } from "@/components/transaction-form";
import { ButtonLink } from "@/components/ui/primitives";

export default function AddPage() {
  return (
    <>
      <PageHeader title="Add Transaction" back={{ href: "/transactions", label: "Transactions" }}
        actions={<ButtonLink href="/add/bulk" variant="tinted" className="max-sm:px-3"><Images aria-hidden className="size-4" /> <span className="max-sm:sr-only">Bulk Import</span></ButtonLink>} />
      <Page className="max-w-3xl"><TransactionForm /></Page>
    </>
  );
}
