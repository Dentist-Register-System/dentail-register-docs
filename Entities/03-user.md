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
- `doctor_id` — optional reference to the user's linked `doctor_beta` row (set when the user has a doctor profile in the current clinic context)

## Relationships
- May have one or more clinic memberships
- May represent a doctor
- May represent an assistant
- May represent a clinic owner
- May create or edit operational records
- Appears in audit events

## Roles and Doctor Identity

Roles (`Owner`, `Doctor`, `Assistant`) are **not mutually exclusive**. A clinic creator who also practices is both `Owner` and `Doctor`. An assistant who was later granted a doctor profile is both `Assistant` and `Doctor`.

**Doctor-ness is determined by the presence of a linked `doctor_beta` row**, not solely by `membership.role`. A user is considered a doctor in a clinic when:

1. They have a `doctor_beta` record with `clinic_id` matching the current clinic, and
2. That record's `linked_user_id` equals the user's id.

The `/me` endpoint exposes `doctor_id` so the frontend can distinguish users who have a doctor profile (and therefore can access **My Schedule**) from those who do not. See `docs/specs/2026-06-20-owner-doctor-self-profile-nav-split-design.md` §3.2, issue #49.

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
