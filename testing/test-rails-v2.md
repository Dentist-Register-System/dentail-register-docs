# Register System - Test Rails V2

## Purpose
Implementation contract for Claude Code.

Feature completion requires:
- Code
- Automated tests
- Relevant P0/P1 rails passing
- Manual acceptance checks

## P0 Categories
- Data Integrity
- Capacity & Concurrency
- Appointment Lifecycle
- Audit & History
- Integration Safety

### Capacity
- Capacity never exceeded.
- Doctor override only approved bypass.
- Concurrent booking protected.

### Stale State
- Every transition validates current state.
- Expired/cancelled requests cannot be approved.

### Requests
- Create
- Edit
- Cancel
- Reject
- Approve
- Expire
- Re-send approval

### Appointments
- Direct booking
- Retroactive
- Arrival
- No-show
- Completion
- Cancellation
- Reschedule

### Audit
- Actor
- Timestamp
- Previous state
- New state
- Retry on failure

### Integrations
- WhatsApp failure never rolls back appointment.
- Calendar failure never rolls back appointment.
- Hooks are idempotent.
- Calendar never becomes source of truth.

## P1
- Notifications
- Waitlists
- Follow-ups
- Schedule changes
- Doctor availability

## P2
- Search
- Sorting
- Filtering
- UX behavior
