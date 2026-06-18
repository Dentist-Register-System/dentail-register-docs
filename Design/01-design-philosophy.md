<!-- Status: SUPERSEDED — being rewritten to Material 3 | Date: 2026-06-18 -->

> ⚠️ **Superseded (2026-06-18):** the Linear × Stripe direction below has been replaced by **Material 3**. See the recorded decision + interim authoritative spec: `docs/specs/2026-06-18-ui-redesign-m3-design.md`. This document is being rewritten to M3 as part of the UI redesign. Until then, treat the M3 spec as the source of truth where it conflicts with the text below.

# Design Philosophy

## Overview

This document defines the foundational design philosophy for this design system — the "why" behind every visual and interaction decision. It is product-agnostic and applies to any modern SaaS product built on this system. Token values, theme mechanics, and component specifications live in sibling documents (02, 03); this document is concerned with principles, intent, and the design culture these decisions create.

---

## 1. The Target Aesthetic: Linear × Stripe

The north star is a product that feels like **Linear** and **Stripe** built it together.

- **Linear** contributes: speed, restraint, keyboard-first thinking, dark-mode-native sensibility, and the confidence to leave whitespace unfilled.
- **Stripe** contributes: precision, professionalism, documentation-quality polish, a trust-building visual language, and the discipline to make complex workflows feel calm.

The result is a product that is simultaneously **modern, clean, fast, calm, professional, and premium** — qualities that are not in tension when design decisions are made with enough care. A product built on this system should feel instantly familiar to users who use world-class SaaS tools, and it should communicate competence before a single interaction occurs.

The aesthetic is not neutral in an undecided way — it is deliberate in its restraint. Every element that is absent is absent on purpose.

---

## 2. Visual Language

### 2.1 The Neutral-Forward Canvas

The application surface is intentionally quiet. Backgrounds, cards, and containers use neutral values — near-white in light mode, near-black in dark mode — so that the content placed on them reads with maximum clarity.

The canvas exists to serve the data, not to express itself.

### 2.2 Color Communicates State and Action, Not Decoration

Color is a **functional signal**, not an aesthetic flourish. The indigo primary exists to identify the thing you can do or the thing that is selected. Red surfaces an error. Green confirms success. Amber warns. Beyond these roles, color is withheld.

This constraint is what gives color meaning. When every interactive element is clearly distinguished from every static one, users build accurate mental models faster and make fewer mistakes. When color appears only on the things that matter, it is never ignored.

The canvas stays neutral. Indigo is not a background color. Status colors are not brand colors.

### 2.3 Whitespace Over Separators

Grouping and separation are achieved through **spacing and layout**, not through lines, borders, or boxes. A hairline border is a last resort — it means the spacing system has not been used to its full capacity.

Generous whitespace is not wasted space. It is the primary tool for communicating structure, importance, and relationship. Tight layouts feel rushed; generous layouts feel considered.

### 2.4 Hierarchy Through Spacing, Typography, and Layout — Not Chrome

Visual hierarchy is established by:

- **Size and weight**: headings are heavier and larger; body text is lighter and smaller.
- **Spacing**: important content has more room around it.
- **Position**: primary actions are in expected locations; secondary actions recede.
- **Opacity and color value**: secondary text is lighter, not a different color.

What hierarchy is never established by: decorative backgrounds, gradient fills, shadow stacks, icon collections, colored section headers, or visual complexity as a substitute for organizational clarity.

The product should be legible to someone who has never seen it before — not because it explains itself loudly, but because its structure is obvious.

### 2.5 Restraint as a Practice

Every element added to a layout must justify its presence. The correct question is not "should we add this?" but "what breaks if this is absent?" If the answer is "nothing much," the element should be absent.

Restraint is not minimalism for its own sake. It is the practice of removing friction between the user and their goal.

---

## 3. Interaction Philosophy

### 3.1 Fast and Calm

Interactions should feel **instantaneous** and **unhurried** at the same time. Transitions are quick enough to feel snappy (not sluggish), but never so abrupt that they feel broken. Motion exists to orient the user — showing where an element came from, where it went, and what it is becoming — not to entertain them.

The product should never feel like it is making the user wait, and it should never feel like it is rushing them.

### 3.2 Optimistic and Responsive

The UI responds to user intent the moment intent is expressed. Where it is safe to do so, state is updated optimistically — the interface moves forward and reconciles with the server rather than making the user wait for confirmation before showing progress.

A button pressed should feel pressed. A record saved should feel saved. Uncertainty is surfaced only when uncertainty genuinely exists.

### 3.3 Subtle Motion

Motion tokens are defined at three durations: fast (hover/press), base (enter/leave, tab switches), and slow (sheets, dialogs, page transitions). All motion uses an ease-out curve — movement accelerates from intent and decelerates into rest, like a physical object.

There is no bounce. There is no spin. There are no decorative animations. Motion is purposeful or absent. The system always respects `prefers-reduced-motion` — non-essential transforms are disabled; opacity transitions are kept.

### 3.4 Keyboard-Friendly by Default

Every interactive element is reachable and operable by keyboard alone. Focus is always visible — the focus ring is a first-class design element, not an afterthought overridden in a CSS reset. Logical tab order reflects the visual reading order. Overlays and dialogs are dismissible with Escape. No keyboard traps exist.

A power user should be able to move through a complete workflow without touching a pointer device.

### 3.5 Forgiving

The product assumes good intent and designs for recovery:

- **Errors are specific**: they name the problem and suggest a resolution; they never blame.
- **Destructive actions are confirmed**: the cost of an irreversible operation is surfaced before it is committed.
- **Undo is offered where the platform supports it**.
- **Loading is communicated honestly**: skeletons signal that content is coming; spinners signal that an action is in progress; errors always explain what happened and offer a path forward.

The user should never feel trapped, confused about what happened, or unsure whether their action succeeded.

### 3.6 Progressive Disclosure

Complexity is revealed only when it is needed. The default state of any screen shows what the user needs most often. Advanced options, secondary actions, and infrequently needed controls are available — but they do not compete for attention in the default view.

This is not hiding functionality. It is prioritizing it.

### 3.7 Content-First

The chrome — navigation, toolbars, controls — is structural scaffolding. It should recede so that the content the user is working with can be prominent. The product exists to help users accomplish goals; the interface is the path to those goals, not the destination.

---

## 4. Anti-Patterns

The following patterns are explicitly prohibited. Each entry includes a one-line corrective.

| Anti-pattern | Instead |
|---|---|
| **Enterprise / ERP look** — dense grids, heavy table borders, toolbar-heavy layouts, form-over-function aesthetics | Use generous whitespace, card-based surfaces, and task-focused layouts |
| **Legacy-software look** — beveled buttons, drop shadows as decoration, visual noise to signal "features" | Use flat or barely-elevated surfaces; let typography carry hierarchy |
| **Excessive borders** — using hairlines to separate every element, wrapping every section in a box | Use spacing to group; reach for a border only when whitespace has been exhausted |
| **Dense layouts** — minimizing whitespace to show more on screen | Trust that whitespace improves comprehension and reduces user error; fewer items in more space outperforms more items in less |
| **Visual clutter** — multiple competing calls to action, icon overuse, mixed typographic weights, competing color values | One primary action per context; icons support labels, they do not replace them; consistent weight/color usage |
| **Decorative UI** — gradients on non-illustrative surfaces, patterned backgrounds, color fills that carry no semantic meaning | If color is not communicating state or action, remove it |
| **Color-only meaning** — using red text alone to signal an error, green alone to signal success | Pair every color signal with an icon, label, or textual explanation |
| **Hardcoded colors in components** — using raw hex or rgb values instead of semantic tokens | Every color reference in a component is a semantic token; never a raw value |

---

## 5. Mobile-First as a Philosophy

Mobile-first is not a breakpoint strategy — it is a design discipline.

**The rule**: every screen, every flow, every component is designed for the smallest supported viewport first. Desktop layouts are derived from mobile layouts by adding columns, density, and surface area — not by adding new concepts.

**Why this matters**: designing desktop-first and adapting to mobile produces layouts that are fundamentally too complex for the constraints of a small screen. Designing mobile-first produces layouts that are fundamentally simple — and simplicity on desktop is a feature, not a compromise.

**Practical implications**:

- The information hierarchy on mobile is the information hierarchy everywhere. If something cannot be prioritized on a 390px screen, it should be reconsidered entirely.
- Touch targets meet a minimum of 44×44px with adequate spacing between them. Desktop inherits these comfortable targets.
- Thumb-reachability is considered from the first layout sketch. Primary actions belong in zones the thumb reaches without adjustment.
- Navigation patterns adapt to platform conventions (bottom tab bar on mobile; sidebar on desktop) while carrying identical destinations and terminology.
- Progressive enhancement describes how desktop builds on mobile, not how mobile degrades from desktop.

---

## 6. Dark Mode as a Primary Target

Dark mode is not a feature added after launch. It is not a theme applied as a coat of paint. It is a co-equal design target from the first pixel.

**Both themes are primary citizens.** Every component is designed for both light and dark simultaneously. A component that works in one theme and breaks in the other is an incomplete component.

**Why dark mode matters at the philosophy level**:

- Many users prefer dark environments for long work sessions. Treating dark mode as primary communicates respect for that preference.
- Dark mode design is harder — it requires more deliberate use of surface color, border contrast, and shadow — and doing it well elevates the perceived quality of the entire product.
- The system supports Light, Dark, and Follow-System as first-class options, with preference persisted across sessions.

**The design implication**: never design in only one theme. Every decision — spacing, contrast, elevation — must be validated against both. Dark mode uses lighter surface values (not just inverted light values) to communicate elevation, because shadows are less effective on dark canvases.

---

## 7. Cross-Platform Consistency

The same product everywhere means: the same **identity**, the same **information architecture**, the same **behavior**, and the same **accessibility commitment** — regardless of platform.

What does not need to be the same: the specific navigation pattern (web sidebar, iOS tab bar, Android bottom nav), native controls where the platform provides better ones, platform-specific gestures, and the precise expression of elevation (iOS and Android have their own depth conventions).

**The philosophy-level principle**: platform-native means native to the *platform*, not alien to the *product*. A user moving between web, iOS, and Android should feel confident they are in the same product, even if the gestures differ. Brand tokens — color, typography, spacing, radius — are shared across all surfaces. Layout patterns adapt; visual identity does not.

Detailed platform-specific guidance lives in document 04.

---

## 8. Accessibility as a Built-In Property

Accessibility is not a compliance layer applied at the end of a design process. It is a constraint that improves design for everyone.

Sufficient contrast ratios make text easier to read in every context, not just for users with visual impairments. Keyboard navigation makes power users faster. Touch target sizing makes interfaces less error-prone for all users. Clear focus states reduce cognitive load.

The design system targets WCAG 2.1 AA throughout. This is a floor, not a ceiling.

---

## 9. Self-Check Principles

A designer or engineer should be able to verify any design decision against these questions. If a decision fails more than one, it should be reconsidered.

**Visual**
- [ ] Does every use of color communicate state, action, or semantic meaning — or is it decoration?
- [ ] Is hierarchy established through spacing and typography, without relying on borders or fills?
- [ ] Is there enough whitespace that the layout breathes, or has whitespace been compressed to fit more?
- [ ] Are hardcoded colors absent — only semantic tokens used throughout?

**Interaction**
- [ ] Does the interface respond to input before the server responds?
- [ ] Is every interaction operable by keyboard alone?
- [ ] Is the focus ring visible in both themes at all times?
- [ ] Are errors specific, non-blaming, and actionable?
- [ ] Does motion serve orientation, not decoration?

**Scope and complexity**
- [ ] Is complexity revealed progressively, with simple defaults and advanced options available but not prominent?
- [ ] Has every element on screen justified its presence? Is anything absent that is not also unnecessary?

**Mobile and accessibility**
- [ ] Was this designed for the smallest viewport first?
- [ ] Do touch targets meet 44×44px minimum?
- [ ] Does this work in both light and dark themes without degradation?
- [ ] Does color signal pair with a non-color signal (icon, label, shape)?
- [ ] Does the layout honor `prefers-reduced-motion`?

**Cross-platform**
- [ ] Are terminology and information architecture identical across platforms?
- [ ] Do platform-specific adaptations preserve the product identity rather than replace it?

---

*Next: [02 — Token Architecture](./02-token-architecture.md) | [03 — Component Standards](./03-component-standards.md)*
