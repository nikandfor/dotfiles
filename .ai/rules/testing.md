# Testing — delegate to a persistent test subagent

When a task involves **creating, updating, or running tests**, delegate that work to a dedicated test subagent rather than doing it inline.

**Why:** it keeps the main design/build context compact — the heavy parts (full test output, iteration on failures) stay out of the way. The test agent accrues its own context over the project: the test harness/API, the conventions, and how to run the suites.

**How to apply:**

- Finish the code change first — compiling and lint-clean — *then* hand off. The repo is shared, so handing off mid-edit risks clobbering.
- Give the agent **precise new behavior and selectors**, not vague intent: it can't ask follow-ups mid-task, so spell out what changed and what the tests should now assert.
- Division of labour: it owns the test files and running the suites. It **fixes tests**; if it suspects a real bug in the source, it **reports** rather than "fixing" it — source/design decisions stay with the main agent.
- Ask for a **terse report**: lint state, pass/fail counts per suite, one line per change. No full file dumps or full command logs.
- **Reuse the same agent** across the project (continue it, don't spawn fresh) so it keeps context. Spawn a new one only for a genuinely separate project or area.
