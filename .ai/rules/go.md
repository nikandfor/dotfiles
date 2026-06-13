# Go style — write code exactly like this

Extracted from my repos (json2, cbor, batch, bufq, mux, websocket, socks5, graceful, quantile, eazy, tlog, errors, loc, cli, hacked, slow) + Effective Go + CodeReviewComments. Local copies: `~/nikandfor/`, `~/w/tlog/`, `~/w/slowlang/slow` — read the real code when unsure.

## Iron rules (exceptions are super-super rare)

1. **Every error propagates to the topmost caller** — usually `main`, the server's per-connection handler, or the start of a long-running background job whose failure must not take down the whole app. No swallowing mid-stack; wrap and return.
2. **Every acquired resource is released on the very next line in the same function**: `defer f.Close()` (or the `closer(c, &err, "...")` helper) immediately after acquisition. The ONLY thing allowed in between is `if err != nil { ... }`.
3. **Every started goroutine is waited in the same function that started it** — `wg.Add`/`go`/`defer wg.Wait()`, or drain the exact-capacity result channel. Same discipline as resources: start and wait live together.

## Dependencies

- Near-zero deps. Allowed universe: stdlib, `nikand.dev/go/*`, `tlog.app/go/*`, testify/assert (tests only). Nothing else without asking.
- A private 15-line helper beats importing my own module (cli has its own `wrap()` clone rather than depending on tlog errors). Tiny generic helpers (`csel`, `grow`, `dup`) are re-declared per package, not shared.
- Heavy deps (DB clients, fsnotify) confined to `cmd/` and `ext/` subpackages, never in the library core.

## API design

- Stateless codec types with value receivers, zero-value usable: `type Iterator struct{}`. All state through args/returns.
- The canonical parse signature — buffer + cursor in, value + new position + error out:
  ```go
  func (d Iterator) Skip(b []byte, st int) (i int, err error)
  func (d Decoder) Tag(b []byte, st int) (tag, l, i int, err error)
  ```
  Body starts `i = st`; on failure return `st` (the start, not the failure position). Bounds checks are explicit arithmetic: `if i+size > len(b) { return st, ErrShortBuffer }`. Pointer-cursor variants (`Break(b []byte, i *int) bool`, `ForMore(b, &i, typ, &err)`) when they make call-site loops clean.
- Append-style APIs everywhere: `func (e Encoder) AppendString(b []byte, s string) []byte` — take dst buffer first, return it grown. Never allocate internally; decoders return subslices of input. Caller passes reuse buffer `buf[:0]`.
- Two layers: stateless low-level codec (Encoder/Decoder) + stateful convenience wrapper (Writer/Reader) that embeds the codec and the io interface.
- Config = exported struct fields, documented on the field. NO functional options. Constructors `New`/`Make*` are trivial; `Reset`/`ResetBytes`/`ResetSize` methods reuse allocated objects.
- Zero value must be useful: `var s websocket.Server` works. Lazy-init in methods: `if c.cond.L == nil { c.cond.L = &c.mu }`. Nil receivers are valid no-ops where it makes sense (`if l == nil { return }`).
- Handler/callback types are func TYPE ALIASES (`=`), not defined types, so any matching literal fits without conversion: `Handler = func(c *Context, w http.ResponseWriter, req *http.Request) error`.
- Error-returning HTTP handlers; middleware handles the error. Middlewares ARE handlers (gin-style Next), not `func(Handler) Handler` wrappers.
- Bitmask feature flags with `Is` method, not bool fields: `f&ff == ff`.
- `Should*` prefix for error-swallowing variants; `*Multi` suffix for batch ops; `FormatTo(b []byte, ...)` for alloc-free variants.
- Misuse (programmer error) = panic, usually with the bare offending value: `panic(l)`, `panic(cmd)`, or with usage string.

## Memory

- Reuse heavily. No sync.Pool — reuse via Reset methods, retained struct fields, caller-owned buffers.
- One owned scratch buffer per stateful type, reset by reslicing: `l.b = e.AppendMap(l.b[:0], -1)` then append-chain.
- `func grow(b []byte, n int) []byte { if cap(b) >= n { return b[:cap(b)] }; return append(b, make([]byte, n-len(b))...) }` — redeclared per package.
- Stack arrays for small scratch: `var buf [32]byte`. Hot paths may use the noescape hack (isolated in `unsafe.go`, comment ends `// USE CAREFULLY!`).
- Manual byte encoding `buf[i] = byte(x >> 8); i++` — no bytes.Buffer, no binary.Write; stdlib `binary.BigEndian.AppendUint16` when it fits exactly.
- unsafe lives in dedicated files/packages, risky variants behind build tags with a safe fallback file.

## Errors

- Libraries: stdlib `errors` + `fmt.Errorf("%w")`. Applications/cmd: `tlog.app/go/errors` — `errors.Wrap(err, "msg")`, printf built in, panics on nil err; `WrapNil` when err may be nil. NEVER stdlib `errors` in app code where tlog errors is already in use.
- Wrap message = terse lowercase verb-phrase naming the failed step: `"open log file"`, `"dial proxy"`, `"parse %v", a`. NEVER "failed to", "could not", "error doing". No trailing punctuation. `%v` operands when they disambiguate. With tlog errors no `%w` — Wrap chains; `%w` only with fmt.Errorf matching a sentinel.
- Sentinels: `var ( ErrSyntax = errors.New("syntax error"); ... )` block, lowercase, terse. Alias stdlib sentinels instead of redefining: `ErrShortBuffer = io.ErrShortBuffer`.
- Hot paths may encode errors as negative ints (typed `Error int` with `Error() string`); protocol codes implement `error` directly (Status, Reply).
- Close-in-defer keeps the first error — named return + helper:
  ```go
  func closer(c io.Closer, errp *error, msg string) {
      err := c.Close()
      if *errp == nil && err != nil { *errp = errors.Wrap(err, msg) }
  }
  // func f() (err error) { ...; defer closer(c, &err, "close conn") }
  ```
  `*error` out-params are a standard tool.
- EOF normalization at boundaries: mid-protocol `io.EOF` → `io.ErrUnexpectedEOF`; end-of-frame → `nil`.
- Discarded errors are explicit `_ =` with a nearby rationale comment.
- Errors = input/environment problems. Panics = compiler/programmer bugs: every type-switch `default:` is `panic(x)` (the value itself). No recover except goroutine firewalls and panic-safe primitives that re-raise.

## Concurrency — last resort

The Go face of *explicit over implicit* (AGENTS.md): concurrency hides control flow, so it's the last resort, and where it's unavoidable the flow is made visible — goroutines waited where started, channels avoided as event coordinators.

- Default is sequential, linear code. Reach for concurrency only when genuinely needed.
- When needed: `sync.Mutex` + `sync.Cond` + plain ints. Channels almost never inside libraries — only app-level fan-in (buffered to exact capacity, first-error-wins drain). No channels as event/coordination buses: you can't see who runs when.
- My trademark lock idiom — defer written ABOVE Lock:
  ```go
  defer q.mu.Unlock()
  q.mu.Lock()
  ```
- Cond: always `for cond { c.cond.Wait() }`; `Broadcast()` on state change, often deferred together with Unlock.
- State encoded compactly: sign-flip phases (`cnt = -cnt`), negative size sentinels, small-int state machines in const blocks with `panic(usage)` on misuse. Atomics only for lock-free counters.
- Blocking is a `bool` param (`Enter(blocking bool)`), not a TryX method pair.
- Unlock-around-callback: `c.mu.Unlock(); defer c.mu.Lock(); res, err = f(ctx)` — user code runs unlocked.
- Per-connection goroutines guarded by `var wg sync.WaitGroup; defer wg.Wait()` in the accept loop. Goroutine lifetimes must be obvious.
- Lifecycle via `graceful.Group`: tasks as `func(ctx) error`, first finisher cancels shared ctx, `IgnoreErrors(context.Canceled)`.
- Context: passed, never stored. First param, `ctx`. Primitives take ctx but cancellation is mostly the caller's job — keep the primitive simple. Net I/O cancellation = ctx→deadline watcher (websocket.Stopper pattern).

## Naming

- Receivers: single letter matching role (`d` decoder, `e` encoder, `w` writer, `r` reader, `c` conn/command, `l` logger, `s` span/scope, `p` package-ctx). `tb` for `*testing.T` AND `*testing.B`.
- Cursor vocabulary: `b` buffer, `st` start, `i` position, `end`, `l` length, `n`, `tag`, `sub`, `raw`, `off`, `v` value, `x` the any-typed node, `tr` tlog span, `q` scratch/secondary. Maps named by mapping: `l2i`, `renm`.
- Unexported helpers: lowercase single words (`valsize`, `skipVal`, `seekObj`).
- MixedCaps always; no Get prefix; initialisms keep case (`ID`, `URL`); no stutter (`bufio.Reader` not `bufio.BufReader`).
- Files: lowercase single noun per concern (`iterator.go`, `conn_read.go`, `unsafe.go`). Packages: short lowercase single words (`ir`, `tp`, `df`, `set`). FORBIDDEN package names: util, common, misc, helpers, types, api, interfaces.

## Organization

- Flat packages. No `internal/`, no `pkg/`, no layered trees. Repo root = the package. Subpackages only for genuinely separate things.
- One file ≈ one concern/pass. A 1300-line file is fine if it's one pass; a 300-line switch is NOT split for size.
- Every file: ONE `type ( ... )` block at top (even for one type), then grouped `const`/`var` blocks (iota, binary literals with underscores for masks, section comments), constructors, methods.
- Struct field order: embedded io/codec first, exported config fields, then mutex as visual divider, then protected scratch buffers below (`// end of mu` comment when mutex is mid-struct).
- Local func literals instead of methods for one-use helpers, defined where needed; immediately-invoked when computing a value.
- Big pipelines (compiler-scale): flat arena of nodes addressed by integer ids (`Expr int`, `Exprs []any`, parallel slices), `const Nil Expr = -1`, negative sentinels for lookups. Ids over pointers. Context threading by struct embedding chains, not parameter lists.

## Control flow

- Early returns, guard clauses, max 2-3 nesting levels. Error handled first, happy path un-indented, no `else` after return.
- Blank-line rhythm is mandatory: blank line before every `return`, between every logical micro-step.
- Tagless `switch { case ... }` over if-chains; empty switch cases as documentation.
- `goto again` / labels (`break authloop`, `goto restart`) used without apology where they simplify.
- Named results for defer-modified errors and doc clarity; bare `return` in short funcs.
- Single-statement funcs on one line.

## Interfaces

- Consumer-side only, defined when needed, usually 1 method, named by role (`-er`). Never speculative, never for mocking, never implementor-side. Return concrete types.
- Func fields beat interfaces for behavior injection: `NewID func() ID`, `Action func(c *Command) error`.
- Anonymous inline interfaces at use sites: `interface{ SetReadDeadline(time.Time) error }` assertion right where needed.
- Embed stdlib interfaces for composition (`Conn struct { net.Conn; ... }`); embed-to-stub in tests.

## Logging (tlog)

- `tr := tlog.SpawnFromContext(ctx, "snake_case_name", "k", v); defer tr.Finish("err", &err)` — pointer args so deferred values are final. Variable always `tr`.
- Flat key-value variadic: `tlog.Printw("listen", "scheme", u.Scheme, "host", u.Host)`. Messages short lowercase; error key is always `"err"`.
- Topics over levels: `tlog.V("rawdb").Printw(...)`, `tlog.If("dump_pkg")`. Debug instrumentation is a feature, runtime-toggled by `-v` topics.
- Nil logger is valid and ignores everything.

## CLI (nikand.dev/go/cli)

- `func main() { cli.RunAndExit(App(), os.Args, os.Environ()) }` — two lines.
- Declarative `*cli.Command` struct-literal tree in `App()`; comma-separated aliases in Name (`"delete,del,rm"`); `cli.NewFlag("output,o", "-", "description")`; root holds `log`/`v`/`debug` flags + `Before` hook that sets up tlog.
- Actions: top-level `func name(c *cli.Command) error`, reading flags by name.

## Testing

- stdlib `testing` first; testify/assert or my `nikandfor/assert` where convenient; zero-dep repos use plain `tb.Errorf("wanted %v, got %v", ...)`.
- Table tests: anonymous struct slice INLINE in the for statement, no named `tests` var.
- Round-trips are the core method: encode → compare bytes (hex verbs `%x`, `%#x`, `%[1]`) → decode → compare value + final index.
- Concurrency: stress tests — N goroutines × M iterations, `runtime.Gosched()` injections, scripted panics, final invariant check; CI runs `go test -race -count=1000`.
- Fuzzing for parsers, differential against stdlib. Benchmarks with `ReportAllocs`; alloc count is a tracked feature.
- Generous gated `tb.Logf` dumps: `if tb.Failed() { tb.Logf("dump\n%v", s.dump()) }`. Unexported `dump() string` debug methods kept in production files.

## Comments

- Sparse, high-value. Doc comments in stdlib voice on exported API, with usage snippets in the comment when the call protocol is non-obvious. ASCII diagrams for buffer/window arithmetic.
- Inline comments only for genuinely non-obvious facts; measured rejected alternatives may stay commented out with the reason.
- Debug prints and superseded versions (`//go:build ignore` files, numbered `compile5.go`/`compile6.go`) stay while the new code matures — quick reference for the rewrite — then get cleaned up once it's stable.

## Lint

- golangci-lint enable-all MINUS the style-fighting linters: wsl, varnamelen, mnd/gomnd, funlen, nlreturn, err113, nonamedreturns, exhaustruct. lll ~170. depguard allowlist: `$gostd`, testify, `nikand.dev/go/*`, `tlog.app/go/*`. `//nolint:` directives are precise and inline.
