# Design System & UX Philosophy

The product-wide design system and UX philosophy for the Register System — **product-agnostic
and reusable across any modern SaaS** (web + native iOS + Android). This is the source of truth
for all UI work; **the design-system foundation must be implemented before any further feature
screens** (see the roadmap).

## Documents
1. **[01 — Design Philosophy](01-design-philosophy.md)** — how the product should look, feel, and
   behave (Linear × Stripe; modern, clean, fast, calm, professional, premium); visual &
   interaction philosophy; anti-patterns; mobile-first & dark-mode-first stance.
2. **[02 — Design System](02-design-system.md)** — the specification: design tokens (color,
   typography, spacing, radius, elevation, motion), component standards (all core components),
   and accessibility standards (WCAG 2.1 AA).
3. **[03 — Theme System](03-theme-system.md)** — light / dark / follow-system architecture,
   color-token strategy (semantic CSS variables, no hardcoded colors), switching (`next-themes`),
   persistence, and the both-themes requirement.
4. **[04 — Cross-Platform Guidelines](04-cross-platform-guidelines.md)** — web / iOS / Android:
   what must stay identical vs. what may vary; mobile-first; shared tokens.
5. **[05 — UI Implementation Roadmap](05-ui-implementation-roadmap.md)** — phased rollout
   (foundation → component library → app shell → feature screens), with screen work deferred
   until the foundation lands.

Implementation plan (Phase 0): `../docs/plans/2026-06-18-design-system-foundation-plan.md`.

## Core principles (at a glance)
- **Linear × Stripe**, neutral-forward; **color communicates state & action, not decoration**
  (calm **indigo** is the single semantic accent).
- **Whitespace over separators**; hierarchy via spacing/typography/layout, not chrome.
- **Mobile-first**; desktop derived from mobile workflows.
- **Light / Dark / System are all first-class**; **dark mode is a primary target**.
- **Semantic design tokens only — no hardcoded colors**; every component works in both themes.
- **Accessibility is built-in** (AA contrast, keyboard, ≥44px touch targets, responsive, readable).
- **Same product across platforms**: identical terminology, identity, navigation concepts, and
  component behavior; platform-native patterns may vary.

## Summary of changes (this design-system establishment)
- Added this `Design/` set (docs 01–05) + the Phase-0 implementation plan.
- **PRD §40** (Design & UX Philosophy) and **Golden Rules §17** (UI & Design System rules) added.
- **Tech stack** updated with the theming/token foundation (Tailwind CSS-variable semantic
  tokens + `next-themes` + shadcn aligned to tokens).
- Board: a **Design System Foundation** UI work item created as the **next UI task**; feature
  screen work (e.g., SP2 Core entities UI) is **explicitly deferred** until the foundation is done.
