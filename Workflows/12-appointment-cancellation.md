# Appointment Cancellation

Purpose: Cancel confirmed appointments while preserving audit history.

Key Rules:
- Cancellation reason required; note optional.
- Notify patient checkbox, enabled by default.
- Patient-requested cancellations may be executed directly by assistant.
- Doctor-requested cancellations create Cancellation Requested state.
- Assistant coordinates patient communication.
- Capacity released only after final cancellation.
- Google Calendar delete hook executes after cancellation.
- Cancellation-to-reschedule shortcut supported.
- Concurrency validation required.
