# Entity: Doctor

## Purpose
A Doctor represents a clinical provider whose availability can be scheduled and whose approval is required for normal appointment requests.

## Why This Entity Exists
Doctors are the decision makers for whether a patient should be placed into their schedule. The system must model doctor availability, approval actions, direct bookings, overrides, and appointment history.

## Core Information It Holds
- Name
- Phone number
- Email, optional
- Specialty
- Status
- `linked_user_id` — foreign key to the user who owns this doctor profile (set at creation; used for authorization, schedule access, and approval actions)
- Clinic membership
- Availability ownership

## Relationships
- Belongs to clinic
- May have a linked user (via `linked_user_id`)
- Has many availability windows
- Has many slots
- Has many appointment requests
- Has many appointments
- Can approve/reject requests
- Can create direct bookings
- Can request cancellations

## Lifecycle / States
- Invited
- Active
- Inactive

## Created By

Two creation paths exist (as-built, issue #49):

1. **Self-profile (owner-doctor path — default happy path):** The clinic owner who is also a practicing doctor creates their own doctor profile as a self-service step after clinic setup. No invite is issued; the profile is immediately `Active`. `linked_user_id` is set to the creating user's id. One doctor profile per user per clinic is enforced (duplicate attempts return 409). Clinic name/phone are not copied — the owner fills the doctor profile independently. See `docs/specs/2026-06-20-owner-doctor-self-profile-nav-split-design.md` §3.1.

2. **Invite path:** Owner or practice manager invites a doctor by name/phone/specialty. The doctor receives an invite, creates an account, and submits availability. `linked_user_id` is set when the invited doctor's user account is linked.

## Edited By
Doctor may edit own profile. Clinic admin/assistant may manage operational doctor setup depending on permissions.

## Visibility
Doctors can view all clinic schedules and patient records in V1.

## Deletion Behavior
Doctors should be deactivated rather than deleted. Historical attribution remains visible.

## Audit Requirements
Doctor invitation, activation, deactivation, availability changes, approvals, rejections, direct bookings, and cancellation requests should be auditable.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.
