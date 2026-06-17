# Doctor Direct Booking

Purpose: Allow doctors to create confirmed appointments outside normal assistant workflow.

Key Rules:
- Creates confirmed appointment immediately.
- Name and phone required.
- Auto-create patient if needed.
- Duplicate detection warns but does not block.
- Capacity override allowed.
- Assistant always notified.
- Standard confirmation hooks execute.
- Assistant may enrich appointment later.
