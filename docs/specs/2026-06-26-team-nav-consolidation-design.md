# Team Nav Consolidation + Invite-Surface Gating — Design Spec

**Status:** Approved in brainstorm (2026-06-26), interactive mockup signed off via the visual companion. **Phase 1 of a 2-phase owner-nav redesign** (Phase 2 = "Today's Schedule", separate spec). Register Design System (Rule 17.0), i18n-first (en/hi), both themes, WCAG 2.2 AA per `testing/ux-standards-runbook.md`. **Frontend-led, one small backend authorization fix.**

**Requirement source:** Owner-facing nav clutter — too many top-level items. This phase *removes one* item (folds Doctors + Assistants into a single **Team**) so Phase 2 can *add* "Today's Schedule" without growing the rail. Brainstorm 2026-06-26.

**Type:** Replace two nav items with one **Team** hub; tighten the **invite** surface to owners.

---

## 1. Goal

> *"A clinic owner opens **Team**, sees two cards — **Doctors** and **Assistants** — each showing how many are active and a one-line description, and taps through to the existing roster. The rail is one item lighter for everyone, and only the owner sees invite controls."*

Today the rail carries **Doctors** and **Assistants** as separate items for every role, and the **Invite doctor / Invite assistant** buttons (plus the Invites tab and the Overview "pending invites" card) are shown to everyone — even though inviting staff is an owner concern.

---

## 2. Scope decisions (locked in brainstorm 2026-06-26)

1. **Fold `Doctors` + `Assistants` → one `Team` nav item.** Icon `group`, route `/team`, label "Team". **Shown to all roles** (owner/doctor/assistant). Net **−1** nav item for everyone.
2. **`/team` is a landing hub** with **two cards** that route to the **existing, unchanged** `/doctors` and `/assistants` views. The old routes stay reachable (deep links, the `/doctors/[id]` detail pages, the cards); they are only removed from the nav.
3. **Card content (Variant B):** icon + name + a **live "N active" count** + a one-line, role-agnostic description. Copy:
   - **Doctors** — icon `stethoscope`, "The dentists in your practice".
   - **Assistants** — icon `badge`, "Support & coordinating staff".
4. **Layout:** side-by-side on desktop (2-col), **stacked on mobile** (1-col). Composed from AppShell › page template › existing `card` components — **no per-page CSS** (Rule 17.0–17.2).
5. **Invite surface = owner-only.** The invite trigger **and** the Invites tab **and** the Overview "pending invites" card are gated together behind a single `canManageInvites(ctx)` helper. **Non-owner doctors never** see it; **assistants** see it only once a *future* `allow_staff_manage_invites` setting exists (out of scope here — the helper is the seam).
6. **Backend enforcement** of #5 (defense in depth, Rule §13.2): the invite-creation endpoints must be owner-only.
7. **Out of scope — Doctors Schedules nav.** An earlier idea to let assistants always see Doctors Schedules (read-only) was **dropped**: it would reverse scope #6 of the shipped `2026-06-26-doctors-schedules-redesign-design.md` (owner + assistant-with-`allow_staff_manage_availability`, per Sayali's beta finding F). That gate is **unchanged**.

---

## 3. What exists today (verified, 2026-06-26)

- **Nav** (`src/components/shell/destinations.ts`, `app-shell.tsx`): a flat `destinations[]`; only `my-schedule` (needs `doctor_id`) and `clinic-schedules` (owner or assistant+`allow_staff_manage_availability`) are role-gated. **`doctors` and `assistants` are shown to every role.** Rail (desktop) + bottom-nav (mobile) render the same filtered list; **no overflow handling** (relevant to Phase 2 / #56, not here).
- **Doctors page** (`/doctors` → `DoctorsTabs`): `ListPageTemplate` with an **`InviteDialog`** header action + tabs **Overview / Team / Invites**. Overview shows a team-summary card **and a "pending invites" card**. **No role gating** on any of it.
- **Assistants page** (`/assistants` → `AssistantsTabs`): identical structure.
- **The "Invite" flow** is `invite-wizard.tsx`, which calls **`createDoctor` (`POST /clinics/{id}/doctors`)** / **`createAssistant` (`POST /clinics/{id}/assistants`)** — each creates the member row *and returns an invite token*. (It does **not** call `POST /invites`.)
- **Backend invite-creation gates (inconsistent today):**
  - `POST /invites` → `require_role(owner)` ✓
  - `POST /assistants` (`create_assistant`) → `require_role(owner)` ✓
  - `POST /doctors` (`create_doctor`) → `require_role(owner, **assistant**)` ✗ — an assistant can invite a doctor via the API. `_can_manage` here **also** gates `update_doctor` + `delete_doctor`.
- **Reusable:** `card` primitives + the `doctors-schedule-grid` card pattern (avatar/icon + title + chevron, responsive 1/2/3-col); `useDoctors` / `useAssistants` hooks (active counts); `ListPageTemplate`, `PageContainer`, `AppShell`.

---

## 4. Frontend design

### 4.1 Nav (`destinations.ts` + `app-shell.tsx`)
- **Remove** the `doctors` and `assistants` destinations; **add** `team`:
  `{ key: "team", labelKey: "nav.team", icon: "group", href: "/team" }`, placed where Doctors/Assistants were (between `requests` and `patients`).
- **No role gate** on `team` (visible to all). Active-state highlighting matches existing items; `/team`, `/doctors`, `/assistants`, `/doctors/[id]`, `/assistants/[id]` all highlight the Team item.

### 4.2 `/team` landing (`src/app/team/page.tsx`)
- `AuthGate` › `AppShell` › `PageContainer`; `PageHeader` title **"Team"**.
- A **responsive grid** (`grid-cols-1` mobile, `md:grid-cols-2` desktop, `gap`) of **two cards** composed from `components/ui/card`:
  - Each card = leading icon tile (`bg-primary-container` / `text-on-primary-container`) + **name** + trailing chevron + **description** + a **"N active" count chip**. The whole card is a `Link` (tap target ≥44px).
  - **Doctors** → `/doctors`; count from `useDoctors` (active). **Assistants** → `/assistants`; count from `useAssistants` (active).
- **Empty/loading:** count chip shows a skeleton/`—` until loaded; cards never block on the count.

### 4.3 Invite-surface gating (Doctors + Assistants pages)
- Add `canManageInvites(ctx: { role: string }): boolean` (new helper, e.g. `src/features/invitations/permissions.ts`): returns `role === "owner"`. **Single seam** for the future `allow_staff_manage_invites` assistant branch.
- In `DoctorsTabs` **and** `AssistantsTabs`, gate **all three** on `canManageInvites`:
  1. the **`InviteDialog`** header action,
  2. the **Invites tab** (`TabsTab value="invites"` + its panel),
  3. the Overview **"pending invites" card**.
- Non-owners see only **Overview (team summary) + Team tab**. Routes/components otherwise unchanged.

---

## 5. Backend design (authorization only — no migration)

- **Tighten `create_doctor`** (`POST /clinics/{id}/doctors`) to **owner-only** via a **dedicated** gate (e.g. `_can_invite = require_role(MemberRole.owner)`), applied to `create_doctor` **only**.
  - **Leave `_can_manage` (owner+assistant) unchanged** on `update_doctor` and `delete_doctor` — the invite rule is about *creating*, not editing existing doctors.
- `create_assistant` and `POST /invites` are **already owner-only** — no change.
- Error: standard `ForbiddenError` (403), uniform envelope.

---

## 6. Permission matrix (this phase only)

Roles: **owner / doctor / assistant**. Assistant column tracks the **invite** capability.

| Capability | Owner | Doctor (non-owner) | Assistant | Change |
|---|:--:|:--:|:--:|---|
| **Team** nav item | ✓ | ✓ | ✓ | New; replaces Doctors+Assistants for all |
| Open Doctors / Assistants **roster** | ✓ | ✓ | ✓ | Unchanged (via the Team cards) |
| **Invite doctor / assistant** (button) | ✓ | ✗ | ✗ | Was all ✓ → owner-only |
| **Invites tab + "pending invites" card** | ✓ | ✗ | ✗ | Was all ✓ → owner-only |
| `POST /doctors` (API) | ✓ | ✗ | ✗ | Was owner+assistant → owner-only |
| `POST /assistants`, `POST /invites` (API) | ✓ | ✗ | ✗ | Already owner-only |
| Doctors Schedules nav, Edit availability, Approve/reject | — | — | — | **Unchanged** (see §2.7) |

> Future `allow_staff_manage_invites` setting will flip **assistants → ✓** for the invite rows via the `canManageInvites` seam. Non-owner doctors never.

---

## 7. i18n (Rule §16)

New keys in `en.json` + `hi.json` (no hardcoded strings; counts interpolated):
- `nav.team` — "Team"
- `team.title` — "Team"
- `team.doctors.name` / `team.doctors.desc` — "Doctors" / "The dentists in your practice"
- `team.assistants.name` / `team.assistants.desc` — "Assistants" / "Support & coordinating staff"
- `team.countActive` — "{{count}} active"

---

## 8. UX-standards mapping (`testing/ux-standards-runbook.md`)

The Phase-1 Playwright journey asserts these **[AUTO]** checks:
- **Consistency (heuristic 4 / Rule 17.0):** `/team` uses AppShell + `card` components + semantic tokens only; no per-page CSS. Team item rendered like every other nav item.
- **Recognition over recall (6):** two clearly-labeled cards, not a menu/recall.
- **Nav correctness (`nav` layer):** Team → `/team`; Doctors card → `/doctors`; Assistants card → `/assistants`.
- **Target size (2.5.8 / Rule 17.4):** cards and the nav item ≥44px tap targets.
- **Focus visible / keyboard (2.4.7):** cards are focusable links with `ring-ring` focus.
- **Both themes (17.3):** light + dark via tokens.
- **i18n (16.1, heuristic 2):** all copy from resources; `{{count}}` interpolation.
- **Negative (`neg`):** a non-owner (doctor / assistant) session shows **no** invite button, **no** Invites tab, **no** pending-invites card on `/doctors` and `/assistants`.

**[HEURISTIC]** (intelligence review): the hub feels premium-SaaS, not an ERP menu; the extra hop is justified by the count + description.

---

## 9. Testing (P0, Rule §10.1)

**Backend (pytest):**
- `create_doctor`: assistant → **403**; owner & doctor → **201** (unchanged). (`create_assistant` owner-only and `/invites` owner-only already covered.)

**Frontend (Playwright e2e, mocked):**
- Team nav visible for owner / doctor / assistant; clicking → `/team` renders **two cards**.
- Doctors card → `/doctors`; Assistants card → `/assistants`; counts render.
- **Owner**: invite button + Invites tab + pending-invites card present on `/doctors` and `/assistants`.
- **Non-owner (doctor, assistant)**: all three **absent** (the `neg` assertion above).

---

## 10. Out of scope / future

- **Doctors Schedules nav loosening (old item D)** — dropped; gate unchanged (§2.7).
- **`allow_staff_manage_invites`** assistant setting — future; `canManageInvites` is the ready seam.
- **Phase 2 — "Today's Schedule"** clinic-wide hourly view — separate spec (extends the per-doctor Appointments tab).
- **Mobile bottom-nav crowding (#56)** — separate.
- Editing/deleting existing doctors by assistants (`_can_manage` on update/delete) — untouched.

---

## 11. Verification checklist (release gate)

- [ ] Team item replaces Doctors + Assistants for **all** roles; rail/bottom-nav is **−1**.
- [ ] `/team` renders 2 cards (copy + live counts), responsive (stacked mobile / 2-up desktop); routes correct.
- [ ] `/doctors`, `/assistants`, `/doctors/[id]` still reachable by URL and via the cards.
- [ ] Invite button + Invites tab + pending-invites card **hidden** for non-owners on both pages.
- [ ] `POST /doctors` → 403 for assistant, 201 for owner/doctor; `update`/`delete` doctor unchanged.
- [ ] All new strings in en **and** hi; both themes; a11y (focus, ≥44px) pass.
- [ ] FE `tsc` + eslint + Playwright green; BE pytest + ruff green.

---

## 12. Docs to update

- This spec → implementation **plan** (`docs/plans/2026-06-26-team-nav-consolidation-plan.md`).
- Consider a one-line note in Golden Rules §18 (navigation) that Doctors + Assistants are consolidated under **Team**.
