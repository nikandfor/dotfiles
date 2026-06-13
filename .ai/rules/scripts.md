# scripts/ — build, run, integration tests for Go services

A service's `scripts/` directory is bash + curl + jq: a vendored test harness wrapped by a
thin `tests/lib.sh`, a few orchestration scripts, and a collection of `tests/*.sh` scripts
that drive the running service over HTTP. The bash style underneath is `rules/shell.md`; the
service it builds and runs is `rules/docker.md`.

## Why this exists

- **Unit tests can't cover dependencies.** `go test` is for pure local logic. Anything that
  needs a real database (or any real external piece) isn't unit-testable without faking the
  very thing under test. So that work moves out: bring the real service + real datastore up
  in compose (`docker.md`) and drive it over HTTP. The two layers are complementary, not
  competing.
- **One harness, many setups.** The same `tests/*.sh` run against a locally-built binary,
  against the compose image, and against staging — plain tests, docker tests, whatever comes
  next all reuse the scripts. This is the *fold-and-reuse* principle (AGENTS.md) applied to
  tests: one set, configured per setup, not a variant per environment.
- **Tests are interactive.** Every call is printed, quoted so you can copy-paste-rerun it
  verbatim. When something looks off, paste the exact command, add `-v` or tweak a field,
  and inspect — no test framework between you and the request. Output is verbose yet clear:
  it reads like a terminal session, not a log.
- **bash + curl + jq is enough, and it disciplines the API.** A small, portable toolkit
  covers a large suite anywhere. More importantly: if an endpoint is awkward to hit with
  plain curl and jq, it's awkward for your users too. Writing the tests this way puts you in
  their shoes and pushes the API toward something simple enough to use by hand.

## Using the harness

- **`testlib.sh` is vendored, not written.** It (with `run_all.sh` and `update_testlib.sh`)
  comes from `codeberg.org/nikandfor/testlib.sh` via `update_testlib.sh` — refresh it, never
  hand-edit. It supplies the verbs; you supply the narration.
- **Project additions live in a thin `tests/lib.sh`** that sources `../testlib.sh` and adds
  service-specific helpers (shared login steps, fixtures, base URLs). The test scripts in
  `tests/` source this `lib.sh`, not `testlib.sh` directly — so per-project sugar sits in one
  place and the vendored file stays pristine and refreshable. The orchestration scripts up in
  `scripts/` (build, prepare, run-local) need no helpers and source `testlib.sh` straight.

      #!/usr/bin/env bash

      source "$(dirname "$0")/../testlib.sh"

      # service-specific helpers on top of the vendored harness
      # (shared logins, fixtures, common checks)

- **What the harness does for you**, so a test script stays pure narration: prints and
  quotes every command, colorizes, captures each response into register files
  (`.out`/`.code`/`.header`), accumulates pass/fail without `set -e`, and prints the final
  `ALL IS OK` / `TEST FAILED` verdict from an EXIT trap. See `shell.md` for the style this
  embodies.
- **The handful of verbs you'll actually reach for:** `comment` (narrate a step), `apicall`
  (happy path — 2xx, no error envelope), `apicallerr` (negative test), `apicallshould`
  (may-or-may-not-exist probe that won't fail the run), `res` (the last response body),
  `check '<jq predicate over res>'`, `waitfor` (readiness polling), and `format=` set to a
  command (e.g. `format=(jq …)`) to reshape output for easier reading. The rest is
  discoverable in `testlib.sh` itself; reach for it when you need it rather than memorizing it.

## Per-project scripts

Copied and adapted per service (the harness above is not). `<svc>` is the service/binary
name, as in `docker.md`.

**build.sh** — stamp version vars from git and hand them to the compose build (the `ARG`s
in `docker.md`):

	#!/bin/sh

	dateformat='%a %b %d %H:%M:%S %z %Y'

	SVC_REF=$(git branch --show-current) \
	    VERSION=$(git describe --tag --dirty --always) \
	    COMMIT=$(git rev-parse HEAD) \
	    COMMIT_DATE=$(git show -s --format=%cd --date=format:"$dateformat" HEAD) \
	    BUILD_DATE=$(date +"$dateformat") \
	    docker compose build <svc>

**prepare.sh** — bring the datastore to a clean state before a run (reset + init) over the
debug surface:

	#!/usr/bin/env bash

	debug="${debug:-http://localhost:6060}"

	source "$(dirname "$0")/testlib.sh"

	run curl -s -XPOST "$debug/service-init"

**run_tests_local.sh** — build the binary, start it, wait until it answers, run the suite,
stop it. Start-and-stop live in one function via `defer` (the shell mirror of go.md's
resource discipline):

	#!/usr/bin/env bash

	http="${http:-localhost:8080}"
	debug="${debug:-localhost:6060}"

	source "$(dirname "$0")/testlib.sh"

	function stopsvc {
	    run pkill <svc>
	    run wait $svcpid

	    test -f .logs && cat .logs
	}

	run pkill <svc>

	comment Building
	run go build -o .<svc> ./cmd/<svc>/ || fail
	assertok

	cmd="./.<svc> run -http $http -debug $debug"
	printcmd $cmd | color 2 $bold >&2

	$cmd &>.logs &
	svcpid=$!
	defer stopsvc
	assertok

	comment "Wait until it's up..."
	waitfor run curl -sf "http://$debug/ping" || FAIL "Didn't start"

	http=http://$http debug=http://$debug "$(dirname "$0")/run_all.sh" "$@" || fail

`run_all.sh` (vendored) takes the script list and runs each in order —
`./run_tests_local.sh ./scripts/tests/a.sh ./scripts/tests/b.sh` — and is also what the
compose tests overlay calls.

## A test script

Env-configurable base URL, source `lib.sh`, announce what it's pointed at and grab
`/version` (so a saved run is self-describing), then walk a small story top to bottom —
create something, check the response, pull a value out of it, use that value in the next
calls, and poke the error paths:

	#!/usr/bin/env bash

	base="${api:-http://localhost:8080}/v0"
	cookie="-b .cookie -c .cookie"

	source "$(dirname "$0")/lib.sh"

	comment "Using $base api endpoint. Version:"
	apicall $base/version

	comment "Create an item"
	apicall $cookie $base/items --json '{"title": "first"}'
	check '.title == "first"'

	key=$(res | jq -r .key)

	comment "Read it back"
	apicall $cookie $base/items/$key
	check '.title == "first"'

	comment "Rename it"
	jq -nc >.req "{ title: \"second\", keyback: \"$key\" }"
	apicall $cookie $base/items/$key -XPATCH --json "$(cat .req)"
	check '.title == "second"'

	comment "Missing item is a 404"
	apicallerr $cookie $base/items/nope
	checkcode '. == 404'

	comment "Empty payload is rejected"
	apicallerr $cookie $base/items --json '{}'

The idioms, all visible above:

- **URLs from env with defaults** (`${api:-…}`) so the identical script runs against local,
  compose, or staging — the caller sets `api`/`debug`, the file hardcodes nothing.
- **Pull a value out and reuse it** — `res | jq -r .field` reads from the last response;
  feed it into the next path or body. That chaining is the test.
- **Build bodies with jq** — `jq -nc >.req "{…}"` then `--json "$(cat .req)"`. Mostly it
  spares you wrestling with json quotes; as a bonus, interpolated values are escaped, so
  the payload is always valid JSON.
- **Pick the right verb** — `apicall` for the happy path, `apicallerr` for negative tests,
  `apicallshould` for "may or may not exist" probes that shouldn't fail the run.
- **Assert an exact status** — `apicallerr` only checks for ≥ 400; when you expect a
  specific code use `checkcode '. == 404'`, or the `if4xx` / `if5xx` predicates in a
  condition.
- **Cookie jars** (`-b .cookie -c .cookie`) carry a session across calls; a second jar for
  a second identity.

A utility script that only borrows `run`/colors from the harness — not its assertions —
can drop the trailing `ALL IS OK` / `TEST FAILED` verdict with `trap - 0` after sourcing
`testlib.sh` (as `prepare.sh` could).
