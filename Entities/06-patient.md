# Entity: Patient

## Purpose
A Patient represents a person receiving care or attempting to schedule care at the clinic.

## Why This Entity Exists
Appointments, history, follow-ups, communication, and scheduling context all attach to patients. Patients may exist before any appointment is booked.

## Core Information It Holds
- Name
- Phone number
- Age
- Referral source
- Medical conditions
- Chief complaint
- Notes
- Alternate phone numbers, future
- Patient history summary

## Relationships
- Belongs to clinic
- Has many appointment requests
- Has many appointments
- Has many follow-ups
- Has many communication messages
- May be created during doctor direct booking or retroactive appointment creation

## Lifecycle / States
V1 does not require complex patient lifecycle states. Patient records can exist without appointments.

## Created By
Assistant, doctor direct booking flow, retroactive appointment flow, or future onboarding flow.

## Edited By
Assistants and doctors may edit patient details. Completed/history-related edits must be auditable.

## Visibility
All doctors and assistants in the clinic can view all patient records.

## Deletion Behavior
Delete means delete. Patient-requested deletion must remove patient data. Confirmation is required.

## Audit Requirements
Create, edit, duplicate override, merge if supported later, and deletion actions must be auditable where possible.

## Open Questions
None for conceptual discovery. Implementation details should be resolved during database and API design.
