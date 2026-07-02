# <Feature> — Design Spec

**Date:** <YYYY-MM-DD>
**Status:** DRAFT — **BLOCKED**. Implementation must not begin until every OPEN item in the §2 Decision Ledger is ✅ RULED by the human.
**Doctrine:** `Rules/sentinel-rules.md` · `Rules/register-golden-rules.md` (incl. **Rule 2.4 — never proceed on an assumption**).

---

## ⛔ IMPLEMENTATION HALT — coder agent, read before writing ANY code

This spec may contain **OPEN decisions** (§2). They are blocking gates, not defaults to run with.

1. **Do not write, scaffold, or migrate anything** until every row in the §2 Decision Ledger is ✅ **RULED** by the human.
2. **If you meet ANY choice this spec does not explicitly rule — no matter how small — STOP and ask the human. Never default, never infer, never "assume and note it," never treat an unanswered question as consent.** (Golden Rule 2.4.)

---

## 1. Goal
<what this is, who it's for, why.>

## 2. Decision Ledger

### ✅ RULED (by <human>, <date>)
- <decision> — <ruling>.

### ⛔ OPEN — implementation blocked until the human rules each (proposed value shown; confirm or override)
- **O1 —** <decision>. *Proposed:* <value>. **Needs an explicit yes.**

## 3. … design sections (architecture, backend, frontend, API, testing, risks) …

## N. Sign-off checklist (implementation blocked until all ✅)
- [ ] O1 <decision>
