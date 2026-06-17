# Entity: Hook

## Purpose
A Hook represents a delayed or asynchronous side effect triggered after a committed internal state change.

## Why This Entity Exists
External side effects such as WhatsApp and Google Calendar must not run until internal state commits. Hooks provide delayed, retryable, independent execution.

## Core Information It Holds
- Hook type
- Related entity
- Scheduled execution time
- Execution status
- Retry count
- Failure reason
- Created at
- Executed at

## Relationships
- Belongs to appointment/request/follow-up/cancellation depending on trigger
- May create communication messages
- May create/update calendar event

## Lifecycle / States
- Scheduled
- Running
- Succeeded
- Failed
- Cancelled/Discarded

## Created By
System after committed workflow transitions.

## Edited By
System. Assistants may trigger retry through UI.

## Visibility
Visible mainly when failures require attention.

## Deletion Behavior
Hooks are operational records and should generally remain for debugging.

## Audit Requirements
Hook creation, execution, failure, retry, and discard should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.
