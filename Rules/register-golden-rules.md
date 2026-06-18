# Register System - Golden Rules for Claude Code

Version: 1.0  
Purpose: Non-negotiable implementation guardrails for building the Register System.

This document defines rules Claude Code must never overstep while designing, implementing, refactoring, testing, or resolving ambiguity.

The PRD, workflow docs, entity specs, test rails, and acceptance plans define the product.  
This document defines the boundaries.

---

# 1. Product Philosophy Rules

## Rule 1.1 — Humans decide. Software coordinates.

The system must never silently make operational decisions that belong to clinic staff.

Claude Code must not implement behavior where the system automatically decides:

- which patient gets a slot
- whether a patient should be scheduled
- whether a waitlist entry should be promoted
- whether a follow-up should become an appointment
- whether a cancellation should proceed without the correct human workflow
- whether a doctor’s request should be ignored
- whether appointment capacity should be released without the assistant action where the workflow requires assistant action

When multiple valid workflow outcomes exist, the system should present choices to the user rather than enforce a single path.

## Rule 1.2 — Doctors decide clinical scheduling approval.

For normal appointment requests:

- assistant creates request
- doctor approves or rejects
- appointment is confirmed only after doctor approval

Claude Code must not bypass doctor approval in the normal assistant-created appointment request workflow.

Exceptions are explicitly documented workflows:

- doctor direct booking
- retroactive appointment creation
- doctor override

## Rule 1.3 — Assistants are operational authority.

The assistant is the primary day-to-day operator.

Claude Code must preserve assistant workflows for:

- appointment requests
- cancellations
- reschedules
- patient communication
- waitlists
- follow-ups
- schedule coordination
- failed integration recovery

Do not design the product as doctor-first unless the workflow explicitly says so.

## Rule 1.4 — AI never schedules appointments.

AI may summarize, prioritize, and highlight risks.

AI must not:

- create appointments autonomously
- promote waitlist entries
- negotiate scheduling
- approve/reject requests
- cancel appointments
- reschedule appointments
- contact patients autonomously as if it were clinic staff

Any AI-generated output must be advisory.

---

# 2. Implementation Freedom Rules

## Rule 2.1 — Behavior is fixed. Implementation is flexible.

Claude Code may choose:

- database structure
- ORM patterns
- service boundaries
- API route structure
- frontend component structure
- internal abstractions
- job runner implementation
- test framework structure

But Claude Code must not change documented business behavior without explicitly asking.

## Rule 2.2 — Do not overfit to documents when behavior conflicts are found.

If documents conflict:

1. Prefer the latest explicit user decision.
2. Prefer the Golden Rules.
3. Prefer the PRD philosophy.
4. Prefer workflow docs.
5. Prefer entity docs.
6. Ask for clarification if still ambiguous.

Known latest decision:
- Expired approval does **not** automatically release capacity.
- Expired approval keeps capacity reserved until assistant cancels or re-sends approval.

## Rule 2.3 — Do not invent enterprise complexity.

Do not add complex abstractions unless needed.

Avoid:

- event sourcing unless explicitly chosen
- microservices
- CQRS
- distributed workflow engines
- premature multi-tenant enterprise admin features
- billing modules
- EMR/EHR features
- insurance modules
- inventory systems

This is an operational coordination system, not a hospital management platform.

---

# 3. Open Source and Dependency Rules

## Rule 3.1 — Use only open-source libraries unless explicitly approved.

Claude Code must not introduce proprietary, commercial, paid, source-available-but-restrictive, or closed-source libraries without asking.

Acceptable examples:

- MIT
- Apache-2.0
- BSD
- ISC
- PostgreSQL-compatible open-source tooling
- standard Python/TypeScript open-source packages

Must ask before using:

- paid SDKs
- commercial UI kits
- proprietary SaaS-only SDKs
- source-available licenses with commercial restrictions
- AGPL libraries
- GPL libraries
- libraries with unclear licenses

## Rule 3.2 — Prefer boring, widely used dependencies.

Choose reliable, mainstream libraries over clever niche ones.

Backend preference:

- FastAPI
- Pydantic
- SQLAlchemy or equivalent mature ORM
- Alembic or equivalent migration tool
- pytest

Frontend preference:

- TypeScript
- React/Next.js if chosen
- mature form and validation libraries
- simple component structure

## Rule 3.3 — Do not add dependencies for trivial problems.

Do not install a package for logic that can be clearly implemented in a few lines.

Examples:

- small date formatting helper
- simple enum mapping
- basic string transformation
- one-off utility functions

## Rule 3.4 — Document every non-trivial dependency.

For each meaningful dependency added, Claude Code should document:

- package name
- purpose
- license
- why it is needed
- why a simpler alternative was not chosen

---

# 4. Data and Storage Rules

## Rule 4.1 — Preserve operational history.

History belongs to the clinic.

Do not erase historical appointment records during normal workflow transitions.

Use states for workflow outcomes:

- Cancelled
- Rejected
- No Show
- Completed
- Rescheduled
- Expired Approval

Do not delete records to represent normal business outcomes.

## Rule 4.2 — Delete means delete only where explicitly intended.

Patient deletion removes the active Patient object.

Historical operational records remain, using stored patient snapshot fields.

Claude Code must not implement patient deletion in a way that destroys completed clinic history unless explicitly required later.

## Rule 4.3 — Historical records must not depend only on live Patient data.

Appointments and important workflow records should preserve enough patient snapshot information to remain understandable if the Patient object is deleted.

Examples:

- patient name snapshot
- phone snapshot where appropriate
- age snapshot where appropriate
- complaint or visit context where appropriate

## Rule 4.4 — Staff users should usually be deactivated, not deleted.

Doctors and assistants appear in audit/history.

Do not hard-delete staff users as a normal workflow.

Inactive staff attribution must remain visible historically.

## Rule 4.5 — Test tables must be clearly demarcated.

All test/beta tables must use:

`<table_name>_beta`

Do not mix experimental test tables with production-intended tables without clear naming.

---

# 5. Appointment and Scheduling Rules

## Rule 5.1 — Normal appointment requests are not appointments.

Pending appointment requests must not behave as confirmed appointments.

While pending:

- patient is not confirmed
- patient should not receive confirmation
- request waits for doctor approval
- slot capacity is reserved according to rules

## Rule 5.2 — Capacity must be enforced atomically.

Claude Code must prevent race conditions that allow overbooking beyond configured capacity.

When multiple users attempt to book the same capacity:

- exactly the allowed number succeeds
- excess attempts fail cleanly
- no silent capacity drift occurs

## Rule 5.3 — Only doctor override can exceed capacity.

Assistants must not exceed capacity through normal booking flows.

Doctor override must be explicit and auditable.

## Rule 5.4 — Waitlists never auto-promote.

Waitlist entry becoming an appointment request requires assistant action.

The system may notify assistants that capacity opened.

The system must not automatically convert waitlist entries into appointment requests or appointments.

## Rule 5.5 — Expired approval does not auto-release capacity.

When a request expires after 120 minutes:

- status becomes Expired Approval
- doctor can no longer directly approve the expired notification/action
- assistant sees Cancel and Re-send Approval
- capacity remains reserved until assistant action

This is intentional.

## Rule 5.6 — Re-send approval reuses the same request.

Re-send approval must not create duplicate appointment requests.

## Rule 5.7 — Reschedule must preserve the original appointment until replacement is approved.

Never destroy or cancel the original appointment before a replacement appointment is confirmed.

If replacement request is rejected, cancelled, or expires, the original appointment remains unchanged.

## Rule 5.8 — Completion fields are optional.

The system must not block appointment completion because treatment, notes, or template fields are empty.

Humans decide what information is enough.

## Rule 5.9 — Arrival and no-show reversals must preserve human control.

Undo arrival defaults back to Confirmed.

Undo no-show defaults back to Confirmed, but the user may choose another allowed target state when supported.

Do not enforce one rigid recovery path when clinic reality requires flexibility.

---

# 6. State Transition Rules

## Rule 6.1 — Every state transition must validate current state.

Before committing a transition, verify the entity is still in the expected state.

Examples:

- cannot approve cancelled request
- cannot approve rejected request
- cannot approve expired request directly
- cannot complete already cancelled appointment
- cannot cancel already completed appointment unless explicit workflow later allows it

## Rule 6.2 — First committed transition wins.

For races such as:

- cancel vs complete
- approve vs cancel
- reject vs approve

The first valid committed transition wins.

Later stale actions must fail clearly.

## Rule 6.3 — Terminal states cannot be reopened unless a workflow explicitly allows it.

Rejected requests cannot be reopened.

Cancelled requests cannot be reopened.

Expired approvals require assistant action; they are not silently reactivated.

## Rule 6.4 — Idempotency is mandatory for dangerous actions.

Repeated action submission must not create duplicates.

Must be idempotent:

- approval
- rejection
- cancellation
- direct booking submission where retry risk exists
- hook execution
- WhatsApp send workflows
- calendar create/delete workflows

---

# 7. Audit Rules

## Rule 7.1 — Important actions must be auditable.

Audit events are required for:

- request creation
- request edit
- request approval
- request rejection
- request cancellation
- request expiry
- re-send approval
- appointment creation
- direct booking
- retroactive creation
- cancellation
- reschedule
- arrival
- no-show
- completion
- patient deletion
- doctor override
- schedule change
- hook failure/retry where operationally relevant

## Rule 7.2 — Audit records must preserve attribution.

Audit events should capture:

- actor
- timestamp
- action
- entity type
- entity ID
- previous state/value where applicable
- new state/value where applicable
- reason/note where applicable

## Rule 7.3 — Audit failure must not silently disappear.

If the main business transaction succeeds but audit write fails:

- business transaction may remain successful
- audit retry/dead-letter intent must be recorded
- failure must be recoverable/observable

Do not silently drop audit events.

## Rule 7.4 — Audit events are append-only.

Do not edit audit records.

If correction is required, create another audit event.

---

# 8. Hook and Integration Rules

## Rule 8.1 — External side effects happen only after internal commit.

Never call WhatsApp or Google Calendar before the internal workflow transition commits.

Correct sequence:

1. validate
2. commit internal state
3. create hook/job
4. worker executes external side effect

## Rule 8.2 — External failure never rolls back internal appointment state.

If WhatsApp fails, appointment remains valid.

If Google Calendar fails, appointment remains valid.

The system should create visible recovery tasks or retry states.

## Rule 8.3 — Hooks must re-validate state before execution.

A hook scheduled for a confirmed appointment must check the appointment is still in a state where the side effect makes sense.

Example:
If appointment is cancelled before confirmation hook executes, do not send confirmation.

## Rule 8.4 — Hooks are at-least-once with idempotency.

Do not attempt complex exactly-once guarantees.

Instead:

- make hook execution retryable
- prevent duplicate user-visible side effects
- store provider/message/event IDs where applicable
- use idempotency keys where possible

## Rule 8.5 — Google Calendar is downstream only.

System -> Google Calendar.

Never:

Google Calendar -> System state change.

External calendar edits must not modify appointment state.

## Rule 8.6 — WhatsApp is a communication channel only.

WhatsApp messages do not define appointment truth.

Patient replies may create assistant tasks later, but must not trigger autonomous scheduling.

---

# 9. Authentication and Authorization Rules

## Rule 9.1 — Users must only access their clinic workspace.

Clinic boundaries determine visibility.

Do not allow cross-clinic data leakage.

## Rule 9.2 — Role permissions must match product philosophy.

Doctors can:

- approve/reject requests
- view schedules
- view patients
- create direct bookings
- mark relevant appointment states where allowed

Assistants can:

- create patients
- create requests
- coordinate cancellations/reschedules
- manage waitlists
- manage patient communication
- mark arrival/no-show/completion where allowed

## Rule 9.3 — Do not expose admin-only settings broadly.

Clinic settings that affect scheduling or communication should be editable only by authorized users.

---

# 10. Testing Rules

## Rule 10.1 — P0 tests are mandatory.

Do not mark a feature complete if relevant P0 tests are missing or failing.

## Rule 10.2 — Test product behavior first.

Prefer Given/When/Then tests that verify the business outcome.

Do not rely only on low-level technical tests.

## Rule 10.3 — Mock external providers in automated tests.

Automated tests should mock:

- WhatsApp
- Google Calendar
- OTP/SMS providers
- AI providers

Real provider tests should be manual or smoke tests only.

## Rule 10.4 — Concurrency tests are required for capacity and state transitions.

Claude Code must include tests for:

- simultaneous booking
- simultaneous approval
- approve/cancel race
- cancel/complete race
- hook retry duplication

## Rule 10.5 — Manual acceptance checks are release gates.

Automated tests are not enough.

Manual acceptance plan must be used before declaring major workflow implementation complete.

---

# 11. Security and Privacy Rules

## Rule 11.1 — Do not log sensitive patient details unnecessarily.

Avoid logging:

- medical conditions
- detailed complaint
- phone numbers
- message bodies

Where logs are needed, prefer IDs and structured metadata.

## Rule 11.2 — Secrets must never be committed.

Do not commit:

- API keys
- database passwords
- JWT secrets
- provider tokens
- production URLs with secrets

Use environment variables and example env files.

## Rule 11.3 — Provider credentials must be isolated by environment.

Local, staging, and production credentials must not be mixed.

## Rule 11.4 — Do not implement unsafe debug shortcuts.

No bypass auth endpoints.

No hardcoded admin users in production code.

No test OTPs in production mode.

---

# 12. UI and UX Rules

## Rule 12.1 — UI must make state visible.

Users should clearly see:

- Pending
- Expired Approval
- Confirmed
- Arrived
- No Show
- Completed
- Cancelled
- Rescheduled
- Rejected

Do not hide important workflow states behind generic labels.

## Rule 12.2 — Destructive actions require confirmation.

Require confirmation for:

- patient deletion
- appointment cancellation
- schedule changes affecting appointments
- removing availability with impact
- deleting templates if allowed

## Rule 12.3 — Failed integrations must be visible to assistants.

If WhatsApp/calendar fails, assistant should know.

Do not bury failures only in logs.

## Rule 12.4 — Do not overbuild dashboards before core workflows.

Dashboards are useful, but core workflow correctness comes first.

---

# 13. Architecture Rules

## Rule 13.1 — Prefer simple modular monolith.

Do not split into services unless explicitly requested.

## Rule 13.2 — Keep business logic out of UI-only code.

Critical workflow rules must be enforced backend-side.

Frontend may help validate, but backend is authoritative.

## Rule 13.3 — Use transactions for state changes that must be atomic.

Examples:

- reserve capacity and create request
- approve request and create appointment
- transition appointment state
- create hook records after business commit
- write audit/retry intent

## Rule 13.4 — Avoid hidden magic.

Prefer clear service functions and explicit state transitions over clever implicit side effects.

## Rule 13.5 — Migrations must be reversible where practical.

Database migrations should be clear and reviewable.

Do not generate destructive migrations casually.

---

# 14. Conflict Resolution Rules

If Claude Code finds ambiguity:

1. Do not silently choose a behavior that changes product meaning.
2. Check PRD, workflow docs, entity docs, test rails, and this document.
3. If still unclear, ask the user.
4. If implementation must proceed, choose the safest option:
   - preserve data
   - preserve history
   - avoid patient communication
   - avoid autonomous scheduling
   - avoid external side effects
   - keep human decision point

---

# 15. Absolute Never Rules

Claude Code must never:

- Use non-open-source libraries without approval.
- Add EMR/EHR/billing/payment/insurance/inventory features into V1.
- Let AI schedule appointments.
- Let WhatsApp define appointment truth.
- Let Google Calendar define appointment truth.
- Auto-promote waitlist entries.
- Auto-release expired approval capacity.
- Send patient confirmation before doctor approval.
- Roll back confirmed appointments because WhatsApp failed.
- Roll back confirmed appointments because calendar failed.
- Allow slot capacity overflow except explicit doctor override.
- Silently drop audit intent.
- Delete historical appointment records as part of normal cancellation/reschedule/no-show workflows.
- Hard-delete staff users as a normal operation.
- Store secrets in code.
- Mark features complete without relevant P0 tests.
- Build around implementation convenience when it violates clinic reality.

---

# 16. Internationalization Rules

## Rule 16.1 — No hardcoded user-facing strings.

All user-facing text (labels, buttons, placeholders, validation messages, status labels, empty/loading states, notification copy) must come from translation resources. Do not embed display strings as literals in components.

## Rule 16.2 — Backend returns stable codes; frontend translates.

Prefer stable, machine-readable codes for errors and statuses. The frontend maps codes to localized messages. Do not rely on English backend messages as the display source.

## Rule 16.3 — English is default; structure for more languages.

English is the default/fallback locale. Hindi is the first additional language; Marathi follows. New locales are added by adding resources, never by changing code.

## Rule 16.4 — Do not auto-translate clinical / entered data.

Human-entered content (patient names, notes, complaints, treatment notes) is stored and shown exactly as entered. V1 must not machine-translate clinical data.

## Rule 16.5 — Templates are localization-ready.

WhatsApp and notification templates must support per-locale variants with English fallback. Do not hardcode message bodies in a single language.

---

# 17. Final Operating Principle

When in doubt:

Preserve reality.  
Preserve history.  
Preserve human authority.  
Preserve auditability.  
Ask before changing product behavior.
