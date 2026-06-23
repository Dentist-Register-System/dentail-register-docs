# Team Table (#106) — Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Team tab (Doctors & Assistants) into the full mockup table — server-side search, status + role/specialty filters, sortable columns, pagination (10/page), and a ⋯ row menu (Edit · Activate/Deactivate · Remove) — on a new design-system `dropdown-menu` primitive.

**Architecture:** Add a `dropdown-menu` UI primitive wrapping `@base-ui/react/menu` (same wrapper style as `dialog`/`tabs`, pure M3 tokens). Add paginated data hooks. Build ONE generic `<TeamTable>` driven by a per-entity config (columns, filter field, hooks) used by both pages, plus a shared edit dialog. Consumes the backend `…/page` endpoints from the backend plan.

**Tech Stack:** Next.js App Router, TanStack Query (`keepPreviousData`), Tailwind v4 semantic tokens, `@base-ui/react`, react-i18next.

## Global Constraints
- Spec: `docs/specs/2026-06-23-team-table-design.md`. Frontend half of #106. Consumes backend `GET …/doctors/page` & `…/assistants/page` → `{ items, total }` with params `q,status,specialty|role,sort,order,page,page_size`.
- **Rule 17.0 (user-emphasized for the dropdown):** semantic tokens ONLY, compose `components/ui/*`, no raw colors. The `dropdown-menu` MUST match the Register Design System — M3 surface/elevation/radius/focus-ring tokens, both light+dark themes — and wrap `@base-ui/react/menu` exactly like `dialog.tsx` wraps `@base-ui/react/dialog` (verify the exact Menu part names in `node_modules/@base-ui/react/menu` before coding).
- i18n-first: every string a `t()` key, en+hi PARITY (same keys both files) — the `tests/e2e/i18n.spec.ts` gate must stay green.
- Default sort `joined` desc; page size 10. Status options: All / Active / Inactive / Invited.
- Doctors role column/filter = `specialty`; Assistants = `title` (sent as the `role` query param).
- Preserve existing testids the e2e suite uses (`doctors-section`, `doctor-row-*`, `assistants-section`, etc.).
- CI = `tsc --noEmit` + `npm run build`; e2e local. FE PR **held for user QA**. `find .next -name "* [0-9].*" -delete` if iCloud dups break the build.
- **Render-before-build (controller):** serve a :8753 render of the upgraded table (toolbar + sortable table + ⋯ menu + pager) and get user sign-off BEFORE Task 4.

## File Structure
- Create: `src/components/ui/dropdown-menu.tsx` (primitive).
- Modify: `src/features/doctors/api.ts`, `hooks.ts`; `src/features/assistants/api.ts`, `hooks.ts` (page fns + hooks).
- Create: `src/features/team/team-table.tsx` (generic table), `src/features/team/types.ts` (config type).
- Create: `src/features/team/edit-member-dialog.tsx` (shared edit dialog).
- Rewrite: `src/features/doctors/doctor-team-table.tsx`, `src/features/assistants/assistant-team-table.tsx` (thin wrappers passing config to `<TeamTable>`).
- Modify: `src/i18n/locales/en.json`, `hi.json`.
- Test: `tests/e2e/team-table.spec.ts`.

---

### Task 1: `dropdown-menu` primitive (design-system)

**Files:**
- Create: `src/components/ui/dropdown-menu.tsx`

**Interfaces:**
- Produces: `DropdownMenu`, `DropdownMenuTrigger`, `DropdownMenuContent`, `DropdownMenuItem`, `DropdownMenuSeparator` (names mirroring shadcn so usage reads familiar). Built on `@base-ui/react/menu`.

- [ ] **Step 1: Inspect the base-ui Menu API.** Read `node_modules/@base-ui/react/menu` (and how `src/components/ui/dialog.tsx` wraps `@base-ui/react/dialog`). Note the exact parts (likely `Menu.Root`, `Menu.Trigger`, `Menu.Portal`, `Menu.Positioner`, `Menu.Popup`, `Menu.Item`, `Menu.Separator`).

- [ ] **Step 2: Implement the wrapper** — `"use client"`, compose the base-ui parts, style ONLY with semantic tokens to match the design system (mirror the elevation/radius the `dialog` popup uses):

```tsx
"use client";
import * as React from "react";
import { Menu as MenuPrimitive } from "@base-ui/react/menu";
import { cn } from "@/lib/utils";

function DropdownMenu(props: MenuPrimitive.Root.Props) {
  return <MenuPrimitive.Root {...props} />;
}
function DropdownMenuTrigger(props: MenuPrimitive.Trigger.Props) {
  return <MenuPrimitive.Trigger data-slot="dropdown-trigger" {...props} />;
}
function DropdownMenuContent({ className, sideOffset = 6, ...props }: MenuPrimitive.Popup.Props & { sideOffset?: number }) {
  return (
    <MenuPrimitive.Portal>
      <MenuPrimitive.Positioner sideOffset={sideOffset} align="end">
        <MenuPrimitive.Popup
          data-slot="dropdown-content"
          className={cn(
            "z-50 min-w-[10rem] overflow-hidden rounded-xl border border-border bg-popover p-1.5",
            "text-popover-foreground shadow-elevation-3 outline-none",
            "origin-[var(--transform-origin)] transition-[transform,opacity] data-[starting-style]:scale-95 data-[starting-style]:opacity-0",
            className,
          )}
          {...props}
        />
      </MenuPrimitive.Positioner>
    </MenuPrimitive.Portal>
  );
}
function DropdownMenuItem({ className, variant, ...props }: MenuPrimitive.Item.Props & { variant?: "default" | "destructive" }) {
  return (
    <MenuPrimitive.Item
      data-slot="dropdown-item"
      className={cn(
        "flex cursor-pointer items-center gap-2 rounded-lg px-3 py-2 text-sm outline-none select-none",
        "data-[highlighted]:bg-accent data-[highlighted]:text-accent-foreground",
        "focus-visible:ring-2 focus-visible:ring-ring",
        variant === "destructive" && "text-destructive data-[highlighted]:bg-destructive/10 data-[highlighted]:text-destructive",
        className,
      )}
      {...props}
    />
  );
}
function DropdownMenuSeparator({ className, ...props }: MenuPrimitive.Separator.Props) {
  return <MenuPrimitive.Separator className={cn("my-1 h-px bg-border", className)} {...props} />;
}
export { DropdownMenu, DropdownMenuTrigger, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator };
```

> Verify exact prop/part names against the installed base-ui version; adjust if `Positioner`/`Popup`/`Portal` differ. Keep ALL color/elevation/radius as tokens (`bg-popover`, `border-border`, `shadow-elevation-3`, `rounded-xl`, `ring-ring`, `bg-accent`, `text-destructive`) — these are defined in `globals.css`. No raw colors.

- [ ] **Step 3: `tsc --noEmit`** clean. (No render yet; visual check happens in the Task-4 render gate.) Commit `feat(ui): dropdown-menu primitive (design-system, base-ui)`.

---

### Task 2: Paginated data layer (both entities)

**Files:**
- Modify: `src/features/doctors/api.ts`, `src/features/doctors/hooks.ts`, `src/features/assistants/api.ts`, `src/features/assistants/hooks.ts`

**Interfaces:**
- Produces:
  - `type TeamPageParams = { q?: string; status?: string; role?: string; sort?: "name"|"joined"|"status"; order?: "asc"|"desc"; page?: number; page_size?: number }` (define once, e.g. in `src/features/team/types.ts` and import).
  - `DoctorListPage = { items: Doctor[]; total: number }`; `fetchDoctorsPage(clinicId, params)`; `useDoctorsPage(clinicId, params)`.
  - `AssistantListPage = { items: Assistant[]; total: number }`; `fetchAssistantsPage(clinicId, params)`; `useAssistantsPage(clinicId, params)`.
  - Existing `fetchDoctors`/`useDoctors` (+ assistants) UNCHANGED.

- [ ] **Step 1:** Add `fetchDoctorsPage` to `doctors/api.ts` — builds a querystring from params (omit undefined; doctors use `specialty` not `role`, so map `params.role`→`specialty` for doctors OR keep both: doctors pass `specialty`, assistants pass `role`. Simplest: the doctor fetcher serializes `specialty`, the assistant fetcher serializes `role`; the generic config supplies the right key). Use `apiFetch<DoctorListPage>`.

```ts
export type DoctorListPage = { items: Doctor[]; total: number };
export const fetchDoctorsPage = (clinicId: string, p: TeamPageParams) => {
  const qs = new URLSearchParams();
  if (p.q) qs.set("q", p.q);
  if (p.status) qs.set("status", p.status);
  if (p.role) qs.set("specialty", p.role);     // doctors filter by specialty
  if (p.sort) qs.set("sort", p.sort);
  if (p.order) qs.set("order", p.order);
  qs.set("page", String(p.page ?? 1));
  qs.set("page_size", String(p.page_size ?? 10));
  return apiFetch<DoctorListPage>(`/api/v1/clinics/${clinicId}/doctors/page?${qs}`);
};
```

- [ ] **Step 2:** Add `fetchAssistantsPage` to `assistants/api.ts` — same, but `if (p.role) qs.set("role", p.role)` (assistants filter by `role`→title). `AssistantListPage`.

- [ ] **Step 3:** Hooks — `useDoctorsPage(clinicId, params)` / `useAssistantsPage(clinicId, params)`:

```ts
import { keepPreviousData, useQuery } from "@tanstack/react-query";
export function useDoctorsPage(clinicId: string, params: TeamPageParams) {
  return useQuery({
    queryKey: ["doctors-page", clinicId, params],
    queryFn: () => fetchDoctorsPage(clinicId, params),
    enabled: !!clinicId,
    placeholderData: keepPreviousData,
  });
}
```

(assistants analogue with key `["assistants-page", clinicId, params]`.)

- [ ] **Step 4:** `tsc --noEmit` clean. Commit `feat(team): paginated data layer for doctors & assistants`.

---

### Task 3: Shared edit-member dialog

**Files:**
- Create: `src/features/team/edit-member-dialog.tsx`

**Interfaces:**
- Produces: `<EditMemberDialog kind="doctor"|"assistant" clinicId member open onOpenChange />` — pre-filled form (name, phone, email, specialty/title) → `PATCH` via existing `useUpdateDoctor`/`useUpdateAssistant`; on success closes + invalidates the page query. Reusable by #107's drawer. testids `edit-member-dialog`, `edit-member-name`, `edit-member-submit`.

- [ ] **Step 1:** Build it modeled on the old (now-deleted) add-doctor dialog form + the current `InviteDialog` (react-hook-form + zod + `components/ui/form` + `dialog`). Fields per kind (doctor→specialty, assistant→title). Controlled `open`/`onOpenChange` so a row's ⋯ → Edit can open it.
- [ ] **Step 2:** On submit call the matching update hook with changed fields; on success `onOpenChange(false)` and invalidate `["doctors-page", clinicId]` / `["assistants-page", clinicId]` (and the existing `["doctors", clinicId]`). Surface API errors via `apiErrors.*`.
- [ ] **Step 3:** Rule 17.0 tokens; strings via `t("team.edit.*")` (add to both locales in Task 6, reference now). `tsc` clean. Commit `feat(team): shared edit-member dialog`.

---

### Task 4: Generic `<TeamTable>` + wire Doctors  *(render-gated)*

> **Render gate:** controller serves the :8753 render and gets sign-off before this task.

**Files:**
- Create: `src/features/team/types.ts` (`TeamPageParams` + `TeamTableConfig`), `src/features/team/team-table.tsx`
- Rewrite: `src/features/doctors/doctor-team-table.tsx` (thin wrapper)

**Interfaces:**
- `TeamTableConfig` = `{ kind: "doctor"|"assistant"; usePage: (clinicId, params)=>UseQueryResult; roleLabelKey: string; roleColumn: (m)=>string|null; statusOptions: {value,labelKey}[]; useUpdate; useDelete; rowHref?: (m)=>string }`.
- `<TeamTable clinicId config />` renders toolbar + table + pager + ⋯ menu + edit dialog.

- [ ] **Step 1:** Build `<TeamTable>`:
  - **State:** `q` (debounced ~300ms into the param), `status`, `role`, `sort`, `order`, `page`. Reset `page` to 1 when q/status/role/sort change.
  - **Query:** `config.usePage(clinicId, { q, status, role, sort, order, page, page_size: 10 })`.
  - **Toolbar:** search input (`team-search`), status `<select>` from `config.statusOptions` (`team-status-filter`), role/specialty filter input (`team-role-filter`, placeholder from `config.roleLabelKey`).
  - **Table** (compose `components/ui/table`): columns Name · Role(`config.roleColumn`) · Phone · Joined · Status(Badge) · Actions. Sortable headers for name/joined/status — clicking toggles order, sets sort, shows an arrow icon. Dates via the shared `formatDate` util. Name links to `config.rowHref` if provided.
  - **⋯ menu** (Task-1 primitive) per row: **Edit** → opens `<EditMemberDialog>` for that member; **Activate/Deactivate** → `config.useUpdate` mutate `{status: active|inactive}` (label from current status; hide the toggle for `invited` rows); **Remove** (destructive item) → confirm (window.confirm or a small confirm) → `config.useDelete` mutate; surface `cannot_delete_active_member` as a friendly toast/inline error. testids `team-row-actions`, `team-edit`, `team-toggle-status`, `team-remove`.
  - **Pager:** "Showing {from}–{to} of {total}" + Prev/Next (disabled at bounds) computed from `total`/`page`/page_size. testids `team-pager`, `team-page-prev`, `team-page-next`.
  - **States:** loading (skeleton/`common.loading`), empty (`team.empty`), error (`apiErrors.*`). Keep `data-testid="doctors-section"` on the doctor wrapper's container.
- [ ] **Step 2:** Rewrite `doctor-team-table.tsx` as a thin wrapper passing the doctor config (`usePage: useDoctorsPage`, `roleColumn: d=>d.specialty`, `roleLabelKey:"doctors.specialty"`, status options for doctor statuses, `useUpdate: useUpdateDoctor`, `useDelete: useDeleteDoctor`, `rowHref: d=>/doctors/${d.id}`). Preserve `doctors-section` + `doctor-row-${id}` testids.
- [ ] **Step 3:** `tsc --noEmit` + `npm run build` clean. Commit `feat(team): generic TeamTable + doctors wiring`.

---

### Task 5: Wire Assistants

**Files:**
- Rewrite: `src/features/assistants/assistant-team-table.tsx`

- [ ] **Step 1:** Make it a thin wrapper passing the assistant config (`usePage: useAssistantsPage`, `roleColumn: a=>a.title`, `roleLabelKey:"assistants.title"` — note the param sent is `role`, the data layer maps it, `useUpdate: useUpdateAssistant`, `useDelete: useDeleteAssistant`, no rowHref or a future one). Preserve `assistants-section` + assistant row testids.
- [ ] **Step 2:** `tsc --noEmit` + `npm run build` clean. Commit `feat(team): assistants wiring`.

---

### Task 6: i18n (en+hi) + e2e

**Files:**
- Modify: `src/i18n/locales/en.json`, `hi.json`
- Create: `tests/e2e/team-table.spec.ts`

- [ ] **Step 1:** Add all `team.*` keys (search placeholder, status option labels All/Active/Inactive/Invited, role filter label, column headers if not reused, actions edit/activate/deactivate/remove, confirm-remove, pager `team.showing` with {from,to,total}, edit dialog copy, empty) to BOTH locales in parity. Verify `npx playwright test tests/e2e/i18n.spec.ts` green.
- [ ] **Step 2:** Write `tests/e2e/team-table.spec.ts` (mock backend per existing patterns in `tests/e2e/test-env.ts`): mock `…/doctors/page` returning a page with `total>page_size`; assert table renders rows, search input updates the request (q in URL), status filter updates request, clicking a sort header updates `sort`/`order` params, Next advances `page`, and the ⋯ menu opens with Edit/Deactivate/Remove. Keep it deterministic (mock all routes; mock `**/auth/v1/**` if needed). Run `npx playwright test tests/e2e/team-table.spec.ts` green.
- [ ] **Step 3:** `tsc` + `build` clean. Commit `test(team): e2e coverage + i18n en/hi parity`.

---

## Self-Review (against the spec)
- §5b dropdown-menu primitive (base-ui, M3 tokens, design-system): Task 1. ✅
- §5a paginated data layer (page fns + hooks, keepPreviousData, existing hooks untouched): Task 2. ✅
- §5c edit dialog (shared, reusable by #107): Task 3. ✅
- §5c table: debounced search, status + role/specialty filter, sortable headers, pager, ⋯ menu (Edit/Activate-Deactivate/Remove), states, testids: Tasks 4–5. ✅
- §5c both Doctors & Assistants via generic config: Tasks 4–5. ✅
- §5d i18n en/hi parity + render-before-build + e2e: Task 6 + render gate. ✅
- Type consistency: `TeamPageParams` defined once in `team/types.ts`, imported by both api files + hooks + table; `DoctorListPage`/`AssistantListPage` `{items,total}`; config `usePage` returns the page query. Consistent. ✅
- Rule 17.0 emphasized in Global Constraints + Task 1 (no raw colors anywhere). ✅
- Placeholder scan: concrete files/props/code/testids; no TBD. ✅
