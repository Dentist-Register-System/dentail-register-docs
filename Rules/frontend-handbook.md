# Frontend Engineering Handbook

The binding **code-quality bar** for the Register frontend (Next.js App Router, React 19 + Compiler,
strict TypeScript, Tailwind v4 semantic tokens, TanStack Query, react-i18next, base-ui, Playwright).
Pointed to by **Golden Rule §17.8**; consult it for any FE code work.

**How this fits the other docs** — read this for *how the code is written*; the others own their lanes,
and this handbook **points** to them rather than restating (single source of truth):

- **UX / usability** → `testing/ux-standards-runbook.md` (NN/g, WCAG 2.2 AA, M3/HIG, Baymard).
- **Design system** → Golden §17 + `Design/`. **i18n** → Golden §16.
- **Decisions / permissions** → `Rules/sentinel-rules.md`. **Testing** → Golden §10.

This handbook adds the engineering bars those don't cover and links out where they do.

**The enforcement ladder.** A bar is only as real as its strongest enforceable form. Reach for the
highest rung that fits, in order — prose here is the *last* line of defence, not the first:

1. **Structure** — one module makes the wrong thing impossible (the strongest).
2. **CI guard** — a failing check (e.g. `sentinel-guard`).
3. **Lint / type rule** — eslint or `tsc`, failing the build.
4. **Review check** — a reviewer catches it.
5. **Forward-invariant comment** — state *why the right thing is right* at the tempting site; never a
   "removed X smell" changelog (that rots — git already records removals).

---

## 1. Type safety
- `tsconfig` `strict` stays on. No `any` — use `unknown` + narrowing, or a precise type.
- Model variants and state as **discriminated unions**, not loose strings plus booleans.
- Validate every external boundary with **zod**: API responses, form input, `env`. Parse, don't assume.
- No `as` cast or non-null `!` without a one-line reason; never `as any`.
- Source: [TypeScript handbook](https://www.typescriptlang.org/docs/handbook/), [typescript-eslint](https://typescript-eslint.io/rules/).
- Enforce: `tsconfig strict` (structure) · eslint `@typescript-eslint/no-explicit-any` = error · review for `as`/`!`.

## 2. Components & composition
- One responsibility per component; extract when it grows a second.
- **Composition over configuration** — children/slots beat a pile of boolean props.
- Separate presentational components from data/container components.
- No prop-drilling past one level — lift to a query or context.
- Source: [react.dev](https://react.dev/learn/thinking-in-react).
- Enforce: review · file-size sanity (split well before a component sprawls).

## 3. State & data flow
- **Server state lives in TanStack Query, never `useState`.** One query key per resource (`lib/query-keys.ts`); mutations invalidate through the central helper (`lib/invalidate.ts`).
- **One source of truth** — derive during render; never mirror a prop or query result into `useState`.
- Colocate state at the lowest common owner; lift only when genuinely shared.
- Put shareable / bookmarkable state in the URL.
- Source: [react.dev — You Might Not Need an Effect](https://react.dev/learn/you-might-not-need-an-effect), [TanStack Query](https://tanstack.com/query/latest/docs/framework/react/overview).
- Enforce: the cache-invalidation eslint rule (in `eslint.config.mjs`) · review.

## 4. Effects & React-Compiler purity
- Components and hooks are **pure**: same inputs → same output, no side effects in render. **No `Date.now()` / `Math.random()` / argless `new Date()` in render** — pass time in, or compute in an effect/event.
- Effects synchronize with **external** systems only. Do **not** use an effect to derive state, transform props, or `setState` in a cascade (the `set-state-in-effect` smell).
- Rules of Hooks: call them at the top level, before any early return.
- Let the **React Compiler** memoize — don't hand-roll `useMemo` / `useCallback` that fights it.
- Source: [Rules of React](https://react.dev/reference/rules), [Components and Hooks must be pure](https://react.dev/reference/rules/components-and-hooks-must-be-pure), [purity lint](https://react.dev/reference/eslint-plugin-react-hooks/lints/purity).
- Enforce: `eslint-plugin-react-hooks` (React-Compiler rules) → **error**, after the `react-compiler-correctness` cleanup PR.

## 5. Decision centralization
- Each domain decision lives in **exactly one module** — enum→token/label mappers, predicates, capability reads. Never re-interpret the same enum (`status === "…"`) across components. Pattern: `slot-state.ts`, `request-status.ts`.
- The FE **asks the backend** for permissions and reads the answer; it never compares roles to decide (PDP/PEP).
- Source: `Rules/sentinel-rules.md`.
- Enforce: `sentinel-guard` (CI) · structure (one module) · a scattered-status guard (proposed).

## 6. Styling & design system → Golden §17
Semantic tokens only (no raw colours), compose AppShell + templates + components (no per-page CSS),
both themes AA. The bar is **Golden §17** + `Design/` — follow it; nothing restated here.
- Enforce: review · raw-colour guard (the tree is at ~0 raw colours — keep it).

## 7. Accessibility → UX runbook
WCAG 2.2 AA, semantic HTML first, full keyboard + visible focus, ARIA only when semantics fall short,
a reduced-motion alternative for every animation, ≥44px targets, never colour-only meaning. Canonical
bar = `testing/ux-standards-runbook.md`.
- Source: [WCAG 2.2](https://www.w3.org/TR/WCAG22/).
- Enforce: add `eslint-plugin-jsx-a11y` · the UX runbook's `[AUTO]` checks.

## 8. Performance — Core Web Vitals budgets
- Field budgets (p75): **LCP < 2.5 s · INP < 200 ms · CLS < 0.1**.
- Animate **transform / opacity only** — never layout properties (width/height/top); reserve space to avoid layout shift.
- Keep `'use client'` to the **smallest island**; data and layout stay server-side where practical.
- Avoid request waterfalls (fetch in parallel); code-split heavy / below-fold; `next/image` for images.
- Source: [web.dev — CWV thresholds](https://web.dev/articles/defining-core-web-vitals-thresholds), [Next.js production checklist](https://nextjs.org/docs/app/guides/production-checklist).
- Enforce: review · (later) a Lighthouse / CWV CI check.

## 9. i18n → Golden §16
`t()` keys for all user-facing text (no hardcoded strings), backend returns stable codes the FE
translates, en + hi parity on every key. Bar = **Golden §16**.
- Enforce: no-hardcoded-string guard (proposed) · review.

## 10. Error, loading & empty states
- Every async surface ships **all three**: loading (skeleton, not a bare spinner), error (human copy + a way forward), empty (explains, never just blank).
- Route-level error boundaries; never swallow an error silently.
- Error copy follows the clarify discipline (what happened + what to do next), keyed by backend code.
- Source: [React — Suspense / error boundaries](https://react.dev/reference/react/Suspense), Nielsen heuristics #1/#9 (→ UX runbook).
- Enforce: review · journey tests assert all three states.

## 11. Forms
- React Hook Form + zod resolver; label + error association on every field; inline, forgiving validation.
- Usability bar = Baymard (→ UX runbook); multi-field creation follows the guided wizard (Golden §18.4).
- Enforce: review.

## 12. Testing honesty → Golden §10
Journeys via Playwright; **test behaviour, not implementation**; honest assertions only (no testid-only,
vacuous, or happy-path-only); mock external providers; concurrency tests for races. Bar = **Golden §10**
+ the bulletproof-e2e doctrine.
- Source: [Testing Library — Guiding Principles](https://testing-library.com/docs/guiding-principles/).
- Enforce: the e2e no-swallow / static guard · review.

## 13. Code hygiene & module boundaries
- **Feature-first boundaries**: `features/<domain>` is self-contained; cross-feature use goes through a public surface, never another feature's internals.
- No dead code, no imports inside functions, surgical diffs (every changed line traces to the task).
- Clear names; delete over comment-out; **one-place changes** — consolidate before duplicating.
- Source: `Rules/sentinel-rules.md` + Ponytail discipline.
- Enforce: add `dependency-cruiser` (boundaries) + `knip` (dead exports) · `sentinel-guard`.

## 14. Security
- No secrets in FE code or bundles; config via the validated `lib/env.ts` only.
- No `dangerouslySetInnerHTML` without sanitization; validate / escape all rendered user input.
- The FE never decides authorization — the backend enforces every mutation (PDP/PEP).
- Source: [OWASP Top Ten](https://owasp.org/www-project-top-ten/), Golden §11, `Rules/sentinel-rules.md`.
- Enforce: review · secret-scan.
