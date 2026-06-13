# OpenAPI documentation — Go services

## Doctrine

- **Hand-written specs**: OpenAPI YAML in the service's `docs/` package, written like
  code — no generators, no comment annotations (swaggo and friends rejected). Schema
  evolution is editing the YAML. Target 3.1 for new specs.
- **One spec file per API surface.** Public API is `openapi.yaml`; auxiliary surfaces get
  their own complete standalone files in the same dir (`system.yaml`, `debug.yaml`).
  Each is self-contained — own `info`, `servers`, `tags` — never cross-file `$ref`s.
  Never mix surfaces in one file; never leave an internal surface undocumented just
  because it's internal.
- **Sync discipline**: a small endpoint change updates the spec in the same commit. A new
  endpoint group / subsystem spanning several commits gets its spec as a separate
  following commit. Anything beyond that is drift, and drift is a bug.

## Spec style

- `tags` declared once at the top with descriptions; every operation tagged.
  `operationId` optional — don't bother unless something consumes it.
- Descriptions document *behavior*, not the schema again: defaults, edge cases, lifecycle
  (“the nonce is short-lived and can only be used once”).
- **Schemas come from the handler, not imagination.** Handlers follow one template:
  request parsing at the top (right after the `tr :=` / session preamble) — body
  type/structure first if there is one, then query parameters and/or overrides; business
  logic; response written at the end, its type just as visible. Read the handler
  top-to-bottom and the request/response schemas, parameter names, types, and defaults
  fall out.
- Shared things live in `components` and are `$ref`'d: responses (incl. error responses,
  e.g. a shared 429), schemas, parameters. No copy-pasted response bodies. One error
  envelope schema.
- Global `security:` with a named scheme; public operations opt out explicitly with
  `security: []` — the exception is visible at the operation, not implied.
- `servers`, in order: relative URL of this server first (`/vX/`, description
  “This server”), named environments, then an `{url}` variable with a default. The UI
  page rewrites “This server” from the page URL, so specs stay environment-agnostic.
- `info` carries real `contact` and `license`; `externalDocs` when a docs site exists.

## Go side — docs/ package

UI page + spec files + one Go file; nothing else. Mounted at `/vX/docs/`, and `/vX/`
answers with a relative redirect to `docs/` — hitting the API base lands in the
interactive reference, and relative `openapi.yaml` / derived server URLs resolve without
configuration.

`docs.go` barely changes between projects — copy it as is:

	package docs

	import (
		"context"
		"embed"
		"io/fs"
		"net/http"
		"os"

		"nikand.dev/go/mux"
		"tlog.app/go/tlog"
	)

	//go:embed index.html
	//go:embed openapi.yaml
	var efs embed.FS // embed extra surface specs as needed; never embed *

	var activefs fs.FS = efs

	type osfs struct {
		*os.Root
	}

	// SetLivePath serves docs from dir instead of the embedded copies.
	// Wire to a --docs flag: edit the yaml, refresh the browser.
	// Also the way to override built-in docs in a deployment.
	func SetLivePath(dir string) error {
		root, err := os.OpenRoot(dir)
		if err != nil {
			return err
		}

		activefs = osfs{root}

		return nil
	}

	// AddHandlers mounts docs on r serving the given spec file.
	// Each listener mounts its own surface: public "openapi.yaml", system "system.yaml", ...
	func AddHandlers(ctx context.Context, r *mux.Router, spec string) {
		handle(ctx, r, "/{$}", "index.html")
		handle(ctx, r, ".", "index.html")
		handle(ctx, r, "/openapi.yaml", spec)
	}

	func handle(ctx context.Context, r *mux.Router, from, to string) {
		tr := tlog.SpanFromContext(ctx)

		r.Handle("GET "+from, func(c *mux.Context, w http.ResponseWriter, req *http.Request) error {
			tr.Printw("docs", "url_path", req.URL.Path, "doc_path", to)
			http.ServeFileFS(w, req, activefs, to)

			return nil
		})
	}

	func (fs osfs) Open(name string) (fs.File, error) {
		return fs.Root.Open(name)
	}

`index.html` is likewise copied verbatim — minimal Scalar page, CDN script, no build
step. The config that matters: `url: 'openapi.yaml'`, `baseServerURL` from the page URL
(`new URL('../../', ...)`), `agent: {disabled: true}`, `hideClientButton: true`,
`operationTitleSource: 'path'`, `orderSchemaPropertiesBy: 'preserve'`,
`persistAuth: true`, `telemetry: false`. (Older projects also carry a `rapidoc.html`
fallback page; don't add it to new ones.)

## Updating a stale spec

Spec work usually starts from drift, so start from the routes, not the spec: enumerate
the real `Handle("METHOD /path")` registrations (mind group prefixes and which router —
that decides the surface), diff against each spec's `paths:`, then document the
missing endpoints from their handlers as above.
