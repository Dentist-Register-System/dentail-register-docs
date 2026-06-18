# Entity: User

## Purpose
A User represents a person who can log into the system.

## Why This Entity Exists
Doctors, assistants, clinic owners, and practice managers all need authenticated access. The User entity separates login identity from clinic-specific role behavior.

## Core Information It Holds
- Name
- Phone number
- Email
- Authentication method
- Account status
- Linked clinic memberships
- Role assignments
- Language preference (UI locale; English default)

## Relationships
- May have one or more clinic memberships
- May represent a doctor
- May represent an assistant
- May represent a clinic owner
- May create or edit operational records
- Appears in audit events

## Lifecycle / States
- Invited
- Active
- Inactive

## Created By
Clinic owner, assistant invite flow, or onboarding flow.

## Edited By
The user may edit personal profile fields. Clinic admins may manage role/status within the clinic.

## Visibility
Visible within the clinic according to role and permission needs.

## Deletion Behavior
Users should generally be deactivated rather than deleted if historical records reference them. Patient-requested deletion rules do not apply to staff users.

## Audit Requirements
Status changes, role changes, and invitation events should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.
