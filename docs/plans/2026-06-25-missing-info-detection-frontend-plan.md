# Missing-Information Detection — Frontend Plan (#63)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface deterministic, plain-English missing-information on patient and appointment records via one reusable calm warning card, each item one tap from a precise field-level fix.

**Architecture:** Pure, unit-testable helpers compute a typed `MissingItem[]` per entity (mirroring `computeClinicCompleteness`). A single reusable `<MissingInfoCard>` renders them — calm/amber, icon+text, collapse-when->2, auto-clear, per-item Fix. The patient card mounts on `patient-detail` (replacing #59's banner) and deep-links into a `focusField`-aware `EditPatientDialog`. The appointment helper + card are built and tested now; the appointment **mount** is gated on #139's day-of surface.

**Tech Stack:** Next.js (App Router), React + TS, react-i18next, Tailwind v4 semantic tokens, base-ui primitives, Vitest + React Testing Library, Playwright. Spec: `docs/specs/2026-06-25-missing-info-detection-design.md`. Mockups (directional) on #63.

## Global Constraints

- **Frontend-only — #63 adds no backend and no migration.** It reads existing `PatientRead` / `AppointmentRead` fields.
- **Single-source the rule (coordination with #59/#62).** The canonical predicate `isPatientComplete(p)` lives in **`src/features/patients/patient-completeness.ts`** (created by #59). #63 **imports** it and **extends that same file** with the richer `patientMissingInfo(p)`. **Do not fork the completeness rule.** If #59 has not merged when this work starts, first land #59's Task 1 (the `patient-completeness.ts` predicate) exactly as #59 specs it — do not write a second copy.
- **Canonical completeness rule (verbatim):** a patient is complete ⟺ `name` AND `phone` AND (`age` OR `date_of_birth`) AND `gender` are present. Mirrored server-side by #62's `is_complete`.
- **Honest substrate-gating.** Appointment `confirmationSent` (SP5) and `followUp` (SP6) checks are **designed in the types but never emitted** in V1 (`darkChecksEnabled` defaults `false`). A shipped check must read a real field — no vacuous/always-false check.
- **No warning on:** completion notes (Golden Rule 5.8 — never block/nag), no-show/cancel reason (#139 makes them required at the transition → cannot be missing).
- **Plain language, never field codes** in any user-visible string. Calm **warning** tone — amber/attention tokens, **never** destructive red.
- **Rule 17.0:** semantic tokens only; compose `components/ui/*`; no per-page CSS or raw colours. **Both themes; mobile-first; WCAG AA** (status by icon+text, never colour-only; ≥44px targets; visible focus; contrast in both themes).
- **i18n-first:** all copy via `t()` under `missingInfo.*`; add to **both** `en.json` + `hi.json` (parity gated by `tests/e2e/i18n.spec.ts`).
- `npx tsc --noEmit` + `npm run build` clean before each commit. Dev FE on **3000** (never 3001). **Render-on-:8753 sign-off before building UI; the FE PR is HELD for user QA.**
- **Dependencies owned by other issues (NOT tasks here):** (a) **#59** must make `age`/`date_of_birth` nullable so quick-add patients can persist and the age check is meaningful; (b) **#62** must mirror the canonical rule server-side in `is_complete`; (c) **#139** must provide the appointment day-of surface that hosts the appointment card.

---

### Task 1: `patientMissingInfo` helper + shared `MissingItem` types

**Files:**
- Create: `src/lib/missing-info.ts` (types only — no logic)
- Modify: `src/features/patients/patient-completeness.ts` (add `patientMissingInfo`; this file already exists from #59 with `isPatientComplete`)
- Test: `src/features/patients/__tests__/patient-missing-info.test.ts`

**Interfaces:**
- Consumes: `isPatientComplete(p)` from `src/features/patients/patient-completeness.ts` (#59).
- Produces:
  - `src/lib/missing-info.ts`: `type MissingTier = "attention" | "complete"`; `type FixTarget = { kind: "patientField"; field: string } | { kind: "appointmentField"; field: string } | { kind: "none" }`; `interface MissingItem { code: string; labelKey: string; tier: MissingTier; completenessMember: boolean; fixTarget: FixTarget }`.
  - `patientMissingInfo(p: PatientLike): MissingItem[]` — attention-first ordered list of missing patient items.

- [ ] **Step 1: Write the failing test**

```ts
// src/features/patients/__tests__/patient-missing-info.test.ts
import { describe, it, expect } from "vitest";
import { patientMissingInfo } from "../patient-completeness";
import { isPatientComplete } from "../patient-completeness";

const complete = {
  name: "Riya", phone: "+919800000000", age: 30, date_of_birth: null,
  gender: "female", medical_conditions: "None", referral_source: "Google",
};

describe("patientMissingInfo", () => {
  it("returns [] for a fully-populated patient", () => {
    expect(patientMissingInfo(complete as never)).toEqual([]);
  });

  it("flags a quick-add patient (name+phone only) with attention-first ordering", () => {
    const p = { ...complete, age: null, date_of_birth: null, gender: null,
                medical_conditions: null, referral_source: null };
    const codes = patientMissingInfo(p as never).map((i) => i.code);
    // attention tier first (phone present here, so medicalHistory leads), then complete tier
    expect(codes).toEqual([
      "patient.medicalHistory", "patient.age", "patient.gender", "patient.referralSource",
    ]);
  });

  it("flags phone first when phone is the missing attention item", () => {
    const p = { ...complete, phone: null };
    expect(patientMissingInfo(p as never)[0].code).toBe("patient.phone");
  });

  it("tags completeness members correctly (phone/age/gender yes; medicalHistory/referral no)", () => {
    const p = { ...complete, phone: null, age: null, gender: null,
                medical_conditions: null, referral_source: null };
    const byCode = Object.fromEntries(patientMissingInfo(p as never).map((i) => [i.code, i.completenessMember]));
    expect(byCode["patient.phone"]).toBe(true);
    expect(byCode["patient.age"]).toBe(true);
    expect(byCode["patient.gender"]).toBe(true);
    expect(byCode["patient.medicalHistory"]).toBe(false);
    expect(byCode["patient.referralSource"]).toBe(false);
  });

  it("INVARIANT: isPatientComplete(p) === no completeness-member items", () => {
    for (const p of [complete, { ...complete, phone: null }, { ...complete, medical_conditions: null }]) {
      const noMembers = patientMissingInfo(p as never).every((i) => !i.completenessMember);
      expect(isPatientComplete(p as never)).toBe(noMembers);
    }
  });

  it("each item carries a patientField fix target", () => {
    const p = { ...complete, phone: null };
    expect(patientMissingInfo(p as never)[0].fixTarget).toEqual({ kind: "patientField", field: "phone" });
  });
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run src/features/patients/__tests__/patient-missing-info.test.ts`
Expected: FAIL — `patientMissingInfo` is not exported.

- [ ] **Step 3: Create the types module**

```ts
// src/lib/missing-info.ts
export type MissingTier = "attention" | "complete";

export type FixTarget =
  | { kind: "patientField"; field: string }
  | { kind: "appointmentField"; field: string }
  | { kind: "none" };

export interface MissingItem {
  code: string;            // stable, never shown to users
  labelKey: string;        // i18n key → plain-English label
  tier: MissingTier;       // display ordering/emphasis only
  completenessMember: boolean; // true ⟺ participates in the canonical completeness rule
  fixTarget: FixTarget;
}
```

- [ ] **Step 4: Add `patientMissingInfo` to the existing #59 helper file**

```ts
// src/features/patients/patient-completeness.ts  (ADD below the existing #59 isPatientComplete)
import type { MissingItem, MissingTier } from "@/lib/missing-info";

function filled(v: unknown): boolean {
  if (typeof v === "number") return Number.isFinite(v);
  return typeof v === "string" && v.trim().length > 0;
}

type PatientFieldRule = {
  code: string; field: string; tier: MissingTier; completenessMember: boolean;
  present: (p: PatientLike) => boolean;
};

// Order encodes intra-tier priority; the sort below puts attention ahead of complete.
const PATIENT_RULES: PatientFieldRule[] = [
  { code: "patient.phone", field: "phone", tier: "attention", completenessMember: true,
    present: (p) => filled(p.phone) },
  { code: "patient.medicalHistory", field: "medical_conditions", tier: "attention", completenessMember: false,
    present: (p) => filled(p.medical_conditions) },
  { code: "patient.age", field: "age", tier: "complete", completenessMember: true,
    present: (p) => filled(p.age) || filled(p.date_of_birth) },
  { code: "patient.gender", field: "gender", tier: "complete", completenessMember: true,
    present: (p) => filled(p.gender) },
  { code: "patient.referralSource", field: "referral_source", tier: "complete", completenessMember: false,
    present: (p) => filled(p.referral_source) },
];

const TIER_ORDER: Record<MissingTier, number> = { attention: 0, complete: 1 };

export function patientMissingInfo(p: PatientLike): MissingItem[] {
  return PATIENT_RULES
    .filter((r) => !r.present(p))
    .sort((a, b) => TIER_ORDER[a.tier] - TIER_ORDER[b.tier])
    .map((r) => ({
      code: r.code,
      labelKey: `missingInfo.${r.code}`,
      tier: r.tier,
      completenessMember: r.completenessMember,
      fixTarget: { kind: "patientField", field: r.field },
    }));
}
```

> If `PatientLike` (from #59) lacks `date_of_birth` / `medical_conditions` / `referral_source`, widen that type in the same file to include them as `string | number | null | undefined` — these are existing `PatientRead` fields.

- [ ] **Step 5: Run test to verify it passes**

Run: `npx vitest run src/features/patients/__tests__/patient-missing-info.test.ts`
Expected: PASS (all 6).

- [ ] **Step 6: Typecheck + commit**

```bash
npx tsc --noEmit
git add src/lib/missing-info.ts src/features/patients/patient-completeness.ts src/features/patients/__tests__/patient-missing-info.test.ts
git commit -m "feat(#63): patientMissingInfo helper + MissingItem types (single-sourced on #59 rule)"
```

---

### Task 2: `appointmentMissingInfo` helper (reason live; confirmation/follow-up dark)

**Files:**
- Create: `src/features/scheduling/appointment-completeness.ts`
- Test: `src/features/scheduling/__tests__/appointment-missing-info.test.ts`

**Interfaces:**
- Consumes: `MissingItem` from `@/lib/missing-info`.
- Produces: `appointmentMissingInfo(a: AppointmentLike, opts?: { darkChecksEnabled?: boolean }): MissingItem[]`. `AppointmentLike = { chief_complaint?: string | null }` (extend as #139 adds fields).

- [ ] **Step 1: Write the failing test**

```ts
// src/features/scheduling/__tests__/appointment-missing-info.test.ts
import { describe, it, expect } from "vitest";
import { appointmentMissingInfo } from "../appointment-completeness";

describe("appointmentMissingInfo", () => {
  it("flags a missing reason (live check)", () => {
    const items = appointmentMissingInfo({ chief_complaint: null });
    expect(items.map((i) => i.code)).toEqual(["appointment.reason"]);
    expect(items[0].fixTarget).toEqual({ kind: "appointmentField", field: "chief_complaint" });
  });

  it("returns [] when reason is present", () => {
    expect(appointmentMissingInfo({ chief_complaint: "Toothache" })).toEqual([]);
  });

  it("NEVER emits dark checks by default (confirmation/follow-up reserved)", () => {
    const items = appointmentMissingInfo({ chief_complaint: "Toothache" });
    expect(items.find((i) => i.code === "appointment.confirmationSent")).toBeUndefined();
    expect(items.find((i) => i.code === "appointment.followUp")).toBeUndefined();
  });

  it("emits dark checks only when explicitly enabled (forward-compat, fixTarget none until wired)", () => {
    const items = appointmentMissingInfo({ chief_complaint: "Toothache" }, { darkChecksEnabled: true });
    const dark = items.filter((i) => i.code.startsWith("appointment.") && i.fixTarget.kind === "none");
    expect(dark.map((i) => i.code).sort()).toEqual(["appointment.confirmationSent", "appointment.followUp"]);
  });
});
```

- [ ] **Step 2: Run → fail.** `npx vitest run src/features/scheduling/__tests__/appointment-missing-info.test.ts` → module not found.

- [ ] **Step 3: Implement**

```ts
// src/features/scheduling/appointment-completeness.ts
import type { MissingItem } from "@/lib/missing-info";

export type AppointmentLike = { chief_complaint?: string | null };

function filled(v: unknown): boolean {
  return typeof v === "string" && v.trim().length > 0;
}

export function appointmentMissingInfo(
  a: AppointmentLike,
  opts: { darkChecksEnabled?: boolean } = {},
): MissingItem[] {
  const items: MissingItem[] = [];

  if (!filled(a.chief_complaint)) {
    items.push({
      code: "appointment.reason",
      labelKey: "missingInfo.appointment.reason",
      tier: "attention",
      completenessMember: false,
      fixTarget: { kind: "appointmentField", field: "chief_complaint" },
    });
  }

  // Reserved/dark — designed, not wired. Never emitted unless a future caller opts in
  // AND the backing column exists (SP5 confirmation_sent / SP6 follow-up).
  if (opts.darkChecksEnabled) {
    for (const code of ["appointment.confirmationSent", "appointment.followUp"]) {
      items.push({
        code, labelKey: `missingInfo.${code}`, tier: "attention",
        completenessMember: false, fixTarget: { kind: "none" },
      });
    }
  }

  return items;
}
```

- [ ] **Step 4: Run → pass.** `npx vitest run src/features/scheduling/__tests__/appointment-missing-info.test.ts` → PASS (4).

- [ ] **Step 5: Typecheck + commit**

```bash
npx tsc --noEmit
git add src/features/scheduling/appointment-completeness.ts src/features/scheduling/__tests__/appointment-missing-info.test.ts
git commit -m "feat(#63): appointmentMissingInfo (reason live; confirmation/follow-up dark-reserved)"
```

---

### Task 3: i18n strings — `missingInfo.*` (en + hi parity)

**Files:**
- Modify: `src/i18n/locales/en.json`, `src/i18n/locales/hi.json`

**Interfaces:**
- Produces: i18n keys consumed by Tasks 4–6: `missingInfo.cardTitle`, `missingInfo.cardSubtitle`, `missingInfo.summary` (`{{count}}`), `missingInfo.fix`, `missingInfo.patient.phone`, `missingInfo.patient.medicalHistory`, `missingInfo.patient.age`, `missingInfo.patient.gender`, `missingInfo.patient.referralSource`, `missingInfo.appointment.reason`.

- [ ] **Step 1: Add the `missingInfo` block to `en.json`**

```json
"missingInfo": {
  "cardTitle": "A few details are missing",
  "cardSubtitle": "Tap to add them whenever you like — nothing is blocked.",
  "summary": "{{count}} details missing",
  "fix": "Fix",
  "patient": {
    "phone": "Phone number missing",
    "medicalHistory": "Medical history missing",
    "age": "Age or date of birth missing",
    "gender": "Gender missing",
    "referralSource": "Referral source missing"
  },
  "appointment": {
    "reason": "Reason for visit missing"
  }
}
```

- [ ] **Step 2: Add the parity block to `hi.json`** (same keys, Hindi values)

```json
"missingInfo": {
  "cardTitle": "कुछ विवरण अधूरे हैं",
  "cardSubtitle": "जब चाहें तब जोड़ें — कुछ भी रुका हुआ नहीं है।",
  "summary": "{{count}} विवरण अधूरे हैं",
  "fix": "ठीक करें",
  "patient": {
    "phone": "फ़ोन नंबर अधूरा है",
    "medicalHistory": "चिकित्सा इतिहास अधूरा है",
    "age": "आयु या जन्म तिथि अधूरी है",
    "gender": "लिंग अधूरा है",
    "referralSource": "संदर्भ स्रोत अधूरा है"
  },
  "appointment": {
    "reason": "मुलाक़ात का कारण अधूरा है"
  }
}
```

- [ ] **Step 3: Verify key parity**

Run: `npx vitest run tests/e2e/i18n.spec.ts` (or the project's i18n-parity test)
Expected: PASS — en and hi have identical key sets.

- [ ] **Step 4: Commit**

```bash
git add src/i18n/locales/en.json src/i18n/locales/hi.json
git commit -m "feat(#63): missingInfo.* i18n strings (en+hi parity)"
```

---

### Task 4: `<MissingInfoCard>` component (calm, collapse->2, auto-clear, per-item Fix)

**Files:**
- Create: `src/components/missing-info-card.tsx`
- Test: `src/components/__tests__/missing-info-card.test.tsx`

**Interfaces:**
- Consumes: `MissingItem` (`@/lib/missing-info`); i18n `missingInfo.*` (Task 3).
- Produces: `<MissingInfoCard items={MissingItem[]} onFix={(item: MissingItem) => void} />` — renders nothing when `items` is empty; collapses to a one-line summary when `items.length > 2`; each row has an accessible Fix button.

- [ ] **Step 1: Write the failing test**

```tsx
// src/components/__tests__/missing-info-card.test.tsx
import { describe, it, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { MissingInfoCard } from "../missing-info-card";
import type { MissingItem } from "@/lib/missing-info";

const item = (code: string): MissingItem => ({
  code, labelKey: `missingInfo.${code}`, tier: "attention",
  completenessMember: true, fixTarget: { kind: "patientField", field: "phone" },
});

describe("MissingInfoCard", () => {
  it("renders nothing when there are no items (auto-clear)", () => {
    const { container } = render(<MissingInfoCard items={[]} onFix={() => {}} />);
    expect(container).toBeEmptyDOMElement();
  });

  it("shows each item with a Fix button when <= 2 items", () => {
    render(<MissingInfoCard items={[item("patient.phone")]} onFix={() => {}} />);
    expect(screen.getByText("Phone number missing")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: /fix/i })).toBeInTheDocument();
  });

  it("collapses to a summary when > 2 items and expands on click", () => {
    const items = [item("patient.phone"), item("patient.age"), item("patient.gender")];
    render(<MissingInfoCard items={items} onFix={() => {}} />);
    expect(screen.getByText("3 details missing")).toBeInTheDocument();
    expect(screen.queryByText("Phone number missing")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /3 details missing/i }));
    expect(screen.getByText("Phone number missing")).toBeInTheDocument();
  });

  it("calls onFix with the item when Fix is clicked", () => {
    const onFix = vi.fn();
    const it0 = item("patient.phone");
    render(<MissingInfoCard items={[it0]} onFix={onFix} />);
    fireEvent.click(screen.getByRole("button", { name: /fix/i }));
    expect(onFix).toHaveBeenCalledWith(it0);
  });
});
```

- [ ] **Step 2: Run → fail.** `npx vitest run src/components/__tests__/missing-info-card.test.tsx` → module not found.

- [ ] **Step 3: Implement** (semantic tokens only; icon+text; status not colour-only; ≥44px Fix)

```tsx
// src/components/missing-info-card.tsx
"use client";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { AlertCircle, ChevronDown } from "lucide-react";
import { Button } from "@/components/ui/button";
import type { MissingItem } from "@/lib/missing-info";

export function MissingInfoCard({
  items, onFix,
}: { items: MissingItem[]; onFix: (item: MissingItem) => void }) {
  const { t } = useTranslation();
  const collapsible = items.length > 2;
  const [open, setOpen] = useState(!collapsible);

  if (items.length === 0) return null; // auto-clear

  return (
    <section
      aria-label={t("missingInfo.cardTitle")}
      className="rounded-lg border border-border bg-accent/40 text-accent-foreground p-4"
    >
      <div className="flex items-start gap-2">
        <AlertCircle className="mt-0.5 size-5 shrink-0" aria-hidden="true" />
        <div className="flex-1">
          <p className="font-medium">{t("missingInfo.cardTitle")}</p>
          <p className="text-sm text-muted-foreground">{t("missingInfo.cardSubtitle")}</p>

          {collapsible && !open ? (
            <button
              type="button"
              onClick={() => setOpen(true)}
              className="mt-2 inline-flex items-center gap-1 text-sm font-medium underline-offset-2 hover:underline min-h-11"
            >
              {t("missingInfo.summary", { count: items.length })}
              <ChevronDown className="size-4" aria-hidden="true" />
            </button>
          ) : (
            <ul className="mt-3 space-y-2">
              {items.map((item) => (
                <li key={item.code} className="flex items-center justify-between gap-3">
                  <span className="flex items-center gap-2 text-sm">
                    <AlertCircle className="size-4 shrink-0" aria-hidden="true" />
                    {t(item.labelKey)}
                  </span>
                  <Button
                    type="button"
                    variant="outline"
                    size="sm"
                    className="min-h-11"
                    onClick={() => onFix(item)}
                  >
                    {t("missingInfo.fix")}
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </section>
  );
}
```

> Confirm `Button` import path and `lucide-react` icon availability against the repo; swap to the project's existing icon set/button if different. No raw colours — `bg-accent`/`text-accent-foreground`/`border-border`/`text-muted-foreground` only.

- [ ] **Step 4: Run → pass.** `npx vitest run src/components/__tests__/missing-info-card.test.tsx` → PASS (4).

- [ ] **Step 5: Typecheck + commit**

```bash
npx tsc --noEmit
git add src/components/missing-info-card.tsx src/components/__tests__/missing-info-card.test.tsx
git commit -m "feat(#63): reusable MissingInfoCard (calm, collapse, auto-clear, per-item Fix)"
```

---

### Task 5: `focusField` on `EditPatientDialog`

**Files:**
- Modify: `src/features/patients/patient-detail.tsx` (`EditPatientDialog`, ~lines 76–392)
- Test: `src/features/patients/__tests__/edit-patient-focus.test.tsx`

**Interfaces:**
- Produces: `EditPatientDialog` accepts an optional `focusField?: string` prop; when the dialog opens with it set, that field's input receives focus (and is scrolled into view).

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/patients/__tests__/edit-patient-focus.test.tsx
import { describe, it, expect } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import { EditPatientDialog } from "../patient-detail";

// Render the dialog open with focusField="phone"; assert the phone input is focused.
// (Wrap in the repo's QueryClient/i18n providers per existing patient-detail tests.)
describe("EditPatientDialog focusField", () => {
  it("focuses the named field when opened", async () => {
    render(<EditPatientDialog open patient={{ /* minimal fixture */ } as never} focusField="phone" onOpenChange={() => {}} />);
    await waitFor(() => expect(screen.getByLabelText(/phone/i)).toHaveFocus());
  });
});
```

- [ ] **Step 2: Run → fail.** `npx vitest run src/features/patients/__tests__/edit-patient-focus.test.tsx` → `focusField` not handled / input not focused.

- [ ] **Step 3: Implement** — thread `focusField` into `EditPatientDialog` and focus on open

```tsx
// Inside EditPatientDialog props:
// focusField?: string;

// Add inside the component (after refs/form setup):
import { useEffect, useRef } from "react";
const fieldRefs = useRef<Record<string, HTMLElement | null>>({});

useEffect(() => {
  if (!open || !focusField) return;
  const el = fieldRefs.current[focusField];
  if (el) {
    el.scrollIntoView({ block: "center" });
    (el as HTMLInputElement).focus();
  }
}, [open, focusField]);

// On each editable field, register its ref, e.g. for phone:
//   ref={(el) => { fieldRefs.current["phone"] = el; }}
// Register: phone, medical_conditions, age, gender, referral_source.
```

> Match the existing field markup (react-hook-form `register` / controlled inputs). For non-`<input>` controls (e.g. a select for gender), focus the trigger element. Keep changes surgical — only add the ref + effect; do not refactor the form.

- [ ] **Step 4: Run → pass.** `npx vitest run src/features/patients/__tests__/edit-patient-focus.test.tsx` → PASS.

- [ ] **Step 5: Typecheck + commit**

```bash
npx tsc --noEmit
git add src/features/patients/patient-detail.tsx src/features/patients/__tests__/edit-patient-focus.test.tsx
git commit -m "feat(#63): EditPatientDialog focusField — open focused on one field"
```

---

### Task 6: Mount the patient card on `patient-detail` + wire Fix (replaces #59 banner)

**Files:**
- Modify: `src/features/patients/patient-detail.tsx` (top of the record / Overview; remove #59's generic banner)
- Test: `src/features/patients/__tests__/patient-detail-missing-info.test.tsx`

**Interfaces:**
- Consumes: `patientMissingInfo` (Task 1), `<MissingInfoCard>` (Task 4), `EditPatientDialog` `focusField` (Task 5).

- [ ] **Step 1: Write the failing test**

```tsx
// src/features/patients/__tests__/patient-detail-missing-info.test.tsx
import { describe, it, expect } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { PatientDetail } from "../patient-detail"; // adjust to the exported component name

// Provide an incomplete patient (no phone). Wrap in the repo's providers as existing tests do.
describe("patient-detail missing-info card", () => {
  it("shows the card for an incomplete patient and opens the edit dialog focused on Fix", async () => {
    render(<PatientDetail /* clinicId/patientId or fixture per existing tests, patient missing phone */ />);
    expect(await screen.findByText("Phone number missing")).toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: /fix/i }));
    await waitFor(() => expect(screen.getByLabelText(/phone/i)).toHaveFocus());
  });

  it("does not render the old generic banner", () => {
    // assert the #59 banner copy is gone (single source = the card)
    expect(screen.queryByText(/please complete patient details/i)).not.toBeInTheDocument();
  });
});
```

- [ ] **Step 2: Run → fail.** Card not mounted yet.

- [ ] **Step 3: Implement** — compute items, render the card atop the record, route Fix → focused dialog; delete the #59 banner

```tsx
// In patient-detail.tsx, where the patient (PatientRead) is available:
import { patientMissingInfo } from "./patient-completeness";
import { MissingInfoCard } from "@/components/missing-info-card";
import type { MissingItem } from "@/lib/missing-info";

// state for the focused edit:
const [editFocusField, setEditFocusField] = useState<string | undefined>(undefined);

function handleFix(item: MissingItem) {
  if (item.fixTarget.kind === "patientField") {
    setEditFocusField(item.fixTarget.field);
    setEditOpen(true); // reuse the existing edit-dialog open state
  }
}

// Near the top of the record (Overview), replacing the removed #59 banner:
<MissingInfoCard items={patientMissingInfo(patient)} onFix={handleFix} />

// Pass focusField into the existing dialog and clear it on close:
<EditPatientDialog
  open={editOpen}
  patient={patient}
  focusField={editFocusField}
  onOpenChange={(o) => { setEditOpen(o); if (!o) setEditFocusField(undefined); }}
/>
```

> **Remove** the #59 "Please complete patient details" banner block — the card supersedes it (single source). Keep #59's Patients-list **!** badge untouched.

- [ ] **Step 4: Run → pass.** `npx vitest run src/features/patients/__tests__/patient-detail-missing-info.test.tsx` → PASS.

- [ ] **Step 5: Typecheck, build, commit**

```bash
npx tsc --noEmit && npm run build
git add src/features/patients/patient-detail.tsx src/features/patients/__tests__/patient-detail-missing-info.test.tsx
git commit -m "feat(#63): mount missing-info card on patient-detail; replace #59 banner; wire focused Fix"
```

---

### Task 7: e2e — patient missing-info, focused fix, auto-clear (Playwright, mocked)

**Files:**
- Create: `tests/e2e/patient-missing-info.spec.ts`

- [ ] **Step 1: Write the e2e spec** (mock an incomplete patient; assert card → focused fix → completion clears it)

```ts
// tests/e2e/patient-missing-info.spec.ts
import { test, expect } from "@playwright/test";
// Reuse the repo's auth/clinic mock setup from an existing patients e2e spec.

test("incomplete patient shows calm card; fixing phone clears it", async ({ page }) => {
  // Arrange: route GET patient to an incomplete record (no phone), then navigate to patient-detail.
  await page.goto("/patients/PATIENT_ID"); // per existing patient-detail route

  // Card visible, attention-first (phone leads when missing)
  await expect(page.getByText("Phone number missing")).toBeVisible();

  // Fix → edit dialog focused on phone
  await page.getByRole("button", { name: /fix/i }).first().click();
  await expect(page.getByLabel(/phone/i)).toBeFocused();

  // Fill + save → mock now returns a complete patient → card auto-clears
  await page.getByLabel(/phone/i).fill("+919800000000");
  await page.getByRole("button", { name: /save/i }).click();
  await expect(page.getByText("Phone number missing")).toHaveCount(0);
});
```

- [ ] **Step 2: Run** `npm run test:e2e -- patient-missing-info` → PASS (adjust selectors/mocks to repo conventions).

- [ ] **Step 3: Commit**

```bash
git add tests/e2e/patient-missing-info.spec.ts
git commit -m "test(#63): e2e patient missing-info card → focused fix → auto-clear"
```

---

### Task 8 (GATED on #139): mount the appointment missing-info card

> **Do not start until #139's day-of appointment surface exists.** The helper (`appointmentMissingInfo`, Task 2) and the card (Task 4) are already built and tested; this task only **mounts** the appointment instance and wires the reason-fix deep-link into #139's appointment edit affordance.

**Files:**
- Modify: the #139 appointment day-of surface component (path TBD by #139)
- Test: a component test alongside the #139 surface

- [ ] **Step 1:** Render `<MissingInfoCard items={appointmentMissingInfo(appointment)} onFix={handleFix} />` on the #139 surface.
- [ ] **Step 2:** `handleFix` for `fixTarget.kind === "appointmentField"` opens #139's appointment edit focused on `chief_complaint` (reuse #139's edit affordance; do not build a new one).
- [ ] **Step 3:** Component test: appointment with no `chief_complaint` shows "Reason for visit missing"; Fix opens the reason editor focused. Commit.

---

## Self-Review

**Spec coverage:**
- Itemized warning card on patient page (calm, not error) → Tasks 4, 6. ✅
- Jump straight to the missing field → Tasks 5, 6 (`focusField`). ✅
- Deterministic, no AI → Tasks 1, 2 (pure helpers). ✅
- Single-sourced rule + parity guard with #62 → Task 1 (imports #59 predicate; INVARIANT test). ✅
- Appointment reason live; confirmation/follow-up dark → Task 2. ✅
- Appointment card mounts on #139 surface → Task 8 (gated). ✅
- M3/Rule 17.0, both themes, a11y, i18n en/hi → Tasks 3, 4 + Global Constraints. ✅
- No nag on completion notes / no-show reason → not implemented as checks (Global Constraints), enforced by Task 2 scope. ✅
- `age NOT NULL` dependency on #59 → Global Constraints (dependency, not a task). ✅
- Record-level only (no new aggregate) → no aggregate task; #62 owns it. ✅

**Placeholder scan:** Task 8's surface path is intentionally `TBD by #139` (a real external dependency, not a deferral of #63 work); all #63-owned tasks carry complete code. Fixtures in tests reference "per existing spec" only for provider/mock wiring that already exists in the repo's patient tests.

**Type consistency:** `MissingItem` / `MissingTier` / `FixTarget` defined once in `src/lib/missing-info.ts` (Task 1), imported unchanged by Tasks 2, 4, 6, 8. `patientMissingInfo` / `appointmentMissingInfo` / `MissingInfoCard` / `EditPatientDialog.focusField` signatures match across producing and consuming tasks. ✅
