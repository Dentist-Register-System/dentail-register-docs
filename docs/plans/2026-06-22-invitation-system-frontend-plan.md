# Invitation System (Slice 1) — Frontend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the invitations UX — a tabbed Overview/Team/Invites shell on both Doctors & Assistants pages with a Pending Invites card and an Invites table (Resend/Copy/Cancel), an Invite dialog (Copy Link + Email), and a `/invite/[token]` acceptance flow that opens a clinic-name-contextualized sign-up and auto-joins.

**Architecture:** New `src/features/invitations/` owns invite data + components (`<ShareInvite>`, `<InviteDialog>`, `<PendingInvitesCard>`, `<InvitesTable>`). The Doctors & Assistants pages gain a tabbed shell (existing `components/ui/tabs.tsx`) hosting the current Team list (untouched) + the new invite surfaces. A public `/invite/[token]` route reads the backend preview, stashes the token through Supabase auth, and a shell-level hook auto-joins after login.

**Tech Stack:** Next.js App Router (client components), TanStack Query, react-hook-form + zod, react-i18next (en/hi), Tailwind v4 semantic tokens, Material Symbols, `components/ui/*` primitives.

## Global Constraints
- Spec: `docs/specs/2026-06-22-invitation-system-design.md`. This is the frontend half of Slice 1; consumes the backend plan's endpoints.
- **Render-before-build gate (controller):** before Task 3, the controller serves a static HTML render of the tabbed page (Overview + Invites), the Invite dialog (form + success/ShareInvite), and the acceptance screen on `:8753` and gets the user's sign-off. Build matches the approved render.
- Rule 17.0: semantic tokens only (no raw colors / Tailwind palette utilities), compose `components/ui/*`, no per-page CSS, no new tokens. Both light + dark themes. Mobile-first, WCAG AA.
- i18n-first: every visible string is a `t()` key with en + hi parity (gated by `tests/e2e/i18n.spec.ts`). No hardcoded strings. Backend statuses (`pending/accepted/expired/revoked`) mapped to `invites.status.*` keys client-side.
- Backend contract (from backend plan):
  - `GET /api/v1/clinics/{cid}/invites?role=doctor|assistant` → `Invite[]` `{ id, invitee_name, email, role, status, created_at, expires_at, accepted_at }`.
  - `POST /api/v1/clinics/{cid}/invites/{id}/resend` → `Invite`.
  - `DELETE /api/v1/clinics/{cid}/invites/{id}` → 204.
  - `GET /api/v1/invites/{token}` (PUBLIC) → `{ clinic_name, role, inviter_name, invitee_name, status, expires_at }`, `status ∈ {valid,expired,accepted,revoked,invalid}`.
  - `POST /api/v1/clinics/{cid}/doctors` / `…/assistants` → `{ doctor|assistant, invite_token }` (email now optional; phone optional).
  - `POST /api/v1/clinics/join` `{ token }` → `{ clinic_id, role }`.
- The Copy Link URL is built client-side: `${window.location.origin}/invite/${token}`.
- `gh-personal` only; branch → PR → squash + delete. FE PR **held for user QA**. CI = `tsc --noEmit` + `npm run build` (e2e local pre-merge). Remove iCloud dup files before tsc if needed: `find .next -name "* [0-9].*" -delete`.

## File Structure
- Create: `src/features/invitations/api.ts`, `hooks.ts`, `share-invite.tsx`, `invite-dialog.tsx`, `pending-invites-card.tsx`, `invites-table.tsx`.
- Create: `src/features/doctors/doctors-tabs.tsx`, `src/features/assistants/assistants-tabs.tsx` (tabbed shells).
- Modify: `src/app/doctors/page.tsx`, `src/app/assistants/page.tsx` (mount tabs).
- Modify: `src/features/doctors/add-doctor-dialog.tsx` → replace its success view with `<ShareInvite>` (or supersede with `<InviteDialog>`); same for assistants.
- Create: `src/app/invite/[token]/page.tsx`, `src/features/invitations/accept-invite.tsx`.
- Create: `src/features/invitations/use-pending-invite.ts` (token stash + auto-join hook).
- Modify: `src/components/shell/app-shell.tsx` (mount auto-join hook) and the `/login` screen (invite-context banner).
- Modify: `src/i18n/*` (en + hi keys).
- Tests: `tests/e2e/invitations.spec.ts`.

---

### Task 1: Invitations data layer (`api.ts` + `hooks.ts`)

**Files:**
- Create: `src/features/invitations/api.ts`, `src/features/invitations/hooks.ts`

**Interfaces:**
- Produces:
  - `type Invite = { id: string; invitee_name: string | null; email: string | null; role: "doctor"|"assistant"; status: "pending"|"accepted"|"expired"|"revoked"; created_at: string; expires_at: string; accepted_at: string | null }`.
  - `type InvitePreview = { clinic_name: string; role: string; inviter_name: string | null; invitee_name: string | null; status: "valid"|"expired"|"accepted"|"revoked"|"invalid"; expires_at: string | null }`.
  - `fetchInvites(clinicId, role)`, `resendInvite(clinicId, id)`, `cancelInvite(clinicId, id)`, `fetchInvitePreview(token)` (uses a plain unauthenticated `fetch` to the public route, NOT `apiFetch`).
  - Hooks: `useInvites(clinicId, role)`, `useResendInvite(clinicId)`, `useCancelInvite(clinicId)` — mutations invalidate `["invites", clinicId, role]` AND `["doctors"|"assistants", clinicId]`.

- [ ] **Step 1: Write `api.ts`**

```ts
import { apiFetch } from "@/lib/api-client";
import { env } from "@/lib/env";

export type InviteRole = "doctor" | "assistant";
export type Invite = {
  id: string; invitee_name: string | null; email: string | null;
  role: InviteRole; status: "pending" | "accepted" | "expired" | "revoked";
  created_at: string; expires_at: string; accepted_at: string | null;
};
export type InvitePreview = {
  clinic_name: string; role: string; inviter_name: string | null;
  invitee_name: string | null;
  status: "valid" | "expired" | "accepted" | "revoked" | "invalid";
  expires_at: string | null;
};

export const fetchInvites = (clinicId: string, role: InviteRole) =>
  apiFetch<Invite[]>(`/api/v1/clinics/${clinicId}/invites?role=${role}`);

export const resendInvite = (clinicId: string, id: string) =>
  apiFetch<Invite>(`/api/v1/clinics/${clinicId}/invites/${id}/resend`, { method: "POST" });

export const cancelInvite = (clinicId: string, id: string) =>
  apiFetch<void>(`/api/v1/clinics/${clinicId}/invites/${id}`, { method: "DELETE" });

// Public, unauthenticated — does NOT use apiFetch (no bearer token).
export async function fetchInvitePreview(token: string): Promise<InvitePreview> {
  const res = await fetch(`${env.NEXT_PUBLIC_API_URL}/api/v1/invites/${encodeURIComponent(token)}`);
  if (!res.ok) return { clinic_name: "", role: "", inviter_name: null, invitee_name: null, status: "invalid", expires_at: null };
  return res.json();
}
```

> Implementer: confirm the public API base var name in `src/lib/env.ts` (e.g. `NEXT_PUBLIC_API_URL`); use whatever `api-client.ts` uses for the backend origin.

- [ ] **Step 2: Write `hooks.ts`** — `useInvites` (`useQuery`, key `["invites", clinicId, role]`, `enabled: !!clinicId`), `useResendInvite`/`useCancelInvite` (`useMutation`, onSuccess invalidate `["invites", clinicId]` (all roles) + `["doctors", clinicId]` + `["assistants", clinicId]`).

- [ ] **Step 3: `tsc --noEmit`** → clean. Commit.

```bash
git add src/features/invitations/api.ts src/features/invitations/hooks.ts
git commit -m "feat(invitations): data layer (api + hooks)"
```

---

### Task 2: `<ShareInvite>` delivery component

**Files:**
- Create: `src/features/invitations/share-invite.tsx`

**Interfaces:**
- Produces: `<ShareInvite token={string} email={string | null} onResend?={() => void} resending?={boolean} />`. Renders the invite URL (read-only), a **Copy Link** button (clipboard + "Copied!" feedback for 2s), and a **Resend email** button (shown when `email` present; calls `onResend`). A commented WhatsApp slot is left after Copy.

- [ ] **Step 1: Implement** (compose `Button`, `Icon`; semantic tokens; testids `copy-link-button`, `resend-email-button`, `invite-link`).

```tsx
"use client";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { Button } from "@/components/ui/button";
import { Icon } from "@/components/ui/icon";

export function ShareInvite({ token, email, onResend, resending }: {
  token: string; email: string | null; onResend?: () => void; resending?: boolean;
}) {
  const { t } = useTranslation();
  const [copied, setCopied] = useState(false);
  const url = typeof window !== "undefined" ? `${window.location.origin}/invite/${token}` : `/invite/${token}`;
  function copy() {
    void navigator.clipboard.writeText(url).then(() => { setCopied(true); setTimeout(() => setCopied(false), 2000); });
  }
  return (
    <div className="rounded-xl bg-secondary-container/40 p-4 space-y-3">
      <code className="block break-all text-xs text-muted-foreground font-mono" data-testid="invite-link">{url}</code>
      <div className="flex flex-wrap items-center gap-2">
        <Button variant="tonal" size="sm" onClick={copy} data-testid="copy-link-button">
          <Icon name={copied ? "check" : "content_copy"} size={16} aria-hidden />
          {copied ? t("invitations.copied") : t("invitations.copyLink")}
        </Button>
        {/* WhatsApp share — reserved for the next slice */}
        {email && onResend && (
          <Button variant="outline" size="sm" onClick={onResend} disabled={resending} data-testid="resend-email-button">
            <Icon name="mail" size={16} aria-hidden />
            {t("invitations.sendEmail")}
          </Button>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 2: `tsc --noEmit`** → clean. Commit `feat(invitations): ShareInvite delivery component`.

---

### Task 3: `<InviteDialog>` (Name + Email → create → success w/ ShareInvite)

> **Render-before-build gate:** the controller must have served + obtained sign-off on the dialog render before this task.

**Files:**
- Create: `src/features/invitations/invite-dialog.tsx`
- Modify: `src/features/doctors/add-doctor-dialog.tsx`, `src/features/assistants/add-assistant-dialog.tsx` (or replace usages with `<InviteDialog kind="doctor|assistant" />`)

**Interfaces:**
- Produces: `<InviteDialog kind="doctor" | "assistant" clinicId={string} />`. Form: Name (required) + Email (required, valid email) + optional specialty/title. On submit → `useCreateDoctor`/`useCreateAssistant` (existing hooks; email now optional in payload but required in this form) → success view shows "Invitation sent to {email}" + `<ShareInvite token={invite_token} email={email} />`. Trigger button label `invitations.inviteDoctor`/`invitations.inviteAssistant`.

- [ ] **Step 1:** Build the generic dialog parameterized by `kind` (reuse the field layout from `add-doctor-dialog.tsx`; email becomes required via zod; on success store `invite_token` from the create result and render `<ShareInvite>`). Keep testids `invite-dialog`, `invite-name-input`, `invite-email-input`, `invite-submit`, `invite-sent`.
- [ ] **Step 2:** Point the Doctors & Assistants page action buttons at `<InviteDialog>`; remove the raw-token success view from the old add dialogs (the link is now a proper URL via ShareInvite).
- [ ] **Step 3:** `tsc --noEmit` + manual smoke. Commit `feat(invitations): Invite dialog with Copy Link + Email`.

---

### Task 4: `<PendingInvitesCard>` + `<InvitesTable>`

**Files:**
- Create: `src/features/invitations/pending-invites-card.tsx`, `src/features/invitations/invites-table.tsx`

**Interfaces:**
- Consumes: `useInvites`, `useResendInvite`, `useCancelInvite`, `<ShareInvite>` (for inline Copy), `Invite` type.
- Produces:
  - `<PendingInvitesCard clinicId role onViewAll />` — `Card` titled "Pending Invites" + count; lists pending invites (avatar initials from `invitee_name`, name, email, `Pending` chip, "Invited {created_at}"); "View all invites" button → `onViewAll`.
  - `<InvitesTable clinicId role />` — `Table`: Invitee · Email · Invited on · Status chip (`invites.status.*`) · Expires on · actions. Actions per row: `pending`/`expired` → Resend + Copy Link + Cancel; `accepted` → View (links to the team member; for this slice a no-op/disabled or routes to the Team tab — keep light per spec). Confirm before Cancel.

- [ ] **Step 1:** Status chip mapping → `chip.tsx` variants (pending=warning tone, accepted=success, expired/revoked=muted/destructive) using semantic tokens only. Date formatting via `Intl.DateTimeFormat` (locale-aware).
- [ ] **Step 2:** Wire Resend (mutation + spinner + toast), Cancel (confirm + mutation), Copy Link (reuse ShareInvite's URL builder or a small inline copy). Empty state when no invites. testids `pending-invites-card`, `invites-table`, `invite-row`, `invite-resend`, `invite-cancel`, `invite-copy`.
- [ ] **Step 3:** `tsc --noEmit` → clean. Commit `feat(invitations): Pending Invites card + Invites table`.

---

### Task 5: Tabbed Doctors & Assistants pages

**Files:**
- Create: `src/features/doctors/doctors-tabs.tsx`, `src/features/assistants/assistants-tabs.tsx`
- Modify: `src/app/doctors/page.tsx`, `src/app/assistants/page.tsx`

**Interfaces:**
- Consumes: `components/ui/tabs.tsx`, existing `DoctorList`/`AssistantList`, `<PendingInvitesCard>`, `<InvitesTable>`, `<InviteDialog>`.
- Produces: a tabbed shell — **Overview** (existing Team list + `<PendingInvitesCard>` beside it), **Team** (existing list as-is), **Invites** (`<InvitesTable>`). Header keeps the page title + the `<InviteDialog>` trigger top-right. "View all invites" switches to the Invites tab.

- [ ] **Step 1:** Build `doctors-tabs.tsx` using `Tabs` with values `overview|team|invites`; lift the active tab to state so "View all invites" can switch tabs. Mount in `doctors/page.tsx` replacing the bare `<DoctorList>`.
- [ ] **Step 2:** Mirror for assistants.
- [ ] **Step 3:** `tsc --noEmit` + build. Commit `feat(invitations): tabbed Overview/Team/Invites on Doctors & Assistants`.

---

### Task 6: `/invite/[token]` acceptance route

**Files:**
- Create: `src/app/invite/[token]/page.tsx`, `src/features/invitations/accept-invite.tsx`, `src/features/invitations/use-pending-invite.ts`

**Interfaces:**
- Consumes: `fetchInvitePreview`, `useSession`.
- Produces:
  - `use-pending-invite.ts`: `stashInviteToken(token)` / `readInviteToken()` / `clearInviteToken()` over `localStorage["register.invite_token"]`.
  - `accept-invite.tsx`: renders preview states — `invalid|expired|revoked` → dead-end card (`invitations.accept.invalid`); `accepted` → "already accepted, sign in"; `valid` → context card "You've been invited to join **{clinic_name}** as a **{role}**" + primary CTA. CTA: if a session exists → call join immediately (via the Task 7 hook path) ; else `stashInviteToken(token)` then route to `/login?invite=1`.

- [ ] **Step 1:** Build the route as a client page: `fetchInvitePreview(params.token)` via `useQuery`, render `<AcceptInvite preview token />`. Loading + error states.
- [ ] **Step 2:** Implement the preview-state UI + token stash + CTA routing. testids `accept-invite`, `accept-cta`, `accept-invalid`.
- [ ] **Step 3:** `tsc --noEmit` → clean. Commit `feat(invitations): /invite/[token] acceptance route`.

---

### Task 7: Post-auth auto-join + login invite-context banner

**Files:**
- Modify: `src/components/shell/app-shell.tsx` (or the authed root) to mount the auto-join hook
- Create/extend: `src/features/invitations/use-pending-invite.ts` (`useAutoJoinPendingInvite()`)
- Modify: the `/login` screen to read `?invite=1` + the stashed token's clinic name for a banner
- Modify: `src/features/clinic/hooks.ts` if a `useJoinClinic` doesn't already cover programmatic join (it does — reuse it)

**Interfaces:**
- Produces: `useAutoJoinPendingInvite()` — on mount, if `readInviteToken()` and a session exists, `POST /clinics/join {token}`, then `clearInviteToken()`, invalidate `["me"]`, toast success (or "already a member"). Runs once per token (guard with a ref keyed to the token).
- Consumes: existing `useJoinClinic` (from onboarding), `useSession`.

- [ ] **Step 1:** Implement `useAutoJoinPendingInvite()` reusing `useJoinClinic`. Mount it high in the authed tree so it fires right after login regardless of landing route. On "already a member" (409/conflict) → clear token + friendly toast, no error surface.
- [ ] **Step 2:** Login banner: when `?invite=1`, fetch the stashed token's preview (or pass clinic name through) and render "You're joining **{clinic_name}**" above the auth form. testid `invite-context-banner`.
- [ ] **Step 3:** `tsc --noEmit` + build. Commit `feat(invitations): post-auth auto-join + login invite banner`.

---

### Task 8: i18n keys (en + hi) + e2e

**Files:**
- Modify: en + hi locale resources (wherever `src/i18n` keeps them)
- Create: `tests/e2e/invitations.spec.ts`

- [ ] **Step 1:** Add all `invitations.*` and `invites.status.*` keys in BOTH en and hi (title/subtitle, inviteDoctor/inviteAssistant, copyLink, copied, sendEmail, pendingInvites, viewAll, table headers, status.pending/accepted/expired/revoked, accept.title/invalid/expired/accepted, banner copy, confirm-cancel copy). Reuse existing `common.*` where possible.
- [ ] **Step 2:** Verify parity: `npm run test:e2e -- i18n` (the `tests/e2e/i18n.spec.ts` gate) → green.
- [ ] **Step 3:** Write `tests/e2e/invitations.spec.ts` (Supabase + backend mocked, per existing e2e patterns): create-invite flow shows ShareInvite with a `/invite/` URL; Invites tab renders rows + Resend; `/invite/[token]` valid preview → CTA → (mocked) join. Run locally → green.
- [ ] **Step 4:** Commit `feat(invitations): i18n en/hi + e2e coverage`.

---

## Self-Review (against the spec)
- §5a data layer (api + hooks, public preview via plain fetch): Task 1. ✅
- §5a `<ShareInvite>` (Copy + email resend, WhatsApp slot): Task 2. ✅
- §5a `<InviteDialog>` (Name + Email → create → success): Task 3 (behind render gate). ✅
- §5a `<PendingInvitesCard>` + `<InvitesTable>` (status chips, Resend/Copy/Cancel/View): Task 4. ✅
- §5b tabbed Overview/Team/Invites on both pages: Task 5. ✅
- §5c `/invite/[token]` preview states + token stash + contextual sign-up: Task 6. ✅
- §5c post-auth auto-join + login banner (skips onboarding): Task 7. ✅
- §5d i18n en/hi + render-before-build + e2e: Task 8 + Global Constraints. ✅
- Type consistency: `Invite`/`InvitePreview` defined in Task 1 and reused in 4/6/7; `<ShareInvite token email onResend resending>` signature identical in Tasks 2/3/4; tab values `overview|team|invites` consistent across Task 5. ✅
- Placeholder scan: two implementer confirmations (env var name for the public base URL; existing `useJoinClinic` reuse) are concrete "verify this name" notes, not TBD logic. ✅
- "View" on accepted invites kept light (per the user's OK): Task 4. ✅
