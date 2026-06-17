# Workflow: Appointment Rejection
## Status
Draft v1.0

## Purpose
The appointment rejection workflow allows a doctor to decline a pending appointment request while preserving scheduling history and returning control to the assistant for coordination.

## Key Decisions

### Rejection Reason

Rejection reason is optional.

Doctor may:

Reject
→ Submit

or

Reject
→ Optional Note
→ Submit

### Patient Communication

Patients are not automatically notified when requests are rejected.

Request rejection is considered an internal clinic workflow event.

The assistant decides how to communicate with the patient.

### Assistant Notification

Assistants receive an immediate notification when a request is rejected.

The notification should contain:

- Patient
- Doctor
- Slot
- Rejection Reason (if provided)

### Capacity Release

Slot capacity is released immediately upon rejection.

The system does not wait for:

- Assistant acknowledgement
- Patient communication
- Follow-up actions

### Reschedule Workflow

Rejected requests remain historical.

Reschedule Request creates a brand-new request.

The original request remains rejected.

### Rejection Context

The rejection reason remains visible while creating the replacement request.

This helps assistants avoid repeating the same scheduling mistake.

### Reschedule May Change

The replacement request may change:

- Doctor
- Date
- Time Slot

because it is a new request.

### Immutability

Rejection reason is immutable after submission.

Rejected requests are terminal.

Rejected requests cannot be reopened.

### Audit Requirements

The system should record:

- Rejected By
- Rejected At
- Rejection Reason
- Original Request Reference
