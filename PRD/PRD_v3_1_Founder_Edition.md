# Clinic Scheduling & Coordination Platform
# Founder PRD v3.0

> This document is the business source of truth for the product.
> It intentionally focuses on workflows, users, operational realities, and product decisions rather than implementation details.

---

# 1. The Story Behind The Product

Most clinics do not have a scheduling problem. They have a coordination problem. From the outside, scheduling appears simple:
- Patient calls
- Appointment booked
- Patient arrives

In reality, the process is significantly more complex. A clinic assistant often acts as the operational brain of the clinic.
The assistant remembers:
- Which doctor is available
- Which consultant visits on which days
- Which patients require urgent follow-up
- Which patient cancelled last week
- Which patient should be prioritized
- Which doctor is travelling
- Which treatment requires special handling

Much of this information exists only in human memory. The clinic functions because experienced assistants hold everything together. The goal of this product is to capture and organize that operational knowledge.

---

# 2. Mission

*Enable clinics to coordinate patients, doctors, consultants, follow-ups, reminders, and scheduling without relying on human memory. The product should become the operational coordination layer for the clinic.*

---

# 3. What We Are Not Building

We are not building:

- EMR
- EHR
- Billing
- Payments
- Insurance
- Inventory
- Treatment planning
- Clinical charting

Those products already exist. **Our focus is operational coordination.**

---

# 4. Core Product Philosophy

## Assistant First

The assistant is the primary user. The product succeeds when assistants become more effective.

## AI Summarizes, Humans Decide

AI can:
- summarize
- prioritize
- highlight risks
- create daily briefs

AI cannot:
- schedule autonomously
- make medical decisions
- negotiate appointments

## WhatsApp Is Communication

The application is the workflow engine. WhatsApp is simply a communication channel.

## Simplicity Wins

Whenever there is a choice between:
- operational simplicity
- enterprise complexity

**choose simplicity.**

## Reality First

The system should support clinic operations rather than dictate them.

In real clinics, emergencies occur, doctors may directly contact patients, assistants may be unavailable, and appointments may be created outside the application.

Whenever there is a conflict between patient care and workflow completion, patient care takes priority.

The system should provide mechanisms to record, communicate, and reconcile real-world actions after they occur rather than attempting to prevent those actions.

The primary responsibility of the system is to capture reality and improve coordination around it.

---

# 5. Target Customer

Initial target:
- Dental clinics
- Specialist clinics
- Consultant-driven clinics

Characteristics:
- Single location
- One or more doctors
- One or more assistants

---

# 6. Primary Users

## Assistant

The operational center of the clinic.

Responsibilities:

- create patients
- coordinate schedules
- communicate with patients
- manage follow-ups
- manage reminders
- coordinate consultants

## Doctor

Responsibilities:

- submit availability
- approve appointments
- review daily schedule
- determine follow-up requirements

## Clinic Owner

Responsibilities:

- manage staff
- oversee operations

## Practice Manager

Responsibilities:

- monitor workflows
- review operations

---

# 7. Real World Workflow Today

1. Patient calls.
2. Assistant answers.
3. Assistant gathers:
  	- patient name
  	- phone number
	- age
	- referral source
	- medical conditions
	- chief complaint
	- preferred times
4. Assistant determines:
	- which doctor should see the patient
	- whether consultant involvement is needed
	- whether referral exists
5. Assistant then negotiates between:
	- patient availability
	- doctor availability

This frequently requires multiple calls. The product exists to reduce this coordination burden.

---

# 8. Patient Lifecycle

## New Patient

Patient may be created without appointment.

Reasons:
- inquiry
- referral
- future scheduling

Required fields:
- name
- phone
- age

Additional fields:
- referral source
- medical conditions
- complaint
- notes

## Returning Patient

Assistant should immediately see:
- last two visits
- doctor seen
- treatment performed
- closing notes
- medical history recorded

---

# 9. Patient Search Philosophy

The most common clinic workflow is:
1. Patient calls.
2. Assistant searches.

Therefore search must be extremely fast.

Supported:
- name
- phone number

Nothing else required in V1.

---

# 10. Duplicate Patients

Duplicates will happen. The system should:
- check name
- check phone
- check age

Warn the assistant. Never block creation. Humans make the final decision.

---

# 11. Doctor Lifecycle

## Invite

Assistant creates doctor.

Fields:
- name
- phone
- specialty

Doctor receives invite.
`Status: Invited`

## Activation

1. Doctor creates account.
2. Doctor submits availability.

`Status: Active`

## Departure

If the Doctor becomes inactive, the history remains stored forever or until the clinic owner chooses to delete it.

---

# 12. Consultant Philosophy

Consultants are doctors. No special consultant workflow exists. From the system perspective:
- Doctor = Consultant

The distinction is operational, not technical.

---

# 13. Availability Management

Doctors submit weekly availability.

Example:

Monday:
9am - 12pm

Wednesday:
2pm - 5pm

**Availability becomes immediately usable. No approval required.**

---

# 14. Assistant-Controlled Availability

Real clinics often require assistants to act on behalf of doctors.

Example:
1. Consultant calls while driving.
2. Requests availability creation.
3. Assistant creates availability.
4. Doctor is notified.

This behavior is allowed.

---

# 15. Slot Generation

Availability windows generate:
30-minute slots.

This is a scheduling convenience. Appointments may consume multiple slots.

## 15.1 Multiple Slot bookings

### Booking Capacity Model

Different clinics operate differently. Some clinics require strict slot exclusivity. Other clinics intentionally overbook. The system shall support both models.

### Clinic Setting

Allow Multiple Bookings Per Slot

Values:

- `Enabled`
- `Disabled`

`Default: Disabled`

### Disabled Mode

A slot may contain only one appointment.

Example:

9:00 AM
Patient A

Result:

9:00 AM unavailable.

### Enabled Mode

A slot may contain multiple appointments.

Example:

9:00 AM

Patient A
Patient B
Patient C

Maximum capacity per slot: 3 patients

Once capacity is reached: Slot becomes unavailable.

### Queue Visualization

Assistants should see:

9:00 AM

1. Patient A
2. Patient B
3. Patient C


### Waitlist Support

When slot capacity has been reached, assistants may add patients to a waitlist associated with that specific doctor, date, and time slot.

Waitlisted patients do not consume slot capacity.

Waitlisted patients do not notify the doctor.

Waitlisted patients do not receive patient communication.

When capacity becomes available, the system should notify assistants that capacity has opened.

The system must never automatically promote waitlisted patients into appointment requests.

Assistants remain responsible for deciding which waitlisted patient should be offered the newly available capacity.

### Concurrency Rule

Slot capacity must be enforced atomically.

Example:
```
Capacity = 3
Current Count = 2
Two assistants attempt booking simultaneously.
Only one succeeds.
Final Count = 3
```
---

# 16. Appointment Creation

Assistant selects:

- patient
- doctor
- slot

Assistant submits request.

Slot enters: Pending

Doctor notified.

### Existing Appointment Detection

During appointment request creation, the system should check whether the patient already has future appointments.

Future appointments include:

- Pending
- Confirmed

If future appointments exist, the system should warn the assistant but should not block scheduling.

The assistant should be able to:

- Confirm and Proceed
- Check Appointment History
- Cancel Existing Appointment and Schedule New

---

# 17. Pending Requests

Pending slots remain visible. Other assistants can see:
- patient
- requested doctor
- request creator
- request age

**Pending requests expire after 120 minutes.**

Expired requests remain visible in the system and should be displayed as:

`Requested - Expired Approval`

Assistants should be able to re-trigger the approval notification workflow for pending or expired requests.

Doctors opening expired requests should see that the request has expired and can no longer be approved.


---

# 18. Concurrency Rules

First request wins. Second request fails. System must prevent double booking.

---

# 19. Appointment Approval

Doctor may:

- approve
- reject

Optional rejection message supported.

Upon approval:

- appointment confirmed
- Google Calendar updated
- WhatsApp confirmation sent

### Approval Screen

The approval screen should show:

- Patient Name
- Requested Time Slot
- Age
- Chief Complaint
- Notes

Patient history should not be automatically displayed.

Doctors may select:

`View Patient History`

to review historical appointments, treatments, medical history, and previous closing notes.

---

# 19.1 Doctor Direct Booking

Doctors should be able to create appointments directly without assistant involvement.

This workflow exists primarily for:

- After-hours scheduling
- Emergency appointments
- Personal patient contacts
- Consultant scheduling
- Assistant unavailable scenarios

If a doctor creates an appointment directly through the application, the following information is required:

- Patient Name
- Patient Phone Number

Doctor-created appointments are immediately confirmed and do not require an approval workflow.

Assistants should be notified that a doctor-created appointment exists.

The notification is informational and does not require assistant approval.

---

# 19.2 Doctor Override

Doctors may intentionally exceed normal slot capacity when required.

The system should allow a doctor to create an appointment even when slot capacity has already been reached.

The system must not automatically cancel existing appointments.

The doctor's action should be considered final.

Assistants should receive a notification indicating that a doctor override was created.

The purpose of the notification is awareness and coordination.

The purpose is not approval.

---

# 19.3 Retroactive Appointment Creation

The system should allow appointments to be created after the appointment time has already passed.

This workflow exists for situations such as:

- Emergency treatment
- Walk-in patients
- Offline scheduling
- System unavailability
- Administrative corrections

Retroactively created appointments should use the same Appointment entity as normal appointments.

The appointment should contain metadata indicating that it was created after the appointment occurred.

Retroactively created appointments may be created directly in the Completed state.

The purpose of this workflow is to reconstruct reality rather than replay historical workflow states.

---

# 20. Appointment Cancellation Philosophy

Doctors decide. Assistants coordinate. Therefore:

- Doctor requests cancellation.
- Assistant handles patient communication.

---

# 21. Appointment States

```
Draft

Pending

Confirmed

Arrived

Completed

Alternative:

Rejected

Cancelled

No Show
```

---

# 22. Arrival Workflow

Patient arrives.

Assistant marks: Arrived

Timestamp stored. If appointment not marked Arrived after 15 minutes: Assistant receives notification.

---

# 23. No Show Workflow

Assistant attempts contact.

If unresolved:

Mark No Show.

No Show remains part of history.

---

# 24. Completion Workflow

Doctor or assistant:

- select treatment performed
- add notes
- select post-op template
- edit template

Appointment completed.

WhatsApp instructions sent.

---

# 25. Follow-Up Philosophy

Doctor determines urgency.

Possible outcomes:

- none
- recommended
- mandatory

System tracks recommendation.

Humans perform scheduling.

---

# 26. Schedule Change Protection

Doctors cannot accidentally destroy booked schedules. If schedule modification affects appointments: Assistant must resolve appointments first.
Only then may change proceed.

---

# 27. WhatsApp Strategy

Supported:

- confirmations
- reminders
- cancellations
- post-op instructions

**Patient replies create assistant tasks. No conversational AI. No autonomous scheduling.**

If WhatsApp delivery fails, the appointment remains valid.

The assistant should be able to manually re-trigger WhatsApp communication from the application.


---

# 28. Google Calendar Strategy

System is source of truth.

Flow:
System -> Google Calendar

Not:
System <-> Google Calendar

**Calendar edits are ignored.**

External integrations such as Google Calendar and WhatsApp should only be triggered after the internal appointment state has been successfully committed.

Failed integration operations must not roll back valid appointment state changes.


---

# 29. Assistant Dashboard Philosophy

Assistants manage change.

Therefore dashboard prioritizes:

- accepted appointments
- rejected appointments
- overnight changes
- callbacks
- pending requests

The dashboard is action-oriented.

---

# 30. Doctor Dashboard Philosophy

Doctors need awareness, not administration.

Dashboard contains:

- today's appointments
- pending approvals
- daily AI brief

---

# 31. AI Philosophy

AI behaves like a chief of staff. Not a replacement assistant.

Daily brief examples:

- pending approvals
- follow-up risks
- schedule conflicts

Weekly and monthly summaries supported.

---

# 32. Permissions

Doctors may view:

- all patients
- all schedules
- appointment history

Assistants may:

- create patients
- edit patients
- create appointments
- edit appointments
- manage schedules

Clinic operates as a shared workspace.

---

# 33. Historical Records

History belongs to the clinic.

If employee leaves:
- attribution remains
- records remain

Example:

Requested By:
Priya (Assistant)

even if Priya left years ago.

---

# 34. Authentication

- Primary: Phone + OTP
- Secondary: Email + Password

Chosen because of Indian clinic workflows.

---

# 35. Deletion Philosophy

Delete means delete. No archive. No recycle bin. No soft delete. Confirmation required.
**Patient-requested deletion must remove data.**

---

# 36. Retention

Target visibility window: 3 years.
*Can be revisited later.*

---

# 37. Success Metrics

The product succeeds when clinics report:

- less dependence on memory
- fewer coordination calls
- easier scheduling
- better handoffs
- centralized knowledge
- automated reminders
- improved operational visibility

---

# 38. Future Vision

Future versions may include:

- Android
- iOS
- Multi-branch clinics
- Advanced reporting
- Schedule request workflows
- AI-assisted scheduling

These are intentionally excluded from V1.

---

# 39. Internationalization & Localization (i18n)

The product is India-first and must support multiple languages without later refactoring. Internationalization is a core product requirement, not an enhancement.

## Locales
- The application is i18n-ready from the beginning.
- English is the default locale.
- Hindi is the first non-English supported language.
- Marathi is planned next, because the initial market is Pune / Maharashtra.

## What must be localizable (never hardcoded)
All user-facing text must come from translation resources, not literals in code:
- UI text, page titles, navigation / sidebar labels
- Form labels, placeholders, buttons
- Validation messages
- Status labels (appointment states, member roles/statuses, etc.)
- Empty states and loading states
- Notification copy
- WhatsApp / communication templates

## Frontend owns user-facing translation
- The backend returns stable, machine-readable codes for errors and statuses wherever possible.
- The frontend translates those codes into localized, user-facing messages.
- English backend messages must not be used as the display source.

## Language preference
- Clinic-level and user-level language preference are supported conceptually.
- For V1, locale may be stored client-side; a persisted user/clinic preference can follow without refactoring.

## Clinical / entered data is not translated
- Human-entered content — patient names, doctor notes, treatment notes, complaints — is stored and displayed exactly as entered.
- V1 does not auto-translate clinical content. Only product/UI chrome is localized.

## Communication templates
- WhatsApp and notification templates must be localization-ready (selectable per recipient / clinic locale), with English as the default/fallback.

---

# Closing Statement

***This product is not attempting to reinvent healthcare software. It is attempting to solve a narrow but extremely painful operational problem. If successful, clinics should feel that operational coordination became dramatically easier while requiring minimal behavioral change from doctors, assistants, and patients.***
