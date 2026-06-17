# Claude Code Implementation Prompt

Read:
- PRD
- Workflow docs
- Entity docs
- Test Rails
- Acceptance Plan

Rules:
- Humans decide, system coordinates.
- AI never schedules.
- Google Calendar is downstream.
- WhatsApp is downstream.
- Preserve auditability.
- Preserve history.
- Favor simple implementations.

Implementation Order:
1. Skeleton
2. Auth
3. Core entities
4. Appointment Requests
5. Appointments
6. Audit
7. Hooks
8. Notifications
9. Follow Ups
10. Integrations

Requirements:
- Unit tests
- Integration tests
- P0 coverage

Use *_beta tables during implementation/testing.

Do not mark features complete until test rails pass.
