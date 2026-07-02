# ASSUMPTION-HALT — dispatch directive

Prepend this block to **every code-writing subagent dispatch** (implementers and fixers; a
useful lens for reviewers too). Subagents do **not** inherit session rules, so the halt must be
injected each time — the same gap that requires injecting Ponytail.

> **ASSUMPTION-HALT (binding for this task):** You inherit no session rules. If you meet ANY
> choice not explicitly specified in your instructions or the linked spec — product, design,
> data, scope, or a "small" detail — **STOP and return a question to the dispatcher; do NOT
> pick a default, infer, or proceed.** Guessing is a defect. (Golden Rule 2.4 — never proceed
> on an assumption; a spec with an OPEN decision is BLOCKED.)
