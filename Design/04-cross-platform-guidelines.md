# Cross-Platform Guidelines

**Status:** Draft for review
**Date:** 2026-06-18
**Derives from:** Design System — Master Reference (locked decisions + canonical tokens)

---

## Purpose

This document defines how the design system spans web, native iOS, and native Android. The goal is straightforward: a user who switches between platforms should feel they are using the same product, not a port of one. The guidelines here draw a clear line between what must be held identical and what should adapt to each platform's conventions.

---

## Guiding Principle: Same Product, Native Feel

Consistency is not uniformity. Every platform has ingrained interaction models that users have learned through thousands of hours of use. Forcing a web interaction model onto iOS or Android creates friction even when the visual appearance matches. The correct trade is:

- Hold the **product layer** constant — goals, destinations, copy, data, hierarchy, meaning.
- Let the **platform layer** vary — how the user navigates to those destinations, which native controls render the inputs, how the system communicates depth and elevation.

This distinction is the backbone of every decision in this document.

---

## 1. What MUST Stay Identical Across Platforms

### 1.1 Terminology and Copy

Every user-facing string originates from a shared i18n resource (react-i18next on web; equivalent localization bundles on native). No platform hardcodes copy directly in components or views. This ensures that:

- A feature named "Appointments" in the web app is named "Appointments" in the iOS app and the Android app.
- Error messages, validation text, empty states, and confirmation dialogs carry the same phrasing and tone everywhere.
- Translated strings are applied consistently — a translation change propagates to all platforms from one source.

**Practical rule:** If a string is not in the i18n resource, it does not ship. Never accept a PR that hardcodes user-visible text in a component.

### 1.2 Visual Identity

The design token system is the shared visual contract across all three platforms. Every color, type size, spacing step, radius, and motion duration resolves from the same canonical values defined in the master brief. No platform invents values outside this system.

**Colors:** Semantic tokens (`--primary`, `--background`, `--destructive`, etc.) resolve to the same hue and lightness on every platform. The indigo primary accent (`#4F46E5` light / `#6366F1` dark) is never reinterpreted per platform.

**Typography:** The Geist Sans / Geist Mono type family and the semantic scale (`display` → `caption`) are the default. Where a platform opts into native system fonts (see section 2.6), the scale step names and their size/weight/line-height values still govern the layout — only the face changes.

**Radius:** The shared radius scale (`sm:6`, `md:8`, `lg:12`, `xl:16`, `full:9999`) applies to all components. A card looks equally soft-cornered across platforms.

**Spacing:** The 4px base grid is universal. Control padding, card insets, section gaps, and page gutters all draw from the same scale. Mobile gutter is `space-4` (16px); this is the same value whether "mobile" means a browser viewport at 390px or an iPhone screen.

**Motion:** Duration tokens (`fast:120ms`, `base:200ms`, `slow:300ms`) and easing curves are the same on every platform. Animation character — calm, fast, no decorative bounce — is a brand attribute, not a platform preference. `prefers-reduced-motion` (web) and equivalent system accessibility settings (iOS Reduce Motion, Android Remove Animations) are honored everywhere.

**Dark and light themes:** All three platforms implement light, dark, and system-follow as first-class targets. No platform ships dark mode as an afterthought or approximation.

### 1.3 Navigation Concepts (Information Architecture)

The set of destinations, their names, and their hierarchical relationships are identical everywhere. If the product has five top-level sections, all three platforms expose the same five sections with the same labels. The path from a list view to a detail view follows the same conceptual depth on all platforms.

What varies is how the user physically travels between those destinations (see section 2.1). The destinations themselves do not vary.

### 1.4 Component Behavior

A bottom sheet is a bottom sheet. A dialog requests confirmation. A toast is transient and auto-dismisses. A destructive action requires confirmation. These behavioral contracts are platform-agnostic. A component may render with platform-native chrome, but its function — what it does, when it appears, what it communicates — is defined once and never overridden per platform.

Examples:
- Primary buttons always represent the single most important action on a surface.
- Loading states use skeletons over spinners wherever the content shape is predictable.
- Empty states always include an icon, a title, and a primary action to resolve the empty condition.
- Error messages always include a retry mechanism and copy drawn from the i18n resource.

### 1.5 Information Hierarchy

The visual weight assigned to each element on a screen is determined by semantic role, not by platform convention. Headings use heading tokens; supporting text uses muted foreground tokens; primary actions use the primary token. A user who has learned to scan one platform can scan any other without relearning what is important.

Hierarchy is expressed through spacing, typography weight, and layout position — not through borders, dividers, or visual chrome. This anti-pattern rule applies equally on all platforms.

### 1.6 Accessibility Commitments

WCAG 2.1 AA is the floor everywhere. Specific commitments that travel across all three platforms:

- **Contrast:** Text 4.5:1 minimum; large text and UI elements 3:1. Both light and dark themes verified independently on all platforms.
- **Touch targets:** A minimum of 44 × 44 px on all mobile surfaces (iOS and Android). Web interactive elements use equivalent click-target sizing.
- **Focus management:** Full keyboard navigation on web; full accessibility service support (VoiceOver on iOS, TalkBack on Android). Focus order is logical and never traps the user.
- **Color is never the sole carrier of meaning:** Every status communicated by color is also communicated by an icon, a label, or both.
- **Motion opt-out:** The system reduced-motion preference is respected on every platform.

---

## 2. What MAY Vary (Platform-Native)

### 2.1 Navigation Patterns

Navigation destinations are identical (section 1.3); the chrome that implements them is not.

**Web:** A persistent top navigation bar provides global wayfinding and identity. An optional collapsible sidebar expands the navigation surface for complex applications with many sections. Breadcrumbs communicate hierarchical position in deep content trees. Navigation is primarily driven by URLs; the back button is the browser's built-in control.

**iOS:** The bottom tab bar (UITabBarController) is the primary navigation surface for top-level sections. Within a section, a navigation bar (UINavigationBar) at the top of the screen displays the current view title and exposes back navigation. The back action is also available via the system swipe-back gesture from the leading screen edge. Modal content uses sheets presented from the bottom.

**Android:** Bottom navigation (Material 3 NavigationBar) serves top-level sections. The top app bar (Material 3 TopAppBar) displays the current view title. Back navigation is handled by the system back gesture (edge swipe or gesture navigation bar) or the hardware/software back button where present. Bottom sheets follow Material 3 conventions.

**Consistency guardrail:** For any new top-level section added to the product, verify all three navigation surfaces expose it with the same label from the i18n resource before the section ships.

### 2.2 Native Controls

When a platform provides a native control that users already know, use it. Replacing platform-native date pickers, time pickers, share sheets, and file selectors with custom web-style equivalents degrades the experience on native.

- **Date and time pickers:** iOS uses UIDatePicker (wheel or compact calendar). Android uses the Material 3 DatePicker and TimePicker dialogs. Web uses a styled input with a custom picker aligned to the design token system (since browser-native date inputs are visually inconsistent).
- **Select / option lists:** iOS uses UIPickerView or action sheets where appropriate. Android uses the Material 3 ExposedDropdownMenu or dialog-based pickers. Web uses a styled select component from the design system.
- **Keyboard types:** Native platforms surface the correct keyboard type automatically when the semantic input type is set (email, numeric, phone, URL). This is expected behavior, not a customization.
- **Share sheets:** iOS uses UIActivityViewController. Android uses the Intent share sheet. Web uses the Web Share API where available, falling back to a custom share dialog.

### 2.3 Gestures and Haptics

**iOS:** Swipe-back to dismiss navigation, swipe-to-delete on list items, pull-to-refresh, long-press context menus, and pinch-to-zoom where applicable. Haptic feedback via the Taptic Engine for confirmations, errors, selection changes, and impact events.

**Android:** Edge swipe for system back navigation, swipe-to-dismiss on snackbars, pull-to-refresh, long-press for contextual menus. Haptic feedback via HapticFeedbackConstants (CONFIRM, REJECT, KEYBOARD_TAP) for equivalent interactions.

**Web:** Hover states on desktop; touch events on mobile browsers. No haptic API. Long-press equivalents are handled by right-click context menus on desktop or a hold gesture on touch. Web does not replicate native gesture models — it follows browser conventions.

The gesture vocabulary varies; the actions those gestures trigger must be semantically equivalent.

### 2.4 Elevation Expression

The master brief defines four elevation levels (`0`–`3`). How those levels are expressed differs:

**Web:** Box shadows at defined values (e.g., `0 4px 12px rgba(0,0,0,.10)` for popovers). Dark theme shifts elevation expression toward lighter surface fills rather than deeper shadows, matching the locked decision in the master brief.

**iOS:** Elevation is expressed through UIKit's layer shadow system and blur effects (UIVisualEffectView / vibrancy). Sheets and cards use system materials where appropriate, which adapt automatically to light and dark mode.

**Android:** Material 3 uses tonal surface color elevation (a surface becomes progressively more tinted toward the primary color as it rises) in addition to shadows. This differs from web's shadow-only model. Use the Material 3 elevation system as-designed; do not fight it to match the web shadow values exactly.

The conceptual hierarchy — what is flat, what is a popover, what is a modal — is identical. The visual rendering of that hierarchy uses each platform's idiomatic system.

### 2.5 Layout Density

**Mobile (iOS and Android):** Single-column layouts. Full-width interactive targets. Generous touch padding (`space-2` to `space-3` for controls). Section gaps `space-8` to `space-12`. Tables collapse to card-list layouts on all mobile surfaces.

**Web (desktop breakpoints):** Multi-column layouts at `lg` (1024px) and above. Sidebar navigation becomes available. Data tables render in full. Density increases moderately — tighter padding is acceptable because hover states and cursor precision remove the need for large touch targets. The design concepts are identical; only the spatial arrangement expands.

**Principle:** Desktop is mobile with more columns and more density. It is never a different product.

### 2.6 Platform Typography

The default type family is Geist Sans / Geist Mono on all platforms. Where a native application opts to use the platform system font instead (San Francisco on iOS, Google Sans / Roboto on Android), the semantic type scale values (size, weight, line-height) from the master brief remain authoritative. The face changes; the scale and weight contract do not.

If a native app ships with Geist, verify the font is licensed and loaded correctly on each platform before shipping.

### 2.7 Status Bar and Safe-Area Handling

**iOS:** Content must respect the safe area insets provided by UIKit (`safeAreaInsets` / `safeAreaLayoutGuide`). The navigation bar and tab bar are system-managed. Content never renders behind the home indicator or Dynamic Island without explicit intent.

**Android:** Content respects `WindowInsets` for system bars. Edge-to-edge display (drawing behind status and navigation bars with inset padding applied to interactive content) follows Material 3 guidance.

**Web:** The browser chrome is managed by the browser. On mobile web, the `env(safe-area-inset-*)` CSS variables handle notch and home-indicator padding when `viewport-fit=cover` is set.

---

## 3. Platform Comparison Table

| Aspect | Web | iOS | Android |
|---|---|---|---|
| **Terminology / copy** | Identical (shared i18n resource) | Identical (shared i18n resource) | Identical (shared i18n resource) |
| **Color / visual identity** | Shared semantic tokens; CSS variables | Shared token values; asset catalog / SwiftUI Color | Shared token values; Material theme / XML color resources |
| **Typography** | Geist Sans + Geist Mono; semantic scale | Geist Sans (or SF Pro if native); same scale values | Geist Sans (or Google Sans/Roboto if native); same scale values |
| **Spacing** | 4px base scale; token names shared | 4px base scale; same values in points | 4px base scale; same values in dp |
| **Radius** | Shared scale (`sm:6` → `full:9999`) | Shared scale applied via cornerRadius | Shared scale applied via shape system |
| **Navigation concept** | Identical destinations + labels | Identical destinations + labels | Identical destinations + labels |
| **Navigation pattern** | Top bar + optional sidebar | Tab bar (bottom) + navigation bar (top) + swipe-back | Bottom navigation + top app bar + system back |
| **Primary controls** | Design-system custom components | Native UIKit controls (pickers, sheets, selects) | Native Material 3 controls (pickers, sheets, menus) |
| **Gestures** | Hover + click; Web Share API; no haptics | Swipe-back, swipe-to-delete, pull-to-refresh, Taptic Engine haptics | System back gesture, pull-to-refresh, HapticFeedbackConstants |
| **Motion** | Identical durations + easing; CSS transitions / Web Animations API | Identical durations + easing; UIView / Core Animation | Identical durations + easing; Compose / Animator |
| **Elevation** | Box shadows at defined levels; lighter surfaces in dark mode | UIKit layer shadows + system materials | Material 3 tonal elevation + shadow |
| **Density** | Mobile: single-column; desktop ≥ 1024px: multi-column, tighter spacing | Single-column; system touch target sizing | Single-column; Material 3 touch target sizing |

---

## 4. Mobile-First Implications for Cross-Platform

The master brief locks mobile-first as a non-negotiable stance. This has concrete consequences for cross-platform work:

**Design starts at the smallest viewport.** Every feature is first designed for a 390px-wide screen (or the native mobile canvas). If the interaction model works at this size, it works everywhere. If it only works at 1280px, the feature has a design problem.

**Desktop is additive, not foundational.** When adapting a mobile-first design to desktop, the permitted additions are: more columns, reduced vertical space between elements, persistent navigation panels, and expanded data surfaces (full tables instead of card lists). The permitted additions are never: entirely new concepts, different navigation hierarchies, or functionality that does not exist on mobile.

**Shared tokens eliminate platform-specific sizing.** Because the token scale is the same across web, iOS, and Android, a spacing decision made for mobile applies directly on all platforms. `space-4` is 16px on web, 16pt on iOS, 16dp on Android. The numeric value and visual result are the same.

**One behavior spec, three implementations.** A feature's behavior document (what the component does, its states, its error handling) is written once and serves as the acceptance criterion for all three platform implementations. Platform engineers translate the spec into native code; they do not reinterpret the UX.

---

## 5. Token Sharing Across Platforms

The semantic token layer is platform-agnostic. The values are defined once in the design system source of truth. Each platform maps those values to its theming system:

**Web (CSS variables + Tailwind v4):**
Tokens are declared as custom properties on `:root` (light) and `[data-theme="dark"]` (dark). Tailwind utilities consume the variables directly. Components reference only semantic token utilities (`text-foreground`, `bg-primary`, `border-border`) — never raw color values or Tailwind palette steps.

```css
:root {
  --primary: #4F46E5;
  --primary-foreground: #FFFFFF;
  --background: #FFFFFF;
  --foreground: #0B0B0F;
  /* ... */
}
[data-theme="dark"] {
  --primary: #6366F1;
  --background: #0B0C0E;
  --foreground: #F4F5F7;
  /* ... */
}
```

**iOS (SwiftUI / UIKit):**
Token values are defined in the asset catalog as named Color Sets with light and dark appearances. SwiftUI views reference them by semantic name (`Color("primary")`, `Color("background")`). A token mapping file translates the canonical hex values to asset catalog entries, ensuring no value diverges from the source.

**Android (Material Theme / Compose):**
Token values are declared in the Material 3 theme (`colors.xml` or Compose `MaterialTheme.colorScheme`). A light and dark `ColorScheme` is defined using the canonical token values. Components reference theme roles (`MaterialTheme.colorScheme.primary`, `.background`, etc.) and never hardcode colors.

**Governance:** When a token value changes in the master brief, the change must be applied to all three theming system files in the same release. Partial token updates that leave one platform on old values are not acceptable.

---

## 6. Consistency Guardrails — Pre-Ship Checklist

Before marking a feature ready to ship across platforms, verify the following for each surface:

### Copy and Content
- [ ] All user-visible strings are sourced from the shared i18n resource — none are hardcoded in components or views.
- [ ] Feature names, section labels, and action labels are identical across web, iOS, and Android.
- [ ] Error messages and empty state copy match the shared i18n codes.

### Visual Identity
- [ ] No color value is hardcoded — every color reference resolves to a semantic token.
- [ ] Every token used exists in the master brief token set; no new tokens were invented without updating the source of truth.
- [ ] The feature renders correctly in both light and dark themes on all three platforms.
- [ ] Spacing values align to the 4px base scale; no arbitrary px/pt/dp values were introduced.
- [ ] Radius values are drawn from the shared radius scale.

### Navigation and Information Architecture
- [ ] The feature's position in the navigation hierarchy is identical on all platforms.
- [ ] The destination label matches the i18n string used on every other platform.
- [ ] Navigation into and out of the feature follows the platform's native pattern (see section 2.1) but lands on the same screen.

### Behavior
- [ ] The feature behaves identically across platforms: same states (loading, empty, error, success), same triggers, same outcomes.
- [ ] Destructive actions require confirmation on all platforms.
- [ ] Loading states use skeletons where the content shape is known.
- [ ] Error states expose a retry action and platform-consistent error copy.

### Accessibility
- [ ] Color contrast passes 4.5:1 (text) and 3:1 (UI elements) on both themes, on all platforms.
- [ ] All interactive elements have a touch/click target of at least 44 × 44px on mobile surfaces.
- [ ] VoiceOver (iOS) and TalkBack (Android) label all interactive elements correctly.
- [ ] Full keyboard navigation works on web; focus order is logical; no focus traps.
- [ ] No meaning is conveyed by color alone — every status pairs color with an icon or label.
- [ ] The feature respects reduced-motion settings on all platforms.

### Motion
- [ ] Animation durations and easing match the canonical motion tokens.
- [ ] The feature has been tested with Reduce Motion (iOS), Remove Animations (Android), and `prefers-reduced-motion` (web) enabled — no essential information is lost.

### Platform-Native
- [ ] Native platform controls (pickers, share sheets, selects) are used on iOS and Android where applicable; custom web-style controls are not forced onto native surfaces.
- [ ] Safe area insets are correctly applied on iOS and Android.
- [ ] The feature has been tested on a real device (not only simulator/emulator) for each platform.

---

## 7. Cross-Platform Anti-Patterns to Avoid

**Forcing web navigation onto mobile.** A top navigation bar with horizontal tabs is a web pattern. Do not replicate it on iOS or Android. Use the native navigation patterns defined in section 2.1.

**Building desktop-only features.** If a feature cannot be designed for a 390px canvas, the feature scope needs narrowing before it ships anywhere.

**Platform-specific copy.** Every string that differs between platforms is a support burden and a source of user confusion. The only acceptable copy variation is platform-specific terminology required by platform guidelines (e.g., "Back" on iOS vs system back on Android — both driven by platform convention, not product copy).

**Hardcoded colors or spacing.** Any value not routed through the token system cannot be updated consistently. It will drift.

**Dark mode as an afterthought.** All three platforms treat dark mode as a primary target. A component that is only verified in light mode is not done.

**Reimplementing native controls.** Custom date pickers on iOS and Android that mimic the web component introduce unfamiliar interaction patterns and are harder to maintain. Use the native control.

**Inventing new tokens per platform.** If a spacing, color, or radius value is needed and does not exist in the master brief, the right action is to propose adding it to the source of truth — not to create a platform-local value.

---

*This document is a derived specification. All token values, locked decisions, and anti-patterns originate from the Design System — Master Reference. In case of conflict, the master reference governs.*
