# Member Permissions (read-only) — Frontend Implementation Plan (#108)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Activate the member profile drawer's disabled **Permissions tab** as a read-only, grouped, plain-language "what this member can do" view, fed by the #108 capabilities endpoint and translated entirely on the client.

**Architecture:** A lazy TanStack Query hook fetches `CapabilitiesRead`; a `<PermissionsTab>` renders three grouped cards of capability rows (Allowed / Not allowed + reason), showing an owner-only "Change in Settings → Scheduling" pointer on setting-gated blocked rows. All copy comes from `reason_code`/`note_code`/`key` → i18n mapping (en + hi).

**Tech Stack:** Next.js (App Router), React + TypeScript, TanStack Query, react-i18next, Tailwind v4 semantic tokens, base-ui primitives, Vitest + React Testing Library, Playwright. Spec: `docs/specs/2026-06-23-member-permissions-readonly-design.md`. Backend contract: `docs/plans/2026-06-23-member-permissions-readonly-backend-plan.md`.

## Global Constraints

- **Rule 17.0:** semantic design tokens only (`bg-card`, `text-muted-foreground`, `bg-muted`, `text-foreground`, `border-border`, success/`ring`), compose `src/components/ui/*` + the drawer's existing card/row pattern. NO per-page CSS, `.module.css`, styled-jsx, raw colour literals, or Tailwind palette utilities. Both light + dark themes; mobile-first (sheet full-width on mobile); WCAG 2.1 AA.
- **i18n-first:** zero hardcoded user-facing strings — every label/reason/note/state via `t('...')`. Add keys to BOTH `en.json` and `hi.json` with **key parity** (gated by `tests/e2e/i18n.spec.ts`). Display strings derive from backend **codes** (`reason_code`/`note_code`/`key`), never backend English.
- **Allowed/blocked conveyed by icon + text, never colour alone** (a11y).
- `npx tsc --noEmit` + `npm run build` clean before each commit.
- Reserved ports 3001/8001/5434 are TEST-SUITE only; dev FE on 3000.
- **Render on :8753 + user sign-off BEFORE building** the visual (owner-viewing-an-assistant with a toggle off, and a doctor).
- **FE PR is HELD for user QA** — do not merge until the user says "merge".

---

### Task 1: Capabilities API client + types + hook

**Files:**
- Modify: `src/features/team/api.ts` (add fetcher + types)
- Modify: `src/features/team/hooks.ts` (add hook) — or co-locate per the repo's team feature convention
- Test: `src/features/team/__tests__/capabilities.test.ts` (new; Vitest, fetch mocked)

**Interfaces:**
- Produces:
  - Types `Capability { key; group; allowed; reason_code: string|null; note_code: string|null; setting_key: string|null }` and `MemberCapabilities { member_id; kind; effective_role; capabilities: Capability[] }`
  - `getMemberCapabilities(clinicId: string, kind: "doctor"|"assistant", memberId: string): Promise<MemberCapabilities>`
  - `useMemberCapabilities(clinicId, kind, memberId, opts?: { enabled?: boolean })`

- [ ] **Step 1: Write the failing test**

```ts
// src/features/team/__tests__/capabilities.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { getMemberCapabilities } from "../api";
import * as apiClient from "@/lib/api-client";

describe("getMemberCapabilities", () => {
  beforeEach(() => vi.restoreAllMocks());
  it("calls the assistant capabilities endpoint and returns the payload", async () => {
    const payload = { member_id: "m1", kind: "assistant", effective_role: "assistant", capabilities: [] };
    const spy = vi.spyOn(apiClient, "apiFetch").mockResolvedValue(payload as never);
    const out = await getMemberCapabilities("c1", "assistant", "m1");
    expect(spy).toHaveBeenCalledWith("/clinics/c1/assistants/m1/capabilities");
    expect(out).toEqual(payload);
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/team/__tests__/capabilities.test.ts`
Expected: FAIL — `getMemberCapabilities` not exported.

- [ ] **Step 3: Add types + fetcher + hook**

```ts
// src/features/team/api.ts  (append)
import { apiFetch } from "@/lib/api-client";

export type Capability = {
  key: string;
  group: "scheduling" | "patients" | "team_clinic";
  allowed: boolean;
  reason_code: string | null;
  note_code: string | null;
  setting_key: string | null;
};
export type MemberCapabilities = {
  member_id: string;
  kind: "doctor" | "assistant";
  effective_role: "owner" | "doctor" | "assistant";
  capabilities: Capability[];
};

export function getMemberCapabilities(
  clinicId: string, kind: "doctor" | "assistant", memberId: string,
): Promise<MemberCapabilities> {
  return apiFetch<MemberCapabilities>(`/clinics/${clinicId}/${kind}s/${memberId}/capabilities`);
}
```

```ts
// src/features/team/hooks.ts  (append)
import { useQuery } from "@tanstack/react-query";
import { getMemberCapabilities } from "./api";

export function useMemberCapabilities(
  clinicId: string, kind: "doctor" | "assistant", memberId: string,
  opts?: { enabled?: boolean },
) {
  return useQuery({
    queryKey: ["member-capabilities", clinicId, kind, memberId],
    queryFn: () => getMemberCapabilities(clinicId, kind, memberId),
    enabled: opts?.enabled ?? true,
  });
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run src/features/team/__tests__/capabilities.test.ts`
Expected: PASS.

- [ ] **Step 5: Typecheck + commit**

```bash
npx tsc --noEmit
git add src/features/team/api.ts src/features/team/hooks.ts src/features/team/__tests__/capabilities.test.ts
git commit -m "feat(team): member capabilities api client + hook (#108)"
```

---

### Task 2: i18n keys (en + hi parity)

**Files:**
- Modify: `src/i18n/locales/en.json`
- Modify: `src/i18n/locales/hi.json`

**Interfaces:**
- Produces the `team.permissions.*` namespace consumed by Task 3.

- [ ] **Step 1: Add the keys to `en.json`** (under `team`)

```json
"permissions": {
  "intro": "These are the actions {{name}} can take in this clinic. Some depend on clinic settings.",
  "allowed": "Allowed",
  "blocked": "Not allowed",
  "settingsLink": "Change in Settings → Scheduling",
  "groups": {
    "scheduling": "Scheduling",
    "patients": "Patients",
    "team_clinic": "Team & clinic"
  },
  "capabilities": {
    "approve_requests": "Approve & reject requests",
    "book_appointments": "Book, cancel & reschedule",
    "manage_availability": "Manage doctor availability",
    "manage_patients": "Manage patients",
    "manage_doctors": "Manage doctors",
    "clinic_administration": "Clinic administration"
  },
  "reasons": {
    "staff_approval_disabled": "Staff approval is turned off for this clinic.",
    "staff_availability_disabled": "Staff cannot manage availability for this clinic.",
    "coordination_by_staff": "Doctors approve requests; booking is handled by reception or the owner.",
    "doctors_dont_manage_team": "Only the owner and assistants manage the team.",
    "owner_only": "Owner only."
  },
  "notes": {
    "assigned_requests_only": "Their own patients' requests only.",
    "own_schedule_only": "Their own schedule only."
  }
}
```

- [ ] **Step 2: Add the same keys to `hi.json`** (translated; identical structure/keys)

```json
"permissions": {
  "intro": "इस क्लिनिक में {{name}} ये काम कर सकते हैं। कुछ क्लिनिक सेटिंग्स पर निर्भर करते हैं।",
  "allowed": "अनुमति है",
  "blocked": "अनुमति नहीं है",
  "settingsLink": "सेटिंग्स → शेड्यूलिंग में बदलें",
  "groups": {
    "scheduling": "शेड्यूलिंग",
    "patients": "मरीज़",
    "team_clinic": "टीम और क्लिनिक"
  },
  "capabilities": {
    "approve_requests": "अनुरोध स्वीकृत/अस्वीकृत करें",
    "book_appointments": "बुक, रद्द और पुनर्निर्धारित करें",
    "manage_availability": "डॉक्टर की उपलब्धता प्रबंधित करें",
    "manage_patients": "मरीज़ प्रबंधित करें",
    "manage_doctors": "डॉक्टर प्रबंधित करें",
    "clinic_administration": "क्लिनिक प्रशासन"
  },
  "reasons": {
    "staff_approval_disabled": "इस क्लिनिक के लिए स्टाफ़ स्वीकृति बंद है।",
    "staff_availability_disabled": "इस क्लिनिक के लिए स्टाफ़ उपलब्धता प्रबंधित नहीं कर सकता।",
    "coordination_by_staff": "डॉक्टर अनुरोध स्वीकृत करते हैं; बुकिंग रिसेप्शन या मालिक द्वारा की जाती है।",
    "doctors_dont_manage_team": "केवल मालिक और सहायक ही टीम प्रबंधित करते हैं।",
    "owner_only": "केवल मालिक।"
  },
  "notes": {
    "assigned_requests_only": "केवल उनके अपने मरीज़ों के अनुरोध।",
    "own_schedule_only": "केवल उनका अपना शेड्यूल।"
  }
}
```

- [ ] **Step 3: Verify parity + typecheck + commit**

Run: `npx playwright test tests/e2e/i18n.spec.ts` (or the repo's i18n parity check) — Expected: PASS (en/hi key parity).

```bash
npx tsc --noEmit
git add src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "i18n(team): permissions tab strings en+hi (#108)"
```

---

### Task 3: `<PermissionsTab>` component + RTL tests

**Files:**
- Create: `src/features/team/permissions-tab.tsx`
- Test: `src/features/team/__tests__/permissions-tab.test.tsx` (new)

**Interfaces:**
- Consumes: `useMemberCapabilities` (Task 1), `team.permissions.*` (Task 2).
- Props: `{ clinicId: string; kind: "doctor"|"assistant"; member: { id: string; name: string }; viewerRole: "owner"|"doctor"|"assistant"; active: boolean }`.
- Produces: default-exported `PermissionsTab` used by the drawer (Task 4).

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/team/__tests__/permissions-tab.test.tsx
import { render, screen } from "@testing-library/react";
import { describe, it, expect, vi } from "vitest";
import PermissionsTab from "../permissions-tab";

vi.mock("../hooks", () => ({
  useMemberCapabilities: () => ({
    isLoading: false, isError: false,
    data: {
      member_id: "m1", kind: "assistant", effective_role: "assistant",
      capabilities: [
        { key: "approve_requests", group: "scheduling", allowed: false,
          reason_code: "staff_approval_disabled", note_code: null, setting_key: "scheduling" },
        { key: "manage_patients", group: "patients", allowed: true,
          reason_code: null, note_code: null, setting_key: null },
      ],
    },
  }),
}));

const member = { id: "m1", name: "Arjun" };

function renderTab(viewerRole: "owner" | "doctor" | "assistant") {
  return render(
    <PermissionsTab clinicId="c1" kind="assistant" member={member} viewerRole={viewerRole} active />,
  );
}

describe("PermissionsTab", () => {
  it("renders allowed and blocked rows with reason", () => {
    renderTab("doctor");
    expect(screen.getByTestId("permission-state-manage_patients")).toHaveTextContent(/allowed/i);
    expect(screen.getByTestId("permission-state-approve_requests")).toHaveTextContent(/not allowed/i);
  });
  it("shows the Settings pointer ONLY for an owner viewer on a setting-gated blocked row", () => {
    const { rerender } = renderTab("owner");
    expect(screen.getByTestId("permission-settings-link-approve_requests")).toBeInTheDocument();
    rerender(<PermissionsTab clinicId="c1" kind="assistant" member={member} viewerRole="assistant" active />);
    expect(screen.queryByTestId("permission-settings-link-approve_requests")).toBeNull();
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/team/__tests__/permissions-tab.test.tsx`
Expected: FAIL — module `../permissions-tab` not found.

- [ ] **Step 3: Implement the component**

```tsx
// src/features/team/permissions-tab.tsx
"use client";
import { useTranslation } from "react-i18next";
import Link from "next/link";
import { Check, X } from "lucide-react";
import { useMemberCapabilities, type Capability } from "./hooks"; // re-export Capability from hooks or import from ./api
import { Card } from "@/components/ui/card";

const GROUP_ORDER = ["scheduling", "patients", "team_clinic"] as const;
const SETTING_ROUTE: Record<string, string> = { scheduling: "/settings?pane=scheduling" };

type Props = {
  clinicId: string;
  kind: "doctor" | "assistant";
  member: { id: string; name: string };
  viewerRole: "owner" | "doctor" | "assistant";
  active: boolean;
};

export default function PermissionsTab({ clinicId, kind, member, viewerRole, active }: Props) {
  const { t } = useTranslation();
  const { data, isLoading, isError } = useMemberCapabilities(clinicId, kind, member.id, { enabled: active });

  if (isLoading) return <div data-testid="permissions-loading" className="space-y-3">{/* skeleton rows */}
    {[0,1,2].map((i) => <div key={i} className="h-12 rounded-lg bg-muted animate-pulse" />)}</div>;
  if (isError || !data) return <p className="text-sm text-destructive">{t("apiErrors.default")}</p>;

  const byGroup = (g: string) => data.capabilities.filter((c) => c.group === g);

  return (
    <div data-testid="permissions-tab" className="space-y-4">
      <p className="text-sm text-muted-foreground">{t("team.permissions.intro", { name: member.name })}</p>
      {GROUP_ORDER.map((g) => (
        <Card key={g} className="p-4">
          <h3 className="mb-3 text-sm font-medium text-foreground">{t(`team.permissions.groups.${g}`)}</h3>
          <ul className="space-y-3">
            {byGroup(g).map((c) => <Row key={c.key} cap={c} viewerRole={viewerRole} />)}
          </ul>
        </Card>
      ))}
    </div>
  );
}

function Row({ cap, viewerRole }: { cap: Capability; viewerRole: Props["viewerRole"] }) {
  const { t } = useTranslation();
  const showLink = !cap.allowed && cap.setting_key != null && viewerRole === "owner";
  return (
    <li className={`flex items-start justify-between gap-3 ${cap.allowed ? "" : "opacity-70"}`}>
      <div className="min-w-0">
        <div className="flex items-center gap-2 text-sm text-foreground">
          {cap.allowed
            ? <Check className="size-4 shrink-0 text-[--color-success,theme(colors.green.600)]" aria-hidden />
            : <X className="size-4 shrink-0 text-muted-foreground" aria-hidden />}
          <span>{t(`team.permissions.capabilities.${cap.key}`)}</span>
        </div>
        {cap.allowed && cap.note_code && (
          <p className="ml-6 text-xs text-muted-foreground">{t(`team.permissions.notes.${cap.note_code}`)}</p>
        )}
        {!cap.allowed && cap.reason_code && (
          <p className="ml-6 text-xs text-muted-foreground">{t(`team.permissions.reasons.${cap.reason_code}`)}</p>
        )}
        {showLink && (
          <Link href={SETTING_ROUTE[cap.setting_key!]} data-testid={`permission-settings-link-${cap.key}`}
                className="ml-6 text-xs text-primary underline">
            {t("team.permissions.settingsLink")}
          </Link>
        )}
      </div>
      <span data-testid={`permission-state-${cap.key}`} className="shrink-0 text-xs text-muted-foreground">
        {t(cap.allowed ? "team.permissions.allowed" : "team.permissions.blocked")}
      </span>
    </li>
  );
}
```

> NOTE: use the project's existing success token if one exists (check `globals.css` for a `--success` / `--positive` semantic token) instead of the inline fallback shown; do NOT introduce a raw colour. Match the drawer's existing card/row component if one is already factored (from #107 Overview). Re-export `Capability` from `./hooks` or import from `./api` — keep one source.

- [ ] **Step 4: Run tests**

Run: `npx vitest run src/features/team/__tests__/permissions-tab.test.tsx`
Expected: PASS (allowed/blocked rendering + owner-only Settings link).

- [ ] **Step 5: Typecheck + commit**

```bash
npx tsc --noEmit
git add src/features/team/permissions-tab.tsx src/features/team/__tests__/permissions-tab.test.tsx
git commit -m "feat(team): read-only permissions tab component (#108)"
```

---

### Task 4: Wire into the drawer (activate the tab) + e2e

**Files:**
- Modify: `src/features/team/member-profile-drawer.tsx` (un-disable the Permissions tab; render `<PermissionsTab>` lazily on select)
- Test: `tests/e2e/team-permissions.spec.ts` (new; Playwright with mocked API per the repo's e2e mock convention)

**Interfaces:**
- Consumes: `PermissionsTab` (Task 3); the drawer already has `me` (viewer) + the `member` + `kind` (from #107).

- [ ] **Step 1: Activate the tab**

In `member-profile-drawer.tsx`: remove `disabled` from the Permissions `TabsTrigger` (testid `drawer-tab-permissions`); in the Permissions `TabsContent`, render:

```tsx
<PermissionsTab
  clinicId={clinicId}
  kind={kind}
  member={{ id: member.id, name: member.name }}
  viewerRole={me.role}
  active={activeTab === "permissions"}
/>
```

(`activeTab` is the drawer's current tab state so the query is lazy. `me.role` is the viewer's membership role already available in the drawer per #107.)

- [ ] **Step 2: Write the e2e spec** (mock `**/capabilities` per the repo's Playwright mock setup)

```ts
// tests/e2e/team-permissions.spec.ts
import { test, expect } from "@playwright/test";
// ... reuse the repo's auth+API mock harness (see theme/doctors specs)

test("owner sees Settings pointer on a blocked setting-gated row", async ({ page }) => {
  // mock GET .../assistants/<id>/capabilities → approve_requests blocked (staff_approval_disabled, setting_key scheduling)
  // open Team table → click an assistant row → drawer opens → click Permissions tab
  await page.getByTestId("drawer-tab-permissions").click();
  await expect(page.getByTestId("permissions-tab")).toBeVisible();
  await expect(page.getByTestId("permission-state-approve_requests")).toContainText(/not allowed/i);
  await expect(page.getByTestId("permission-settings-link-approve_requests")).toBeVisible();
});
```

- [ ] **Step 3: Run typecheck + build + e2e**

Run: `npx tsc --noEmit && npm run build && npm run test:e2e -- team-permissions`
Expected: PASS.

- [ ] **Step 4: Render for sign-off**

Render the drawer Permissions tab on **:8753** for: (a) owner viewing an assistant with `allow_staff_approval` off (shows blocked + Settings link), (b) a doctor (shows scoped notes), (c) dark theme + mobile width. **Get user sign-off before considering the task done.**

- [ ] **Step 5: Commit**

```bash
git add src/features/team/member-profile-drawer.tsx tests/e2e/team-permissions.spec.ts
git commit -m "feat(team): activate read-only permissions tab in member drawer (#108)"
```

---

## Self-Review (plan vs spec)

- §5a API + hook → Task 1. ✅
- §5b component (groups, rows, allowed/blocked, owner-only Settings pointer, loading/error, testids) → Task 3. ✅
- §5c i18n en+hi parity, codes→copy in locale only → Task 2. ✅
- §5d FE tests (allowed/blocked, owner-link vs not, i18n parity, a11y icon+text, render-before-build) → Tasks 2–4. ✅
- Activate the disabled tab (#107) lazily → Task 4. ✅
- Rule 17.0 (tokens, compose ui/*, no per-page CSS), both themes, mobile, FE-held-for-QA → Global Constraints + Task 4. ✅
- Placeholder scan: concrete code/keys/commands; NOTEs flag where to match an existing token/component, not placeholders. ✅
- Type consistency: `Capability`/`MemberCapabilities`/`useMemberCapabilities`/`PermissionsTab` props identical across Tasks 1–4; testids `permission-state-<key>` / `permission-settings-link-<key>` match between Task 3 and Task 4. ✅

## README

Update `dentist-registry-frontend/README.md` (mention the member Permissions tab) within the FE PR per the one-README-per-repo practice.
