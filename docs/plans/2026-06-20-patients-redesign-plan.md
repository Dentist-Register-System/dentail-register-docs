# Patients Page Redesign Implementation Plan (#80 first slice)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use `- [ ]` checkboxes.

**Goal:** Rebuild the Patients page into the Settings-language layout (left sub-panel + carded table + pagination, card-ified detail), matching `Mockups/patients_page.png` and the approved render.

**Architecture:** Frontend-only. Fetch up to 200 patients once (`GET …/patients?limit=200`), then do search / Recent filter / counts / pagination **client-side**. Compose existing primitives (`Card`, `Table`, `PageHeader`, `CardSeparator`, `Button` outlined, `Icon`, success card). Pure logic (recent/paginate/filter/initials/avatar-tint) extracted + unit-tested.

**Tech Stack:** Next.js App Router (client), TanStack Query, Tailwind v4 semantic tokens, Material Symbols, Playwright runner for unit tests.

## Global Constraints
- **Frontend-only, no backend, no new tokens, no per-page CSS** (Rule 17.0 — semantic tokens, compose `components/ui/*`). i18n en/hi parity for new strings. Both themes; mobile-first; WCAG AA. `tsc --noEmit` + `npm run build` clean.
- **V1 scope (spec `docs/specs/2026-06-20-patients-redesign-design.md`):** columns Patient/Phone/Age/Created-on + row ⋮; sub-nav All + Recent (client-side, last 30d); client-side pagination over ≤200. **Deferred (do NOT build):** Last Visit, PT-IDs, Inactive segment, Filter, Import/Export, server-side pagination/count/trigram search.
- Commit trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`; feature branch → PR; commit SPECIFIC paths (never `git add -A`/`.superpowers/`); don't touch `.env.local`.

---

## Task 1: API + hook + pure logic (+ unit test)

**Files:** Modify `src/features/patients/api.ts`, `src/features/patients/hooks.ts`; Create `src/features/patients/patients-logic.ts`, `tests/e2e/patients-logic.spec.ts`.

**Interfaces produced:** `listPatients(clinicId, limit?)`, `usePatientsList(clinicId)`; pure `initials`, `avatarTint`, `isRecent`, `filterByQuery`, `pageSlice`, `pageCount`.

- [ ] **Step 1: Failing unit test** — `tests/e2e/patients-logic.spec.ts`:
```typescript
import { test, expect } from "@playwright/test";
import { avatarTint, filterByQuery, initials, isRecent, pageCount, pageSlice } from "../../src/features/patients/patients-logic";

const P = (over: Partial<{ name: string; phone: string; created_at: string }> = {}) =>
  ({ id: "x", clinic_id: "c", name: "Amit Patel", phone: "+91 98765 43210", age: 34, created_at: "2026-06-01T00:00:00Z", ...over }) as never;

test("initials", () => { expect(initials("Amit Patel")).toBe("AP"); expect(initials("Riya")).toBe("R"); expect(initials("  ")).toBe("?"); });
test("avatarTint is deterministic + token-based", () => {
  expect(avatarTint("Amit Patel")).toBe(avatarTint("Amit Patel"));
  expect(avatarTint("Amit Patel")).toMatch(/^bg-(primary|tertiary)-container text-on-(primary|tertiary)-container$/);
});
test("isRecent within 30 days", () => {
  const now = Date.parse("2026-06-20T00:00:00Z");
  expect(isRecent("2026-06-10T00:00:00Z", now)).toBe(true);
  expect(isRecent("2026-04-01T00:00:00Z", now)).toBe(false);
});
test("filterByQuery matches name + phone", () => {
  const list = [P({ name: "Amit Patel", phone: "111" }), P({ name: "Riya", phone: "98765" })];
  expect(filterByQuery(list, "amit").length).toBe(1);
  expect(filterByQuery(list, "987").length).toBe(1);
  expect(filterByQuery(list, "").length).toBe(2);
});
test("pageSlice + pageCount", () => {
  const items = Array.from({ length: 23 }, (_, i) => i);
  expect(pageSlice(items, 1, 10)).toHaveLength(10);
  expect(pageSlice(items, 3, 10)).toEqual([20, 21, 22]);
  expect(pageCount(23, 10)).toBe(3);
  expect(pageCount(0, 10)).toBe(1);
});
```

- [ ] **Step 2: Run → fail** — `npx playwright test tests/e2e/patients-logic.spec.ts`.

- [ ] **Step 3: Implement** — `src/features/patients/patients-logic.ts`:
```typescript
import type { Patient } from "@/features/patients/api";

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  return (parts[0][0] + (parts[1]?.[0] ?? "")).toUpperCase();
}

const TINTS = [
  "bg-primary-container text-on-primary-container",
  "bg-tertiary-container text-on-tertiary-container",
];
export function avatarTint(name: string): string {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0;
  return TINTS[h % TINTS.length];
}

const THIRTY_DAYS = 30 * 24 * 60 * 60 * 1000;
export function isRecent(createdAtIso: string, now: number): boolean {
  const t = Date.parse(createdAtIso);
  return !Number.isNaN(t) && now - t <= THIRTY_DAYS;
}

export function filterByQuery(patients: Patient[], q: string): Patient[] {
  const s = q.trim().toLowerCase();
  if (!s) return patients;
  return patients.filter((p) => p.name.toLowerCase().includes(s) || p.phone.toLowerCase().includes(s));
}

export function pageSlice<T>(items: T[], page: number, perPage: number): T[] {
  const start = (page - 1) * perPage;
  return items.slice(start, start + perPage);
}

export function pageCount(total: number, perPage: number): number {
  return Math.max(1, Math.ceil(total / perPage));
}
```

- [ ] **Step 4: API + hook.** In `src/features/patients/api.ts` add:
```typescript
export const listPatients = (clinicId: string, limit = 200) =>
  apiFetch<Patient[]>(`/api/v1/clinics/${clinicId}/patients?limit=${limit}`);
```
In `src/features/patients/hooks.ts` add (import `listPatients`):
```typescript
export function usePatientsList(clinicId: string) {
  return useQuery({
    queryKey: ["patients", clinicId, "list"],
    queryFn: () => listPatients(clinicId),
    enabled: clinicId.length > 0,
  });
}
```

- [ ] **Step 5: Run → pass** — `npx playwright test tests/e2e/patients-logic.spec.ts`; `npx tsc --noEmit && npm run build` clean.

- [ ] **Step 6: Commit** — `git add src/features/patients/api.ts src/features/patients/hooks.ts src/features/patients/patients-logic.ts tests/e2e/patients-logic.spec.ts` → `feat(patients): list-200 hook + pure logic (recent/filter/paginate/avatar) + tests`.

---

## Task 2: Sub-panel + carded table + page composition

**Files:** Create `src/features/patients/patients-sidepanel.tsx`, `src/features/patients/patients-table.tsx`; Modify `src/app/patients/page.tsx`; i18n `en.json`+`hi.json`.

> **Read the approved render** `.superpowers/brainstorm/*/content/patients-v2.html` (or `Mockups/patients_page.png`) for exact look. Compose existing primitives only.

- [ ] **Step 1: Side panel** — `patients-sidepanel.tsx`: a `Card` containing: "Patients" heading; a **full-width outlined New patient** (reuse the existing `AddPatientDialog` from `src/features/patients/add-patient-form.tsx` — render its trigger styled `buttonVariants({ variant: "outlined" })` full-width with `Icon name="person_add"`); a search `Input` (controlled, `value`/`onChange`); and a sub-nav `Card` with two rows — **All Patients** and **Recent Patients** — each `flex justify-between` with an `Icon` + label + a count badge; the active row uses `bg-primary-container/55 text-on-primary-container` (paler, matching Settings sub-nav). Props: `{ clinicId, query, onQueryChange, segment, onSegment, counts: {all:number, recent:number} }`. testids: `patients-search`, `patients-seg-all`, `patients-seg-recent`.

- [ ] **Step 2: Table** — `patients-table.tsx`: a `Card` wrapping the `Table` primitive (`Table/TableHeader/TableRow/TableHead/TableBody/TableCell`). Header: Patient · Phone · Age · Created on · (empty for ⋮). Each row: avatar = `<span className={cn("flex size-9 items-center justify-center rounded-full text-xs font-semibold", avatarTint(p.name))}>{initials(p.name)}</span>` + name (`font-medium`); Phone = `Icon name="call" size={16} className="text-primary"` + `p.phone`; Age = `p.age != null ? \`${p.age} yrs\` : "—"`; Created on = formatted (`new Date(p.created_at).toLocaleDateString(undefined,{day:"numeric",month:"short",year:"numeric"})`); ⋮ = a small menu (state-toggled) with **View details** (→ `onSelect(p.id)`) and **Delete** (→ confirm via the existing delete path, or `onDelete(p.id)`). Whole row clickable → `onSelect(p.id)`. Pagination footer (inside the card, `border-t border-border` via a `CardSeparator` or footer div): "Showing X–Y of N" + Prev/Next buttons (+ page chips) driven by props `{ page, pageTotal, onPage, totalCount, shownFrom, shownTo }`. Props: `{ patients: Patient[], onSelect, onDelete, page, pageTotal, onPage, totalCount, shownFrom, shownTo }`. testids: `patients-table`, `patient-row-${id}`, `patients-prev`, `patients-next`. Empty state: when 0 patients, a calm centered empty-state (Icon + text), not a heavy block.

- [ ] **Step 3: Page composition** — rewrite `src/app/patients/page.tsx` `PatientsShell`: keep the AuthGate→AppShell wrapper + me-loading/error/no-clinic guards. Use `usePatientsList(clinicId)`. State: `query`, `segment` ("all"|"recent"), `page`, `selectedId`. Derive (via patients-logic): `segmented = segment==="recent" ? all.filter(p=>isRecent(p.created_at, Date.now())) : all`; `filtered = filterByQuery(segmented, query)`; `counts = { all: all.length, recent: all.filter(...isRecent).length }`; `pageTotal = pageCount(filtered.length, 10)`; `shown = pageSlice(filtered, page, 10)`; `shownFrom/shownTo/totalCount` for the footer. Reset `page` to 1 when query/segment change. Layout: a flex row — `<PatientsSidePanel ... />` (left, `md:w-72` persistent) + main: if `selectedId` → `<PatientDetail clinicId patientId={selectedId} onDeleted={()=>setSelectedId(null)} onBack={()=>setSelectedId(null)} />` (full width, back affordance); else `<PageHeader title subtitle />` + `<PatientsTable ... onSelect={setSelectedId} />`. Mobile: sub-panel stacks above (or list→detail as today). Remove the old side-by-side `PatientSearch` master pane (the sub-panel + table replace it; `patient-search.tsx` may be deleted if now unused — grep first).

- [ ] **Step 4: i18n** — add `patients.*` keys used (e.g. `patients.allSegment`, `patients.recentSegment`, `patients.colPatient/colPhone/colAge/colCreated`, `patients.showing` with `{{from}}/{{to}}/{{total}}`, `patients.viewDetails`, `patients.subtitle`, `patients.empty*`) to BOTH en+hi (reuse existing `patients.*`/`common.*` where present; mirror parity).

- [ ] **Step 5: Verify** — `npx tsc --noEmit && npm run build` clean; `npx playwright test tests/e2e/i18n.spec.ts` parity.

- [ ] **Step 6: Commit** — specific paths → `feat(patients): carded table + sub-panel (All/Recent) + client-side pagination`.

---

## Task 3: Card-ify the patient detail

**Files:** Modify `src/features/patients/patient-detail.tsx`; i18n if new strings.

- [ ] **Step 1: Card-ify Overview.** Wrap the Overview section in a `Card` with `CardHeader`+`CardTitle` ("Overview") + `<CardSeparator />` + `CardContent` containing the existing `OverviewField` grid. Keep the existing fields (Phone, Age, Referral source, Medical conditions, Notes) + the header (name + age + Edit/Delete actions) — optionally wrap the header in its own `Card` for consistency with Settings.

- [ ] **Step 2: Soften the Appointments empty-state.** Replace the heavy `<Card className="bg-muted shadow-none border-0">` block with a calm bordered empty-state: a normal `Card` + `CardContent` centered, an `Icon` (e.g. `event_busy`, `text-muted-foreground`) + the existing title/body (`patients.noAppointmentsTitle/Body`). No heavy grey fill.

- [ ] **Step 3: Back affordance.** If `onBack` is passed (full-width mode from Task 2), render a "← All Patients" text button at the top (`Icon name="arrow_back"` + `t("patients.backToList")`). Keep `onDeleted` behavior. (Add `onBack?: () => void` to the props.)

- [ ] **Step 4: i18n** — add `patients.backToList` (+ any new) to en+hi.

- [ ] **Step 5: Verify** — `npx tsc --noEmit && npm run build` clean; i18n parity.

- [ ] **Step 6: Commit** — `git add src/features/patients/patient-detail.tsx src/i18n/locales/` → `feat(patients): card-ify detail (Overview card + soft appointments empty-state + back)`.

---

## Final Verification (before PR)
- [ ] `npx tsc --noEmit && npm run build` clean; `npx playwright test tests/e2e/patients-logic.spec.ts tests/e2e/i18n.spec.ts` pass.
- [ ] Manual: Patients shows sub-panel (outlined New patient + search + All/Recent counts) + carded table (avatar/Phone/Age/Created + ⋮) + pagination; row→card-ified detail with back; both themes; mobile. No top-right New patient. Looks like the render.
- [ ] Frontend PR `Part of #80`. No backend/deps/tokens.

## Self-Review (against spec)
- Sub-panel (outlined New patient + search + All/Recent sub-nav + counts): Task 2. ✅
- Carded table (Patient/Phone/Age/Created + ⋮) + client-side pagination: Tasks 1–2. ✅
- Recent = last 30d, client-side; counts; search client-side; ≤200 fetch: Task 1 logic + Task 3 page. ✅
- Card-ified detail + soft empty-state + back: Task 3. ✅
- Deferred items NOT built (Last Visit/IDs/Inactive/Filter/Import-Export/server pagination): no task touches them. ✅
- Pure logic unit-tested; i18n parity; Rule 17.0 (token-based avatar tints, no raw colours, Table/Card primitives): Tasks 1–3. ✅
- Placeholder scan: T1 complete code; T2/T3 reference the approved render + spec for pixel composition (inherently visual) with concrete props/testids/snippets — not TBDs. ✅
- Type consistency: `usePatientsList`, `listPatients`, helper names, component props (`onSelect`/`onDelete`/`onBack`/`segment`/`counts`) consistent across tasks. ✅
