# Entity: Communication Message

## Purpose
A Communication Message represents a patient- or doctor-facing message sent through WhatsApp or future channels.

## Why This Entity Exists
WhatsApp is a communication layer, not the source of truth. Messages need delivery status, retry support, and linkage to workflow context.

## Core Information It Holds
- Recipient
- Channel
- Message type
- Body/template
- Related entity
- Delivery status
- Sent at
- Failure reason
- Retry count

## Relationships
- Belongs to clinic
- May relate to appointment, follow-up, cancellation, or retroactive visit
- May be produced by hook engine

## Lifecycle / States
- Pending
- Sent
- Failed
- Retried
- Cancelled/Discarded

## Created By
Hook engine or explicit assistant action.

## Edited By
Usually system-managed. Assistants may re-trigger messages.

## Visibility
Visible to assistants where operationally relevant.

## Deletion Behavior
Messages should generally remain for communication history unless patient deletion requires removal.

## Audit Requirements
Send attempts, failures, and retries should be traceable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.
