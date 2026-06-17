# Entity: Template

## Purpose
A Template represents reusable message or post-op instruction content.

## Why This Entity Exists
Clinics need standardized but editable communication for confirmations, cancellation notices, reminders, post-op instructions, and retroactive thank-you messages.

## Core Information It Holds
- Template name
- Template type
- Content
- Active/inactive status
- Clinic
- Created by
- Updated by

## Relationships
- Belongs to clinic
- Used by communication messages
- Used during appointment completion
- Used for WhatsApp workflows

## Lifecycle / States
- Active
- Inactive

## Created By
Clinic owner, assistant, or authorized admin.

## Edited By
Authorized clinic users.

## Visibility
Visible to users who send or configure communications.

## Deletion Behavior
Templates should be deactivated rather than deleted if already used historically.

## Audit Requirements
Template creation and edits should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.
