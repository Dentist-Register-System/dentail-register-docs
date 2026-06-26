# Team Nav Consolidation + Invite-Surface Gating — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fold the Doctors + Assistants nav items into a single **Team** hub (`/team`, two cards → existing rosters), and gate the invite surface to owners (frontend + a backend authorization fix).

**Architecture:** Frontend-led. Add a `/team` landing that links to the unchanged `/doctors` & `/assistants` views; swap the two nav entries for one `Team` entry; gate the invite button + Invites tab + pending-invites card behind a single `canManageInvites()` helper. Backend: tighten `create_doctor` to owner-only via its own dependency (leaving `update`/`delete` doctor untouched).

**Tech Stack:** Backend — FastAPI + SQLAlchemy + pytest. Frontend — Next.js App Router, React, TanStack Query, react-i18next, Tailwind v4 semantic tokens, Playwright e2e (mocked).

**Spec:** `docs/specs/2026-06-26-team-nav-consolidation-design.md`.

## Global Constraints

- **i18n-first (Rule §16):** every new user-facing string comes from a `t()` key added to **both** `src/i18n/locales/en.json` **and** `src/i18n/locales/hi.json`. Counts use `{{count}}` interpolation. No hardcoded literals.
- **Design system (Rule §17.0):** semantic tokens only (`bg-primary-container`, `text-on-primary-container`, `bg-card`, `text-foreground`, `text-muted-foreground`, `border-border`, etc.). No per-page CSS, no raw colors. Compose `AppShell` › template › `components/ui/*`.
- **Team visibility:** the `Team` nav item is shown to **all roles** (owner/doctor/assistant). Do **NOT** role-gate it.
- **Invite surface = owner-only** this phase, behind `canManageInvites(ctx)` returning `role === "owner"` (the single seam for the future `allow_staff_manage_invites` assistant setting). Non-owner doctors never.
- **Untouched:** Doctors Schedules nav gate, Edit-availability gating, approve/reject gating, `update_doctor`/`delete_doctor` (`_can_manage`). 
- **Ports:** dev FE `3000` / BE `8000` / Postgres `5433`. Never `3001`/`8001`/`5434` (E2E suite).
- **TDD:** failing test first. Backend = pytest (`uv run pytest`). Frontend = Playwright e2e (`npm run test:e2e`, backend + Supabase mocked).
- **No new dependencies.** Permissive-OSS only.
- **Release (post-merge, separate):** backend → frontend, manual. This is a feature → **minor** bump (and it carries the already-merged assistant-doctor-profile patch).

---

### Task 1: Backend — gate `create_doctor` to owner-only

**Files:**
- Modify: `app/modules/doctors/router.py` (around line 22 + the `create_doctor` dependency on line ~37)
- Test: `tests/doctors/test_create_doctor_authz.py` (create)

**Interfaces:**
- Produces: `POST /api/v1/clinics/{clinic_id}/doctors` now returns **403** for `assistant`, **201** for `owner` (unchanged for `doctor`: still 403, not in the gate).

- [ ] **Step 1: Write the failing test**

Create `tests/doctors/test_create_doctor_authz.py`:

```python
from tests.conftest import make_clinic

OWNER = "11111111-1111-1111-1111-111111111111"
ASST = "33333333-3333-3333-3333-333333333333"


def test_assistant_cannot_create_doctor(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = make_clinic(owner, name="C")
    token = owner.post(
        f"/api/v1/clinics/{clinic}/invites", json={"role": "assistant"}
    ).json()["token"]
    asst, _ = auth_client(sub=ASST)
    assert asst.post("/api/v1/clinics/join", json={"token": token}).status_code == 200
    r = asst.post(
        f"/api/v1/clinics/{clinic}/doctors",
        json={"name": "Dr. X", "phone": "+91 90000 00001"},
    )
    assert r.status_code == 403, r.text


def test_owner_can_create_doctor(auth_client):
    owner, _ = auth_client(sub=OWNER)
    clinic = make_clinic(owner, name="C")
    r = owner.post(
        f"/api/v1/clinics/{clinic}/doctors",
        json={"name": "Dr. Y", "phone": "+91 90000 00002"},
    )
    assert r.status_code == 201, r.text
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd dentist-registry-backend && uv run pytest tests/doctors/test_create_doctor_authz.py -q`
Expected: `test_assistant_cannot_create_doctor` **FAILS** (currently returns 201, gate allows assistants); `test_owner_can_create_doctor` passes.

- [ ] **Step 3: Add the owner-only gate**

In `app/modules/doctors/router.py`, add a dedicated gate next to `_can_manage` (line 22):

```python
_can_manage = require_role(MemberRole.owner, MemberRole.assistant)
# Creating/inviting a doctor is owner-only (matches create_assistant and POST /invites).
# update/delete doctor stay on _can_manage.
_can_invite_doctor = require_role(MemberRole.owner)
```

Then change **only** `create_doctor`'s dependency from `_can_manage` to `_can_invite_doctor`:

```python
def create_doctor(
    clinic_id: uuid.UUID,
    data: DoctorCreate,
    db: DbSession,
    membership=Depends(_can_invite_doctor),
):
```

Leave `update_doctor` and `delete_doctor` on `Depends(_can_manage)` unchanged.

- [ ] **Step 4: Run the new test + the full suite to verify pass + no regressions**

Run: `uv run pytest tests/doctors/test_create_doctor_authz.py -q && uv run pytest -q`
Expected: new tests **PASS**; full suite **all green** (was 308 + 2 new = 310). If any existing test posted to `/doctors` as an assistant expecting 201, update it to the new owner-only reality (grep: `grep -rn '"/doctors"' tests | grep -i assist`).

- [ ] **Step 5: Lint + commit**

```bash
uv run ruff check app/modules/doctors/router.py tests/doctors/test_create_doctor_authz.py
git add app/modules/doctors/router.py tests/doctors/test_create_doctor_authz.py
git commit -m "feat: gate create_doctor (POST /doctors) to owner-only"
```

---

### Task 2: Frontend — gate the invite surface to owners

**Files:**
- Create: `src/features/invitations/permissions.ts`
- Modify: `src/features/doctors/doctors-tabs.tsx`
- Modify: `src/features/assistants/assistants-tabs.tsx`
- Test: `tests/e2e/team-invite-gating.spec.ts` (create)

**Interfaces:**
- Produces: `canManageInvites(ctx: { role: string }): boolean` — `true` only for `role === "owner"`.
- On `/doctors` and `/assistants`, the invite button, the `tab-invites` tab+panel, and the `pending-invites-card` render **only** when `canManageInvites` is true.

- [ ] **Step 1: Write the failing e2e test**

Create `tests/e2e/team-invite-gating.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, defaultMe, gotoAuthed } from "./_auth";

async function stubLists(page: import("@playwright/test").Page) {
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/doctors*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
  );
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/assistants*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
  );
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/invites*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
  );
}

test("owner sees the full invite surface on /doctors", async ({ page }) => {
  await installAuth(page, { me: defaultMe({ role: "owner" }) });
  await stubLists(page);
  await gotoAuthed(page, "/doctors");
  await expect(page.getByTestId("tab-invites")).toBeVisible();
  await expect(page.getByTestId("pending-invites-card")).toBeVisible();
  await expect(page.getByRole("button", { name: /invite doctor/i })).toBeVisible();
});

test("assistant sees NO invite surface on /doctors", async ({ page }) => {
  await installAuth(page, { me: defaultMe({ role: "assistant" }) });
  await stubLists(page);
  await gotoAuthed(page, "/doctors");
  await expect(page.getByTestId("tab-invites")).toHaveCount(0);
  await expect(page.getByTestId("pending-invites-card")).toHaveCount(0);
  await expect(page.getByRole("button", { name: /invite doctor/i })).toHaveCount(0);
});

test("assistant sees NO invite surface on /assistants", async ({ page }) => {
  await installAuth(page, { me: defaultMe({ role: "assistant" }) });
  await stubLists(page);
  await gotoAuthed(page, "/assistants");
  await expect(page.getByTestId("tab-invites")).toHaveCount(0);
  await expect(page.getByTestId("pending-invites-card")).toHaveCount(0);
});
```

> Note: `defaultMe` already accepts overrides; `defaultMe({ role: "owner" })` overrides the whole object's top level, so pass the **full** `memberships` shape if `role` isn't a top-level field. If `defaultMe`'s `role` override doesn't reach `memberships[0].role`, use `makeMeResponse` from `team-permissions.spec.ts` instead (same file documents it).

- [ ] **Step 2: Run to verify it fails**

Run: `cd dentist-registry-frontend && npm run test:e2e -- team-invite-gating`
Expected: the "assistant sees NO invite surface" tests **FAIL** (surface currently shown to everyone).

- [ ] **Step 3: Add the `canManageInvites` helper**

Create `src/features/invitations/permissions.ts`:

```typescript
/** Who may see/use the invite surface (button, Invites tab, pending-invites card).
 *  Phase 1: owner only. Seam for a future `allow_staff_manage_invites` assistant setting. */
export function canManageInvites(ctx: { role: string }): boolean {
  return ctx.role === "owner";
}
```

- [ ] **Step 4: Gate the surface in `doctors-tabs.tsx`**

In `src/features/doctors/doctors-tabs.tsx`, add imports and derive the flag:

```typescript
import { useMe } from "@/features/clinic/hooks";
import { canManageInvites } from "@/features/invitations/permissions";
```

Inside `DoctorsTabs`, after `const { data: doctors } = useDoctors(clinicId);`:

```typescript
  const me = useMe();
  const showInvites = canManageInvites({ role: me.data?.memberships[0]?.role ?? "" });
```

Gate the header action:

```typescript
    <ListPageTemplate
      title={t("doctors.title")}
      actions={showInvites ? <InviteDialog kind="doctor" clinicId={clinicId} /> : undefined}
    >
```

Gate the Invites tab (in `TabsList`):

```typescript
          {showInvites && (
            <TabsTab value="invites" data-testid="tab-invites">
              {t("doctors.tabs.invites")}
            </TabsTab>
          )}
```

Gate the pending-invites card (replace the `<PendingInvitesCard .../>` render):

```typescript
            {showInvites && (
              <PendingInvitesCard
                clinicId={clinicId}
                role="doctor"
                onViewAll={() => setTab("invites")}
              />
            )}
```

Gate the Invites panel:

```typescript
        {showInvites && (
          <TabsPanel value="invites">
            <InvitesTable clinicId={clinicId} role="doctor" />
          </TabsPanel>
        )}
```

- [ ] **Step 5: Apply the identical gating in `assistants-tabs.tsx`**

In `src/features/assistants/assistants-tabs.tsx`, add the same two imports, derive `const me = useMe();` + `const showInvites = canManageInvites({ role: me.data?.memberships[0]?.role ?? "" });` after `const { data: assistants } = useAssistants(clinicId);`, and wrap the same four spots (`actions`, the `tab-invites` `TabsTab`, the `PendingInvitesCard` with `role="assistant"`, and the invites `TabsPanel`) in `{showInvites && ...}` / the `actions={showInvites ? ... : undefined}` ternary.

- [ ] **Step 6: Run e2e + typecheck + lint to verify pass**

Run: `npm run test:e2e -- team-invite-gating && npx tsc --noEmit && npx eslint src/features/doctors/doctors-tabs.tsx src/features/assistants/assistants-tabs.tsx src/features/invitations/permissions.ts`
Expected: all 3 e2e tests **PASS**; tsc + eslint clean.

- [ ] **Step 7: Commit**

```bash
git add src/features/invitations/permissions.ts src/features/doctors/doctors-tabs.tsx src/features/assistants/assistants-tabs.tsx tests/e2e/team-invite-gating.spec.ts
git commit -m "feat: gate invite surface (button, tab, pending card) to owners"
```

---

### Task 3: Frontend — fold Doctors + Assistants into one `Team` nav item

**Files:**
- Modify: `src/components/shell/destinations.ts`
- Modify: `src/components/shell/app-shell.tsx` (active-item logic, desktop ~line 94 + mobile ~line 191)
- Modify: `src/i18n/locales/en.json` (add `nav.team`)
- Modify: `src/i18n/locales/hi.json` (add `nav.team`)
- Test: `tests/e2e/team-nav.spec.ts` (create)

**Interfaces:**
- Produces: a nav item `data-testid="nav-team"` (href `/team`) shown to all roles; `nav-doctors` and `nav-assistants` no longer exist. The Team item stays highlighted on `/team`, `/doctors`, `/assistants`.

- [ ] **Step 1: Write the failing e2e test**

Create `tests/e2e/team-nav.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, defaultMe, gotoAuthed } from "./_auth";

async function stubLists(page: import("@playwright/test").Page) {
  for (const p of ["doctors", "assistants", "invites"]) {
    await page.route(`**/api/v1/clinics/${CLINIC_ID}/${p}*`, (r) =>
      r.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
    );
  }
}

for (const role of ["owner", "assistant", "doctor"] as const) {
  test(`Team nav item is visible for ${role}; Doctors/Assistants are gone`, async ({ page }) => {
    await installAuth(page, { me: defaultMe({ role }) });
    await stubLists(page);
    await gotoAuthed(page, "/doctors");
    await expect(page.getByTestId("nav-team")).toBeVisible();
    await expect(page.getByTestId("nav-doctors")).toHaveCount(0);
    await expect(page.getByTestId("nav-assistants")).toHaveCount(0);
  });
}

test("clicking Team nav navigates to /team", async ({ page }) => {
  await installAuth(page, { me: defaultMe({ role: "owner" }) });
  await stubLists(page);
  await gotoAuthed(page, "/doctors");
  await page.getByTestId("nav-team").first().click();
  await expect(page).toHaveURL(/\/team$/);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:e2e -- team-nav`
Expected: FAIL — `nav-team` doesn't exist, `nav-doctors`/`nav-assistants` still present.

- [ ] **Step 3: Update `destinations.ts`**

In `src/components/shell/destinations.ts`, add an optional `activePrefixes` to the interface:

```typescript
export interface NavDestination {
  key: string;
  labelKey: string;
  icon: string;
  href: string;
  /** Extra path prefixes that should keep this item highlighted (e.g. folded sub-pages). */
  activePrefixes?: string[];
}
```

Remove the `doctors` and `assistants` entries and insert `team` in their place (between `requests` and `patients`):

```typescript
  {
    key: "team",
    labelKey: "nav.team",
    icon: "group",
    href: "/team",
    activePrefixes: ["/team", "/doctors", "/assistants"],
  },
```

- [ ] **Step 4: Honor `activePrefixes` in `app-shell.tsx`**

In `src/components/shell/app-shell.tsx`, replace **both** `isActive` computations (desktop ~line 94 and mobile ~line 191) with:

```typescript
  const isActive =
    dest.href === "/"
      ? pathname === "/"
      : (dest.activePrefixes ?? [dest.href]).some((p) => pathname.startsWith(p));
```

Do **not** add a role filter for `team` in `visibleDestinations` (it is visible to all).

- [ ] **Step 5: Add the i18n key (en + hi)**

In `src/i18n/locales/en.json`, add to the `"nav"` object:

```json
    "team": "Team",
```

In `src/i18n/locales/hi.json`, add to its `"nav"` object:

```json
    "team": "टीम",
```

(If `nav.doctors` / `nav.assistants` are now unused — verify with `grep -rn "nav.doctors\|nav.assistants" src` — remove those two keys from both locale files in the same commit.)

- [ ] **Step 6: Run e2e + typecheck + lint to verify pass**

Run: `npm run test:e2e -- team-nav && npx tsc --noEmit && npx eslint src/components/shell/destinations.ts src/components/shell/app-shell.tsx`
Expected: all `team-nav` tests **PASS**; tsc + eslint clean.

- [ ] **Step 7: Commit**

```bash
git add src/components/shell/destinations.ts src/components/shell/app-shell.tsx src/i18n/locales/en.json src/i18n/locales/hi.json tests/e2e/team-nav.spec.ts
git commit -m "feat: fold Doctors + Assistants nav into a single Team item"
```

---

### Task 4: Frontend — the `/team` landing hub

**Files:**
- Create: `src/features/team/team-hub.tsx`
- Create: `src/app/team/page.tsx`
- Modify: `src/i18n/locales/en.json` (add `team.*`)
- Modify: `src/i18n/locales/hi.json` (add `team.*`)
- Test: `tests/e2e/team-hub.spec.ts` (create)

**Interfaces:**
- Consumes: `useDoctors(clinicId)`, `useAssistants(clinicId)` (each returns `{ data?: Array<{ status: string }> }`); `canManageInvites` not needed here.
- Produces: route `/team` rendering `data-testid="team-hub"` with two `Link` cards `team-card-doctors` → `/doctors` and `team-card-assistants` → `/assistants`, each with a `team-count-<key>` chip.

- [ ] **Step 1: Write the failing e2e test**

Create `tests/e2e/team-hub.spec.ts`:

```typescript
import { test, expect } from "@playwright/test";
import { CLINIC_ID, installAuth, defaultMe, gotoAuthed } from "./_auth";

async function stub(page: import("@playwright/test").Page) {
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/doctors*`, (r) =>
    r.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([
        { id: "d1", name: "Dr A", specialty: "Ortho", status: "active" },
        { id: "d2", name: "Dr B", specialty: "Endo", status: "active" },
      ]),
    }),
  );
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/assistants*`, (r) =>
    r.fulfill({
      status: 200,
      contentType: "application/json",
      body: JSON.stringify([{ id: "a1", name: "Asst A", status: "active" }]),
    }),
  );
}

test("/team shows two cards with active counts", async ({ page }) => {
  await installAuth(page, { me: defaultMe({ role: "owner" }) });
  await stub(page);
  await gotoAuthed(page, "/team", { ready: page.getByTestId("team-hub") });
  await expect(page.getByTestId("team-card-doctors")).toBeVisible();
  await expect(page.getByTestId("team-card-assistants")).toBeVisible();
  await expect(page.getByTestId("team-count-doctors")).toContainText("2");
  await expect(page.getByTestId("team-count-assistants")).toContainText("1");
});

test("Doctors card routes to /doctors", async ({ page }) => {
  await installAuth(page, { me: defaultMe({ role: "owner" }) });
  await stub(page);
  await page.route(`**/api/v1/clinics/${CLINIC_ID}/invites*`, (r) =>
    r.fulfill({ status: 200, contentType: "application/json", body: "[]" }),
  );
  await gotoAuthed(page, "/team", { ready: page.getByTestId("team-hub") });
  await page.getByTestId("team-card-doctors").click();
  await expect(page).toHaveURL(/\/doctors$/);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `npm run test:e2e -- team-hub`
Expected: FAIL — `/team` route + `team-hub` don't exist yet.

- [ ] **Step 3: Create the `TeamHub` component**

Create `src/features/team/team-hub.tsx`:

```typescript
"use client";

import Link from "next/link";
import { useTranslation } from "react-i18next";

import { Card, CardContent } from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import { useDoctors } from "@/features/doctors/hooks";
import { useAssistants } from "@/features/assistants/hooks";

export function TeamHub({ clinicId }: { clinicId: string }) {
  const { t } = useTranslation();
  const { data: doctors } = useDoctors(clinicId);
  const { data: assistants } = useAssistants(clinicId);

  const cards = [
    {
      key: "doctors",
      href: "/doctors",
      icon: "stethoscope",
      name: t("team.doctors.name"),
      desc: t("team.doctors.desc"),
      ready: doctors !== undefined,
      count: (doctors ?? []).filter((d) => d.status === "active").length,
    },
    {
      key: "assistants",
      href: "/assistants",
      icon: "badge",
      name: t("team.assistants.name"),
      desc: t("team.assistants.desc"),
      ready: assistants !== undefined,
      count: (assistants ?? []).filter((a) => a.status === "active").length,
    },
  ];

  return (
    <div className="grid grid-cols-1 gap-4 md:grid-cols-2" data-testid="team-hub">
      {cards.map((c) => (
        <Link key={c.key} href={c.href} data-testid={`team-card-${c.key}`}>
          <Card className="h-full transition-shadow hover:shadow-elevation-2">
            <CardContent className="flex flex-col gap-3 p-5">
              <div className="flex items-center gap-3">
                <span className="flex size-12 shrink-0 items-center justify-center rounded-[14px] bg-primary-container text-on-primary-container">
                  <Icon name={c.icon} size={24} aria-hidden />
                </span>
                <span className="flex-1 text-lg font-semibold text-foreground">{c.name}</span>
                <Icon name="chevron_right" size={20} className="text-muted-foreground" aria-hidden />
              </div>
              <p className="text-sm text-muted-foreground">{c.desc}</p>
              {c.ready && (
                <span
                  data-testid={`team-count-${c.key}`}
                  className="inline-flex w-fit rounded-full bg-primary-container px-2.5 py-0.5 text-xs font-semibold text-on-primary-container"
                >
                  {t("team.countActive", { count: c.count })}
                </span>
              )}
            </CardContent>
          </Card>
        </Link>
      ))}
    </div>
  );
}
```

- [ ] **Step 4: Create the `/team` page**

Create `src/app/team/page.tsx` (mirrors `src/app/doctors/page.tsx`):

```typescript
"use client";

import { useTranslation } from "react-i18next";

import { AuthGate } from "@/components/auth-gate";
import { AppShell } from "@/components/shell/app-shell";
import { ListPageTemplate } from "@/components/layout/list-page-template";
import { PageContainer } from "@/components/layout/page-container";
import { TeamHub } from "@/features/team/team-hub";
import { useMe } from "@/features/clinic/hooks";

function TeamShell() {
  const { t } = useTranslation();
  const me = useMe();

  if (me.isPending) {
    return (
      <PageContainer>
        <p className="text-sm text-muted-foreground">{t("common.loading")}</p>
      </PageContainer>
    );
  }
  if (me.isError) {
    return (
      <PageContainer>
        <p className="text-sm text-destructive" data-testid="me-error">
          {t("apiErrors.default")}
        </p>
      </PageContainer>
    );
  }

  const clinicId = me.data?.memberships[0]?.clinic_id;
  const clinicName = me.data?.memberships[0]?.clinic_name;

  if (!clinicId) {
    return (
      <PageContainer>
        <p className="text-sm text-muted-foreground" data-testid="no-clinic">
          {t("team.noClinic")}
        </p>
      </PageContainer>
    );
  }

  return (
    <AppShell clinicName={clinicName}>
      <ListPageTemplate title={t("team.title")}>
        <TeamHub clinicId={clinicId} />
      </ListPageTemplate>
    </AppShell>
  );
}

export default function TeamPage() {
  return (
    <AuthGate>
      <TeamShell />
    </AuthGate>
  );
}
```

- [ ] **Step 5: Add the i18n keys (en + hi)**

In `src/i18n/locales/en.json`, add a top-level `"team"` object:

```json
  "team": {
    "title": "Team",
    "noClinic": "You don't have a clinic yet.",
    "countActive": "{{count}} active",
    "doctors": { "name": "Doctors", "desc": "The dentists in your practice" },
    "assistants": { "name": "Assistants", "desc": "Support & coordinating staff" }
  },
```

In `src/i18n/locales/hi.json`, add the parallel object (Hindi — flag for i18n-owner review):

```json
  "team": {
    "title": "टीम",
    "noClinic": "आपके पास अभी कोई क्लिनिक नहीं है।",
    "countActive": "{{count}} सक्रिय",
    "doctors": { "name": "डॉक्टर", "desc": "आपके क्लिनिक के दंत चिकित्सक" },
    "assistants": { "name": "सहायक", "desc": "सहायता एवं समन्वयन स्टाफ़" }
  },
```

- [ ] **Step 6: Run e2e + typecheck + lint to verify pass**

Run: `npm run test:e2e -- team-hub && npx tsc --noEmit && npx eslint src/features/team/team-hub.tsx src/app/team/page.tsx`
Expected: both `team-hub` tests **PASS**; tsc + eslint clean.

- [ ] **Step 7: Full e2e sweep + commit**

```bash
npm run test:e2e   # ensure the new specs + existing suite are green together
git add src/features/team/team-hub.tsx src/app/team/page.tsx src/i18n/locales/en.json src/i18n/locales/hi.json tests/e2e/team-hub.spec.ts
git commit -m "feat: add /team landing hub with Doctors + Assistants cards"
```

> If the existing `patients.spec` failures (#40/#78) appear, they are pre-existing on main and unrelated — do not block on them.

---

## Self-Review (against the spec)

**Spec coverage:**
- §2.1 Team nav fold → **Task 3**. §2.2 landing routes to unchanged views → **Task 4** (cards `Link` to `/doctors`/`/assistants`). §2.3 Variant-B card content + copy → **Task 4**. §2.4 responsive + tokens → **Task 4** (`grid-cols-1 md:grid-cols-2`, semantic tokens). §2.5 invite surface owner-only + seam → **Task 2** (`canManageInvites`). §2.6 backend enforcement → **Task 1**. §2.7 Doctors Schedules untouched → no task (correct).
- §5 backend create_doctor owner-only, update/delete untouched → **Task 1**. §6 matrix → Tasks 1–3. §7 i18n keys → Tasks 3 (`nav.team`) + 4 (`team.*`). §8 UX [AUTO]/neg → e2e in Tasks 2–4 (visibility, routing, nav). §9 tests → each task's TDD.

**Placeholder scan:** none — every step has concrete code/commands. Two flagged judgment points (the `defaultMe` role-override shape in Task 2 Step 1; the unused `nav.doctors/nav.assistants` removal in Task 3 Step 5) include the exact check to run.

**Type/name consistency:** `canManageInvites({ role })` defined in Task 2 Step 3, consumed identically in Steps 4–5. `team-hub`, `team-card-<key>`, `team-count-<key>`, `nav-team` testids consistent between component (Task 4 Step 3) and tests (Task 4 Step 1 / Task 3 Step 1). `activePrefixes` defined (Task 3 Step 3) and consumed (Step 4).

---

## Release note (post-merge, not part of implementation)

Ship **backend → frontend**, manual, per `docs/ops/release-playbook.md`. This release also carries the already-merged assistant-doctor-profile patch → **minor** bump both repos (BE `→ v1.2.0`, FE `→ v1.5.0`). No migration. Beta has no schema change. Confirm version with the user at release time.
