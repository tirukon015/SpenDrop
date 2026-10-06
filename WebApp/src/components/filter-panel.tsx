"use client";

import { CATEGORY_ICONS, CHANNEL_ICONS } from "@/components/icons";
import { Button, Chip, Field, Input, Select } from "@/components/ui/primitives";
import { CATEGORIES, PAYMENT_CHANNELS } from "@/lib/domain/constants";
import { QUICK_DATES } from "@/lib/domain/dates";
import { defaultFilters, type ActivityFilters, type SortOrder } from "@/lib/domain/activity";
import { minorToInput, parseMinor } from "@/lib/domain/money";
import type { CategoryId, PaymentChannelId, Person } from "@/lib/domain/types";

const toggle = <T,>(list: T[], value: T) => (list.includes(value) ? list.filter((v) => v !== value) : [...list, value]);

/** Filters for the Transactions list. Used inline on desktop and inside a sheet on phones/tablets. */
export function FilterPanel({ filters, onChange, fundingAccounts, people }: {
  filters: ActivityFilters; onChange: (f: ActivityFilters) => void; fundingAccounts: string[]; people: Person[];
}) {
  const set = (patch: Partial<ActivityFilters>) => onChange({ ...filters, ...patch });
  return (
    <div className="flex flex-col gap-5">
      <Field label="Date" htmlFor="filter-date">
        <Select id="filter-date" value={filters.date} onChange={(e) => set({ date: e.target.value as ActivityFilters["date"] })}>
          {QUICK_DATES.map((d) => <option key={d.id} value={d.id}>{d.label}</option>)}
        </Select>
      </Field>
      {filters.date === "custom" && (
        <div className="grid grid-cols-2 gap-2">
          <Field label="From" htmlFor="filter-from"><Input id="filter-from" type="date" value={filters.customFrom ?? ""} onChange={(e) => set({ customFrom: e.target.value })} /></Field>
          <Field label="To" htmlFor="filter-to"><Input id="filter-to" type="date" value={filters.customTo ?? ""} onChange={(e) => set({ customTo: e.target.value })} /></Field>
        </div>
      )}
      <Field label="Sort" htmlFor="filter-sort">
        <Select id="filter-sort" value={filters.sort} onChange={(e) => set({ sort: e.target.value as SortOrder })}>
          <option value="newest">Newest first</option>
          <option value="oldest">Oldest first</option>
          <option value="highest">Highest amount</option>
          <option value="lowest">Lowest amount</option>
        </Select>
      </Field>
      <fieldset className="flex flex-col gap-2">
        <legend className="section-header mb-1.5 px-1">Category</legend>
        <div className="flex flex-wrap gap-1.5">
          {CATEGORIES.map((c) => {
            const Icon = CATEGORY_ICONS[c.id];
            return <Chip key={c.id} selected={filters.categories.includes(c.id)} onClick={() => set({ categories: toggle<CategoryId>(filters.categories, c.id) })}><Icon className="size-3.5" />{c.id}</Chip>;
          })}
        </div>
      </fieldset>
      {fundingAccounts.length > 0 && (
        <fieldset className="flex flex-col gap-2">
          <legend className="section-header mb-1.5 px-1">Funding account</legend>
          <div className="flex flex-wrap gap-1.5">
            {fundingAccounts.map((a) => <Chip key={a} selected={filters.fundingAccounts.includes(a)} onClick={() => set({ fundingAccounts: toggle(filters.fundingAccounts, a) })}>{a}</Chip>)}
          </div>
        </fieldset>
      )}
      <fieldset className="flex flex-col gap-2">
        <legend className="section-header mb-1.5 px-1">Payment channel</legend>
        <div className="flex flex-wrap gap-1.5">
          {PAYMENT_CHANNELS.map((c) => {
            const Icon = CHANNEL_ICONS[c.id];
            return <Chip key={c.id} selected={filters.channels.includes(c.id)} onClick={() => set({ channels: toggle<PaymentChannelId>(filters.channels, c.id) })}><Icon className="size-3.5" />{c.label}</Chip>;
          })}
        </div>
      </fieldset>
      {people.length > 0 && (
        <Field label="Person" htmlFor="filter-person">
          <Select id="filter-person" value={filters.personId ?? ""} onChange={(e) => set({ personId: e.target.value || null })}>
            <option value="">Anyone</option>
            {people.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
          </Select>
        </Field>
      )}
      <div className="grid grid-cols-2 gap-2">
        <Field label="Min amount" htmlFor="filter-min">
          <Input id="filter-min" inputMode="decimal" placeholder="0.00" defaultValue={filters.minMinor !== null ? minorToInput(filters.minMinor) : ""}
            onBlur={(e) => set({ minMinor: e.target.value.trim() ? parseMinor(e.target.value) : null })} />
        </Field>
        <Field label="Max amount" htmlFor="filter-max">
          <Input id="filter-max" inputMode="decimal" placeholder="Any" defaultValue={filters.maxMinor !== null ? minorToInput(filters.maxMinor) : ""}
            onBlur={(e) => set({ maxMinor: e.target.value.trim() ? parseMinor(e.target.value) : null })} />
        </Field>
      </div>
      <Button variant="secondary" onClick={() => onChange({ ...defaultFilters(), search: filters.search, type: filters.type })}>Reset filters</Button>
    </div>
  );
}
