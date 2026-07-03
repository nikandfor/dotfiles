# Front-end — Deno + Lit, dual-suite tests

Conventions for building web UIs. Read before starting front-end work.

## Toolchain

- **Sandbox everything.** Dev server, bundler, build, test runner go through `scripts/box.sh`, never bare. See `sandbox.md` — the deno tasks already wrap box, so run `deno task dev`/`test`, don't box a second time.
- **Deno, not Node.** Prefer Deno for any new front-end. If a library is Node-only, pick a different library before switching the project to Node — the only exception is a big legacy project where Deno isn't viable.
- **Lit is the default framework.** Web components, plain `customElements.define`. Components stay passive and domain-blind (data/candidates handed in, events out); app-specific wiring lives at the seam (context providers), not inside the widget.
- **Bundle with esbuild + the deno loader** (transpile-only): type errors do NOT block the dev bundle, so typecheck separately with `deno check`. `strict: true` always.
- **Nothing nailed down** (AGENTS.md core rule applied to the front-end): only the core is required; storage (localStorage / sessionStorage / IndexedDB), API base URL, and optional side-services are stubbable/swappable and namespaced by a `?ns=` query prefix, so tabs, configs, and test runs stay isolated.

## Tests are required — one cases list, two suites

Write the test cases **once** in a shared list; two runners consume it:

- **`deno test`** runs the **model / pure-logic** cases headlessly (fast, CI-friendly).
- **A headless browser** (e.g. astral) runs the **UI** cases — mount a real component, drive it, assert on the rendered DOM. Always `close()` the browser in `try/finally`.

### One test per routine, sequential

Do NOT write incremental `A?`, `AB?`, `ABC?` tests that each redo setup plus one more step. Write **one test per routine** that mounts/sets up once and walks the sequence, asserting after each step: `A? B? C?`.

- **Stop at the first failed check** — the assertion throws and ends that routine in place; later steps don't run.
- **Leave the failed state playable.** For UI cases the mounted component stays on-screen exactly at the failing step, so a human can inspect and poke it. The harness never tears down; the runner reveals a failed case's stage.

### Human-oriented tests page

Besides headless runs, serve an HTML page with a calm, human-driven UI over the same cases:

- Global: **run all**, **reset all**.
- Per test: **run / stop**, **reset**, **play / hide** (UI components only — mount it live to interact), **show / hide code** (the test case's own steps/source, so you can read what it does — not the component's source).
- Gate it behind debug mode (e.g. a key chord), parked out of the product UI.

### A component playground too

Keep a `/debug` playground (sibling to the test page, same debug gate) that mounts each generic widget with stand-in data, so components are validated by hand before anything depends on them. A new reusable widget gets a playground entry.

### Delegate the test work

Hand test writing/running to a persistent test subagent to keep the build context compact — see `testing.md`.
