# Bash / CLI / scripting style

Reference for the philosophy: `github.com/nikandfor/testlib.sh`. Follow its spirit (status accumulation, defer, output discipline, files-as-registers), not its letter.

## Language & deps

- **POSIX portability matters.** Prefer POSIX sh constructs when they do the job; reach for bashisms (`[[ ]]`, arrays, `[[ -v var ]]`, `=~`, `${BASH_SOURCE[0]}`) only when they genuinely earn their keep — and then declare it honestly with `#!/usr/bin/env bash`. Don't sprinkle bash-only syntax into a script that's otherwise plain sh.
- Minimal dep surface, maximal use of each dep: bash + curl + jq and that's it. jq is the assertion/query language; curl's own features (`-w`, `-D`) do response capture. Everything else is builtins.
- Libraries enforce sourcing: `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then echo "must be sourced"; exit 1; fi`.

## Error handling

- **No `set -e`, no `set -u`.** Error handling is explicit status accumulation: a global `_status=0` plus a tiny verb vocabulary — `fail` (silent mark), `FAIL "msg"` (loud mark, returns 1), `failed`/`stillok` (predicates), `assertok` (bail out now). Scripts keep running after failures; the EXIT trap reports the verdict.
- Functions are written so their exit status IS the result; `&&`-chains are the composition operator:
  ```bash
  function apicall {
      runcurl "$@" &&
      checkboth '. >= 200 and . < 300' '(has("error")) | not'
  }
  ```
- Go-style defer, ported literally: a `traps=()` array, `defer cmd ...` appends, one `trap exit_code EXIT` runs them all and prints the final verdict (`ALL IS OK` / `TEST FAILED`), exiting with `$_status`.

## Structure

- Small named verbs, 3-10 lines each, layered: output plumbing → status verbs → command echo → result accessors → assertions → high-level verbs. A script is then a linear sequence of calls.
- State between steps lives in files, not variables: command output to `.out`, status code to `.code`, headers to `.header`; accessor functions (`res`, `code`, `jsonres`) read them. Files are registers.
- Config via plain ambient variables the caller may set, with defaults: `seconds="${seconds:-15}"`, checked with `[[ -v format ]]`. No getopts ceremony for libraries.

## Naming & formatting

- Short lowercase names (`s`, `v`, `i`, `lib`, `outputdir`); internal state underscore-prefixed (`_status`); `local` for function temporaries.
- Tabs for indentation; blank-line paragraphing, same rhythm as my Go.
- Quoting: quote expansions — `"$@"`, `"${arr[@]}"`, `"$var"`. Inside a larger string use `"$*"`, not `"$@"`. Multi-word commands and flag sets are arrays expanded as `"${arr[@]}"` (e.g. `format=(jq -C .)`, `curlflags=(-H 'X: y')`), never unquoted strings relying on word splitting.

## Output discipline

- All commentary/diagnostics go to stderr (`{ ... } >&2` group blocks); stdout stays clean data.
- Every command echoes itself before running, quoted so it can be copy-pasted and rerun verbatim (escalating quoting: bare → `"…"` → `'…'` → `printf %q`). Output should read like an interactive session, not a log.
- ANSI colors via raw codes in variables and one `color` filter function that checks `-t` tty-ness and passes through untouched when piped.
- Failed assertions print the failing predicate itself as the error message.
- Degrade gracefully: if an optional helper isn't available yet, stub it (`run() { "$@"; }`) instead of dying.
