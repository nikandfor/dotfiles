# Who I am

I'm nikandfor (`nikand.dev`, `tlog.app`). I write minimal, simple, linear code.

My public code is available on `github.com/nikandfor/*`, `github.com/tlog-dev/*`, `codeberg.org/nikandfor/*`, `codeberg.org/tlog/*`.
If in doubt about my style, clone my repos locally and read the real code.

# Core philosophy (applies to every language)

- Minimal, simple, linear code. Shallow nesting, early returns, small composable verbs.
- No concurrency, channels, or goroutines unless genuinely needed. Sequential first.
- Reuse memory heavily: caller-provided buffers, `buf[:0]`, Reset methods, long-lived structs.
- Avoid 3rd-party dependencies. Write the 15-line helper instead of importing it. Exceptions: official clients and genuinely big projects (don't reimplement ClickHouse drivers or TLS).
- No foreign practices. Java patterns, clean/hexagonal architecture, DI frameworks, interface-everywhere, repository/service/controller layering — all rejected. Go canon is go.dev only: Effective Go, CodeReviewComments, the spec. Not blogs, not courses, not "enterprise best practices".
- Don't define abstractions before they're needed. Concrete first; generalize on the second or third real duplication.
- Superseded code and commented-out debug lines are parked temporarily, not forever: keep old versions (`//go:build ignore`) and debug prints around while the new code matures — they're quick reference for importing solutions into the rewrite — then clean them up once it's stable and works fine.
- Panic loudly on can't-happen (with the offending value), accumulate/return quietly on expected failure.
- Errors and misuse: errors are for input/environment problems; panics are for programmer bugs.
- Output and visual design (logging, CLI output, status lines, and code alike): keep everything calm except essentials — muted/gray for routine values, color only for what needs attention. Structure is implicit, carried by spacing and alignment, not drawn with distracting symbols (pipes, boxes, heavy separators). Care about formatting: aligned variables/values, empty lines between logical blocks, lightweight overall.
- Iron rules (exceptions super-super rare): every error propagates to the topmost caller (main / connection handler / background-job root); every acquired resource is released on the very next line of the same function (only `if err != nil` may sit between); every started goroutine is waited in the same function that started it.

# Detailed rules — read on demand

These are NOT auto-loaded. Read the matching file BEFORE writing code in that area:

| Task involves | Read |
|---|---|
| Any Go code | `~/.ai/rules/go.md` |
| ClickHouse schemas, queries, ch-go | `~/.ai/rules/clickhouse.md` |
| Bash, shell scripts, CLI test tooling | `~/.ai/rules/shell.md` |
