# SP5.1 — Hook Substrate (Frontend: Settings → Integrations pane) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a **Settings → Integrations** pane: WhatsApp / Google Calendar connection cards (status only — real connect is SP5.2/5.3) plus a **Delivery activity** list of recent hooks with status chips and a **Retry** action on failures.

**Architecture:** A new `src/features/integrations/` feature (`api.ts`, `hooks.ts`, `status.ts` pure helper) consuming the backend recovery API, surfaced as a new pane `src/features/settings/integrations-pane.tsx` registered in the existing `SettingsShell`. No new routes (Rule 18.6). TanStack Query for fetch + optimistic refetch.

**Tech Stack:** Next.js App Router (client components), TanStack Query, react-i18next, Tailwind v4 semantic tokens, `@/components/ui/*` + `@/components/layout/*`. Frontend repo: `dentist-registry-frontend`.

**Spec:** `docs/specs/2026-06-23-sp5-1-hook-substrate-design.md` §8 (issue #116). **Backend plan:** `docs/plans/2026-06-23-sp5-1-hook-substrate-backend-plan.md` (must be merged/available — provides the API).

## Global Constraints

- **Rule 17.0 framework:** semantic tokens only (NO raw colours / `bg-white` / `text-gray-*`); compose `components/ui/*` + `components/layout/*`; no per-page CSS; both Light + Dark; mobile-first; WCAG AA (≥44px targets, visible focus, no colour-only meaning).
- **i18n-first:** every user-facing string via `t()`, present in BOTH `src/i18n/locales/en.json` and `hi.json` (parity is enforced by the repo's i18n test). No hardcoded display strings.
- **Status driven by stable backend codes** — map hook `status` strings to token variants in a pure helper; `failed` uses the **warning** token (calm), not the scary `destructive` error styling (spec §8).
- **No new routes / nav destinations** — the pane lives inside `/settings` (Rule 18.6), added to `SettingsShell`'s section list.
- **Next.js caveat (`AGENTS.md`):** client components only (`"use client"`); read params via `useParams()`; consult `node_modules/next/dist/docs/` if an API surprises you.
- **API base + auth** go through `apiFetch` from `@/lib/api-client` (injects the Supabase bearer token; throws `ApiError` with `.code`). Do not call `fetch` directly.
- **No new dependencies.** Permissive-OSS only.
- Commit trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Feature branch → PR (never push `main`). Suggested branch: `feat/sp5-1-integrations-pane`. Note: the FE is held for user QA (do not auto-merge).

---

## File Structure

**Frontend (`dentist-registry-frontend`)**
- `src/features/integrations/api.ts` — types (`Hook`, `HookListPage`) + `listHooks`, `retryHook`, `cancelHook`.
- `src/features/integrations/status.ts` — pure `hookStatusToken(status)` + `hookStatusLabelKey(status)`.
- `src/features/integrations/hooks.ts` — `useHooks`, `useRetryHook`, `useCancelHook`.
- `src/features/settings/integrations-pane.tsx` — the pane (connection cards + delivery list).
- `src/features/settings/settings-shell.tsx` — register the `integrations` section.
- `src/i18n/locales/en.json`, `hi.json` — `settings.nav.integrations` + `integrations.*` keys.
- Test: `src/features/integrations/status.test.ts` (pure helper) — follow the repo's existing pure-logic test convention (mirror the test that covers `src/features/scheduling/request-status.ts`).

---

## Task 1: integrations API module + pure status helper

**Files:**
- Create: `src/features/integrations/api.ts`, `src/features/integrations/status.ts`, `src/features/integrations/status.test.ts`

**Interfaces:**
- Produces:
  - types `Hook`, `HookListPage`
  - `listHooks(clinicId, status?) => Promise<HookListPage>`, `retryHook(clinicId, id) => Promise<Hook>`, `cancelHook(clinicId, id) => Promise<Hook>`
  - `hookStatusToken(status: string): "success" | "warning" | "muted"`
  - `hookStatusLabelKey(status: string): string`

- [ ] **Step 1: Failing pure-logic test** — `src/features/integrations/status.test.ts`:

```ts
import { hookStatusToken, hookStatusLabelKey } from "@/features/integrations/status";

test("succeeded → success token", () => {
  expect(hookStatusToken("succeeded")).toBe("success");
});

test("failed → warning token (calm, not destructive)", () => {
  expect(hookStatusToken("failed")).toBe("warning");
});

test("scheduled/running/cancelled → muted", () => {
  expect(hookStatusToken("scheduled")).toBe("muted");
  expect(hookStatusToken("running")).toBe("muted");
  expect(hookStatusToken("cancelled")).toBe("muted");
});

test("label keys are namespaced", () => {
  expect(hookStatusLabelKey("failed")).toBe("integrations.status.failed");
});
```

- [ ] **Step 2: Run → fail** — run the repo's unit-test command (the one that runs `request-status` tests) → FAIL (module missing).

- [ ] **Step 3: Implement `status.ts`:**

```ts
/** Pure status helpers for hooks. No side effects, no imports — safe anywhere. */

export function hookStatusToken(status: string): "success" | "warning" | "muted" {
  switch (status) {
    case "succeeded":
      return "success";
    case "failed":
      return "warning"; // calm nudge, never scary destructive styling (spec §8)
    default:
      return "muted"; // scheduled | running | cancelled
  }
}

export function hookStatusLabelKey(status: string): string {
  return `integrations.status.${status}`;
}
```

- [ ] **Step 4: Implement `api.ts`:**

```ts
import { apiFetch } from "@/lib/api-client";

export type Hook = {
  id: string;
  hook_type: string;
  related_entity_type: string;
  related_entity_id: string;
  status: string;
  attempts: number;
  max_attempts: number;
  provider_ref: string | null;
  last_error: string | null;
  scheduled_at: string;
  next_attempt_at: string;
  executed_at: string | null;
  created_at: string;
};

export type HookListPage = { items: Hook[]; total: number };

export const listHooks = (clinicId: string, status?: string) =>
  apiFetch<HookListPage>(
    `/api/v1/clinics/${clinicId}/integrations/hooks${status ? `?status=${encodeURIComponent(status)}` : ""}`,
  );

export const retryHook = (clinicId: string, id: string) =>
  apiFetch<Hook>(`/api/v1/clinics/${clinicId}/integrations/hooks/${id}/retry`, { method: "POST" });

export const cancelHook = (clinicId: string, id: string) =>
  apiFetch<Hook>(`/api/v1/clinics/${clinicId}/integrations/hooks/${id}/cancel`, { method: "POST" });
```

- [ ] **Step 5: Run → pass + typecheck** — unit tests pass; `npm run typecheck` (or `npx tsc --noEmit`) clean.

- [ ] **Step 6: Commit**

```bash
git add src/features/integrations/api.ts src/features/integrations/status.ts src/features/integrations/status.test.ts
git commit -m "feat(integrations): API module + pure status helper (#116)"
```

---

## Task 2: TanStack Query hooks

**Files:**
- Create: `src/features/integrations/hooks.ts`

**Interfaces:**
- Consumes: `listHooks`, `retryHook`, `cancelHook`.
- Produces: `useHooks(clinicId, status?)`, `useRetryHook(clinicId)`, `useCancelHook(clinicId)`. Mutations invalidate `["integrations", clinicId]` on success.

- [ ] **Step 1: Implement `hooks.ts`** (mirrors `src/features/patients/hooks.ts`):

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";

import { cancelHook, listHooks, retryHook } from "@/features/integrations/api";

export function useHooks(clinicId: string, status?: string) {
  return useQuery({
    queryKey: ["integrations", clinicId, "hooks", status ?? "all"],
    queryFn: () => listHooks(clinicId, status),
    enabled: clinicId.length > 0,
  });
}

export function useRetryHook(clinicId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => retryHook(clinicId, id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["integrations", clinicId] }),
  });
}

export function useCancelHook(clinicId: string) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (id: string) => cancelHook(clinicId, id),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["integrations", clinicId] }),
  });
}
```

- [ ] **Step 2: Typecheck** — `npm run typecheck` clean.

- [ ] **Step 3: Commit**

```bash
git add src/features/integrations/hooks.ts
git commit -m "feat(integrations): query/mutation hooks (#116)"
```

---

## Task 3: Integrations pane + register in SettingsShell

**Files:**
- Create: `src/features/settings/integrations-pane.tsx`
- Modify: `src/features/settings/settings-shell.tsx`

**Interfaces:**
- Consumes: `useHooks`, `useRetryHook`, `hookStatusToken`, `hookStatusLabelKey`, `useClinicSettings` (from `@/features/clinic/hooks`).
- Produces: `IntegrationsPane({ clinicId, canManage })`; `SettingsShell` gains an `integrations` section.

- [ ] **Step 1: Implement the pane** — `src/features/settings/integrations-pane.tsx`:

```tsx
"use client";

import { useTranslation } from "react-i18next";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardSeparator, CardTitle } from "@/components/ui/card";
import { Icon } from "@/components/ui/icon";
import { useClinicSettings } from "@/features/clinic/hooks";
import { useHooks, useRetryHook } from "@/features/integrations/hooks";
import { hookStatusLabelKey, hookStatusToken } from "@/features/integrations/status";

export function IntegrationsPane({ clinicId }: { clinicId: string; canManage?: boolean }) {
  const { t } = useTranslation();
  const settings = useClinicSettings(clinicId);
  const hooks = useHooks(clinicId);
  const retry = useRetryHook(clinicId);

  const channels = [
    { key: "whatsapp", icon: "chat", enabled: settings.data?.whatsapp_enabled ?? false },
    { key: "google_calendar", icon: "calendar_month", enabled: settings.data?.google_calendar_enabled ?? false },
  ];

  return (
    <div className="flex flex-col gap-6" data-testid="integrations-pane">
      {/* Connections — status only; connect/OAuth lands in SP5.2/5.3 */}
      <Card>
        <CardHeader>
          <CardTitle>{t("integrations.connections.title")}</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          {channels.map((c) => (
            <div key={c.key} className="flex items-center justify-between rounded-lg border border-border px-4 py-3">
              <div className="flex items-center gap-3">
                <Icon name={c.icon} size={20} aria-hidden />
                <span className="text-sm font-medium text-foreground">{t(`integrations.channel.${c.key}`)}</span>
              </div>
              <div className="flex items-center gap-2">
                <Badge variant={c.enabled ? "success" : "muted"}>
                  {t(c.enabled ? "integrations.connections.enabled" : "integrations.connections.disabled")}
                </Badge>
                <Button variant="outline" size="sm" disabled>
                  {t("integrations.connections.comingSoon")}
                </Button>
              </div>
            </div>
          ))}
        </CardContent>
      </Card>

      {/* Delivery activity */}
      <Card>
        <CardHeader>
          <CardTitle>{t("integrations.activity.title")}</CardTitle>
        </CardHeader>
        <CardSeparator />
        <CardContent className="py-2">
          {hooks.isPending ? (
            <p className="py-4 text-sm text-muted-foreground">{t("common.loading")}</p>
          ) : (hooks.data?.items.length ?? 0) === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground" data-testid="activity-empty">
              {t("integrations.activity.empty")}
            </p>
          ) : (
            <ul className="divide-y divide-border">
              {hooks.data!.items.map((h) => (
                <li key={h.id} className="flex items-center justify-between gap-3 py-3" data-testid="activity-row">
                  <div className="min-w-0">
                    <p className="truncate text-sm font-medium text-foreground">
                      {t(`integrations.hookType.${h.hook_type}`, { defaultValue: h.hook_type })}
                    </p>
                    <p className="text-xs text-muted-foreground">{new Date(h.created_at).toLocaleString()}</p>
                  </div>
                  <div className="flex shrink-0 items-center gap-2">
                    <Badge variant={hookStatusToken(h.status)}>{t(hookStatusLabelKey(h.status))}</Badge>
                    {h.status === "failed" ? (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() => retry.mutate(h.id)}
                        disabled={retry.isPending}
                        data-testid={`retry-${h.id}`}
                      >
                        {t("integrations.activity.retry")}
                      </Button>
                    ) : null}
                  </div>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
```

> If `Badge` does not support a `variant="warning"`/`"muted"`, check `@/components/ui/badge` for the exact variant names and map `hookStatusToken`'s return values to the available variants — do NOT add raw colour classes (Rule 17.0).

- [ ] **Step 2: Register the section** — edit `src/features/settings/settings-shell.tsx`:

```tsx
// 1. import
import { IntegrationsPane } from "@/features/settings/integrations-pane";

// 2. extend the Section union
type Section = "profile" | "user" | "clinic" | "scheduling" | "integrations";

// 3. add to items[]
{ key: "integrations", labelKey: "settings.nav.integrations", icon: "hub" },

// 4. add to the render switch (after the scheduling branch)
) : section === "scheduling" ? (
  <SchedulingPane clinicId={clinicId} canManage={canManageClinic} />
) : (
  <IntegrationsPane clinicId={clinicId} canManage={canManageClinic} />
)
```

> Note: the existing render uses a chained ternary ending in `SchedulingPane`. Convert the final branch to an explicit `section === "scheduling"` check and make `IntegrationsPane` the trailing `else`, as shown.

- [ ] **Step 3: Typecheck + build** — `npm run typecheck && npm run build` → clean (the CI gates).

- [ ] **Step 4: Commit**

```bash
git add src/features/settings/integrations-pane.tsx src/features/settings/settings-shell.tsx
git commit -m "feat(integrations): Settings → Integrations pane (#116)"
```

---

## Task 4: i18n keys (en + hi parity)

**Files:**
- Modify: `src/i18n/locales/en.json`, `src/i18n/locales/hi.json`

- [ ] **Step 1: Add keys to `en.json`** (place under the existing `settings` block + a new top-level `integrations` block; match surrounding structure):

```json
"settings": { "nav": { "integrations": "Integrations" } },
"integrations": {
  "connections": { "title": "Connections", "enabled": "Enabled", "disabled": "Not connected", "comingSoon": "Coming soon" },
  "channel": { "whatsapp": "WhatsApp", "google_calendar": "Google Calendar" },
  "activity": { "title": "Delivery activity", "empty": "Nothing to show yet — messages and calendar updates will appear here.", "retry": "Retry" },
  "status": { "scheduled": "Scheduled", "running": "Sending", "succeeded": "Sent", "failed": "Failed", "cancelled": "Cancelled" },
  "hookType": {
    "whatsapp_confirmation": "WhatsApp confirmation", "whatsapp_reminder": "WhatsApp reminder",
    "whatsapp_cancellation": "WhatsApp cancellation", "whatsapp_postop": "WhatsApp post-op",
    "gcal_create": "Calendar event created", "gcal_update": "Calendar event updated", "gcal_delete": "Calendar event removed"
  }
}
```

> Merge these into the EXISTING `settings` object (don't duplicate the key) — add only `nav.integrations` there; add `integrations` as a new sibling top-level block.

- [ ] **Step 2: Add the same keys to `hi.json`** with Hindi translations (parity required):

```json
"settings": { "nav": { "integrations": "इंटीग्रेशन" } },
"integrations": {
  "connections": { "title": "कनेक्शन", "enabled": "सक्षम", "disabled": "कनेक्ट नहीं है", "comingSoon": "जल्द आ रहा है" },
  "channel": { "whatsapp": "WhatsApp", "google_calendar": "Google Calendar" },
  "activity": { "title": "डिलीवरी गतिविधि", "empty": "अभी दिखाने के लिए कुछ नहीं — संदेश और कैलेंडर अपडेट यहाँ दिखेंगे।", "retry": "पुनः प्रयास" },
  "status": { "scheduled": "निर्धारित", "running": "भेजा जा रहा है", "succeeded": "भेजा गया", "failed": "विफल", "cancelled": "रद्द" },
  "hookType": {
    "whatsapp_confirmation": "WhatsApp पुष्टि", "whatsapp_reminder": "WhatsApp अनुस्मारक",
    "whatsapp_cancellation": "WhatsApp रद्दीकरण", "whatsapp_postop": "WhatsApp पोस्ट-ऑप",
    "gcal_create": "कैलेंडर इवेंट बनाया गया", "gcal_update": "कैलेंडर इवेंट अपडेट हुआ", "gcal_delete": "कैलेंडर इवेंट हटाया गया"
  }
}
```

- [ ] **Step 3: Run i18n parity + typecheck + build** — run the repo's i18n parity test (the one used by other features) + `npm run typecheck && npm run build` → all pass.

- [ ] **Step 4: Commit**

```bash
git add src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "feat(integrations): i18n en/hi keys for Integrations pane (#116)"
```

---

## Task 5: manual verification + README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Manual check (both themes, en/hi)** — run the app against a backend with the substrate, seed a couple of hooks (enable `whatsapp_enabled` and confirm an appointment, or insert a `failed` hook), open **Settings → Integrations**: connection cards reflect settings; delivery list shows rows with calm status chips; a `failed` row shows **Retry**, clicking it refetches and the row leaves `failed`. Verify Light + Dark + Hindi.
- [ ] **Step 2: README** — add an "Integrations (Settings)" note: what the pane shows, that connect/OAuth flows arrive with SP5.2/5.3, and that `failed` deliveries can be retried here.
- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(integrations): README note for Settings → Integrations (#116)"
```

---

## Self-Review (completed by plan author)

- **Spec coverage (§8):** pane under `/settings` → Task 3 (no new route); connection cards reading clinic settings, connect deferred → Task 3; delivery-activity list + Retry on failed → Task 3; calm `failed`=warning token → Task 1 `hookStatusToken`; i18n en/hi → Task 4; M3 framework components only → Task 3 (uses `@/components/ui/*`, no raw colours); a11y/themes → Task 5 manual check. No gaps.
- **Type consistency:** `Hook`/`HookListPage` shapes match the backend `HookRead`/`HookListPage` (Task 6 of the backend plan); `hookStatusToken` return union (`success|warning|muted`) used consistently in `status.ts` + the pane; query key prefix `["integrations", clinicId]` consistent across `useHooks`/`useRetryHook`/`useCancelHook`.
- **Placeholder scan:** none — concrete code/keys throughout. Two guarded notes (Badge variant names; SettingsShell ternary conversion) point the implementer at the exact existing files to confirm against, not at undefined work.
- **Dependency on backend:** the pane needs the recovery API (backend plan Task 6) live; sequence the backend plan first (or stub the API in dev).
