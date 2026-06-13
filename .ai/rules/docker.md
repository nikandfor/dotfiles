# Docker / Compose / GitHub workflows — Go services

These files travel together from project to project nearly unchanged. Copy them, swap the
project specifics (org, service name, the per-package COPY list, listen flags), and you're
done. The placeholders below are `<svc>` (service / binary / module-dir name), `<org>` (the
private GitHub org for `GOPRIVATE` and the registry), and `<name>` (the deployment's
`COMPOSE_PROJECT_NAME`).

## Doctrine

- **Multi-stage, static, tiny.** `golang:1.26` builder → scratch-thin `alpine:latest`
  final carrying just the binary. `CGO_ENABLED=0` so it's a static binary; no libc to
  match. The whole image is the binary plus alpine.
- **Explicit per-package COPY, never `COPY . .`** (*explicit over implicit*, AGENTS.md.)
  Two reasons. First, a wildcard copy drags in whatever happens to sit in the tree —
  logs, build artifacts, scratch files — and any of them changing triggers a needless
  rebuild; an explicit list copies only real source. Second, the list *is* the
  documentation: you can see exactly what goes into the image. `go.mod`/`go.sum` are just
  copied along with the source; there is no `go mod download` layer — dependency caching is
  the `--mount=type=cache` on the module cache (below), not a copy-manifests-first trick.
- **Private deps via mounted secret, never a baked layer.** `GOPRIVATE=github.com/<org>`
  plus git credentials supplied as a build `--mount=type=secret` (from
  `${HOME}/.git-credentials`). Credentials never land in an image layer. `GOWORK=off` so
  the repo's own `go.work` doesn't try to drag in sibling modules that aren't in the
  build context.
- **Cache mounts for the build.** `--mount=type=cache` on `/root/.cache/go-build` and
  `/go/pkg/mod` — rebuilds reuse compiled stdlib and downloaded modules across runs.
- **Version stamped via ldflags.** `Version`/`Commit`/`CommitDate`/`BuildDate` `main`
  vars set with `-ldflags -X`, fed by `ARG`s that compose and CI fill from git. Devel
  defaults so a bare `docker build` still works.
- **ENTRYPOINT is the binary, CMD is `run`.** `ENTRYPOINT ["/bin/<svc>"]` + `CMD ["run"]`.
  `docker run img` starts the server (the `run` subcommand, no flags);
  `docker run img <other-cmd>` runs any other subcommand without fighting the entrypoint.
  The binary with no args at all — CMD overridden empty — does some lightweight,
  dependency-free thing, so `run` is what actually brings the full server up.
- **One compose file is the whole stack** — the app plus its datastore — runnable on a
  laptop or a deploy host with the same command. Datastore tuning (logger level, users,
  TTLs, init SQL) lives inline in compose `configs:`; a named volume holds its data.
- **Everything overridable, sane defaults.** Container names namespaced by
  `${COMPOSE_PROJECT_NAME}` so projects coexist on one host; every published port is
  `${PORT:-default}`. No required env to bring it up.
- **Integration tests are a compose overlay**, not a separate harness: a second file adds
  a throwaway `tests` service (alpine + bash/curl/jq running the shell suite, see
  `rules/shell.md`) and bolts healthchecks + `depends_on: service_healthy` onto the app
  and datastore.
- **CI is test → image → deploy, registry in the middle.** Tests run on a hosted runner;
  a successful build pushes a tagged image to the registry; deploy pulls that image on the
  target host. Production runs the pushed image — it has no source checked out, so it never
  builds. The same integration overlay that gates locally gates the image build. No k8s,
  no matrix. (Staging can collapse all three onto a self-hosted runner that *is* the host —
  checkout, `compose build`, `up -d` — trading the registry round-trip for fastest
  iteration.)

## Dockerfile

	FROM golang:1.26 AS builder

	ENV GOPRIVATE=github.com/<org>
	ENV GOWORK=off
	ENV CGO_ENABLED=0

	WORKDIR /app

	COPY go.mod go.sum ./
	COPY *.go ./
	COPY cmd cmd
	COPY docs docs
	# one COPY per subpackage — explicit list, not `COPY . .`;
	# go.mod, *.go first, then the packages ordered alphabetically

	ARG VERSION=devel
	ARG COMMIT=unknown
	ARG COMMIT_DATE=unknown
	ARG BUILD_DATE=unknown

	RUN git config --global credential.helper store
	RUN \
		--mount=type=secret,target=/root/.git-credentials \
		--mount=type=cache,target=/root/.cache/go-build \
		--mount=type=cache,target=/go/pkg/mod \
		go build -ldflags="-X 'main.Version=$VERSION' -X 'main.Commit=$COMMIT' -X 'main.CommitDate=$COMMIT_DATE' -X 'main.BuildDate=$BUILD_DATE'" \
			-o app ./cmd/<svc>/

	FROM alpine:latest

	COPY --from=builder /app/app /bin/<svc>

	ENTRYPOINT ["/bin/<svc>"]
	CMD ["run"]

In a multi-module repo, set `WORKDIR /app/<svc>`. Code from the **same repo that lives in
a parent directory** can't be reached from the build context with `../` (the context root
is the floor), so expose it as a compose `build.additional_contexts:` entry
(`shared: ../shared`) and mount it into the build: `--mount=from=shared,target=/app/shared`.
That's same-repo code, not a third-party dependency — no credentials involved. Drop the
secret mount and the `git config` line entirely when there are no private deps to fetch
over the network.

## compose.yaml

Base stack: the service + its datastore. Host ports and image ref env-overridable;
build args feed the Dockerfile's version `ARG`s; the `command:` list is the flag set
(listen addresses, datastore URL, verbosity topics).

	services:
	  <svc>:
	    container_name: ${COMPOSE_PROJECT_NAME}-<svc>
	    image: ghcr.io/<org>/<svc>:${SVC_REF:-latest}
	    build:
	      context: .
	      args:
	        VERSION: ${VERSION:-dev}
	        COMMIT: ${COMMIT:-unknown}
	        COMMIT_DATE: ${COMMIT_DATE:-unknown}
	        BUILD_DATE: ${BUILD_DATE:-unknown}
	      secrets:
	        - .git-credentials
	    ports:
	      - "${SVC_PORT:-8080}:8080"
	      - "${SVC_DEBUG:-6060}:6060"
	    command:
	      - run
	      - --http=:8080
	      - --debug=:6060
	      - --db=${DB_URL:-clickhouse://click?insecure}
	      - -v=requests,db_query

	  click:
	    container_name: ${COMPOSE_PROJECT_NAME}-click
	    image: clickhouse/clickhouse-server:latest
	    ports:
	      - "${CLICK_PORT:-9000}:9000"
	    configs:
	      - source: click_config.xml
	        target: /etc/clickhouse-server/config.d/config.xml
	      - source: click_users.xml
	        target: /etc/clickhouse-server/users.d/users.xml
	    volumes:
	      - "click_data:/var/lib/clickhouse"
	    stop_grace_period: 1m
	    restart: unless-stopped

	configs:
	  click_config.xml:
	    content: |
	      <clickhouse>
	          <logger>
	              <level>error</level>
	              <console>0</console>
	          </logger>
	      </clickhouse>
	  click_users.xml:
	    content: |
	      <clickhouse>
	          <users>
	              <default>
	                  <password></password>
	                  <access_management>1</access_management>
	              </default>
	          </users>
	      </clickhouse>

	secrets:
	  .git-credentials:
	    file: ${HOME}/.git-credentials

	volumes:
	  click_data:

For non-service-specific initialization, inline a `click_init.sql` config targeted at
`/docker-entrypoint-initdb.d/`, sourced from a real file with `file:`. Truncate noisy
ClickHouse system-log TTLs in `click_config.xml`
(`text_log`/`trace_log`/`part_log`/`metric_log`) on long-lived deployments.

## compose/tests.yaml — integration overlay

A second file overlaid on the base (`docker compose -f compose.yaml -f compose/tests.yaml
up`). Adds a throwaway `tests` runner built inline, and the healthchecks the base doesn't
need but the test gate does. Each `command:` line is a script from the shell suite.

	services:
	  tests:
	    container_name: ${COMPOSE_PROJECT_NAME}-tests
	    build:
	      context: .
	      dockerfile_inline: |
	        FROM alpine:3.22

	        RUN apk add --no-cache bash curl jq

	        COPY scripts /scripts
	        WORKDIR /scripts

	        ENTRYPOINT ["/bin/bash"]
	    environment:
	      - api=http://${SVC_HOST:-<svc>}:8080
	      - debug=http://${SVC_HOST:-<svc>}:6060
	    command:
	      - ./run_all.sh
	      - ./prepare.sh
	      - ./tests/smoke.sh
	    depends_on:
	      <svc>:
	        condition: service_healthy
	      click:
	        condition: service_healthy

	  <svc>:
	    environment:
	      - SVC_INIT=true
	    depends_on:
	      click:
	        condition: service_healthy
	    healthcheck:
	      test: [CMD, wget, --quiet, --tries=1, --spider, http://127.0.0.1:8080/ping]
	      start_period: 5s

	  click:
	    healthcheck:
	      test: [CMD, clickhouse, client, --query, "SELECT 'ok'"]
	      start_period: 5s

## .github/workflows/ — CI

Three concerns, each its own workflow: **test** on every push/PR, **image** build-and-push
on merges/tags, **deploy** by hand. For a lightweight service the first two fold into one
job (test, then build+push). The integration overlay (`compose/tests.yaml`) is the gate in
both test and image. Private deps are fetched with a git-credentials file/secret written
from a deploy token; the registry is `ghcr.io/<org>`.

### test.yaml

	name: Test

	on:
	  pull_request:
	    branches: [main, dev]
	  push:
	    branches: [main, dev]

	jobs:
	  test:
	    runs-on: ubuntu-latest
	    env:
	      GOPRIVATE: github.com/<org>
	    steps:
	      - uses: actions/checkout@v6

	      - name: git credentials for private deps
	        run: |
	          git config --global credential.helper store
	          echo "https://x:${{ secrets.GH_DEPS_TOKEN }}@github.com" >~/.git-credentials && chmod 400 ~/.git-credentials

	      - uses: actions/setup-go@v6
	        with:
	          go-version: "1.26"
	          cache-dependency-path: go.sum

	      - run: go build -v ./...
	      - run: go test -v ./...
	      - run: go test -race -v ./...

	      - name: integration
	        run: ./scripts/run_all.sh ./scripts/prepare.sh ./scripts/tests/smoke.sh

### image.yaml

Build the image and the test image with `buildx bake` over the same compose files (one
source of truth for build args and contexts), run the integration overlay against the
freshly built image, then push multi-tagged. GHA layer cache across runs. The git
credential is injected as a buildx secret via an inline `!override` compose fragment, so
it never touches a layer; the test pass re-runs with it disabled.

	name: Image

	on:
	  push:
	    branches: [main, dev]
	    tags: ["*"]
	  workflow_dispatch:
	    inputs:
	      ref:
	        description: 'Git ref or commit (current by default)'
	        default: ''
	      latest:
	        description: 'Tag latest. Auto for main; `no` cancels, `yes` forces.'
	        default: ''
	      platforms:
	        default: 'linux/amd64'

	jobs:
	  build:
	    runs-on: ubuntu-latest
	    permissions:
	      contents: read
	      packages: write
	    steps:
	      - uses: actions/checkout@v6
	        with:
	          ref: ${{ inputs.ref || github.sha }}

	      - uses: docker/setup-qemu-action@v3
	      - uses: docker/setup-buildx-action@v3

	      - name: stamp build metadata
	        run: |
	          fmt='%a %b %d %H:%M:%S %z %Y'
	          echo COMMIT_DATE="$(git show -s --format=%cd --date=format:"$fmt" HEAD)" >>$GITHUB_ENV
	          echo BUILD_DATE="$(date +"$fmt")" >>$GITHUB_ENV

	      - name: build images
	        env:
	          GIT_CREDENTIALS: https://x:${{ secrets.GH_DEPS_TOKEN }}@github.com
	        run: |
	          docker compose pull click
	          docker buildx bake \
	            -f compose.yaml \
	            -f compose/tests.yaml \
	            -f <(echo 'secrets: { ".git-credentials": !override { environment: GIT_CREDENTIALS } }') \
	            --set '*.cache-from=type=gha' \
	            --set '*.cache-to=type=gha,mode=max' \
	            --load \
	              <svc> tests

	      - name: integration tests
	        env:
	          GIT_CREDENTIALS: none
	        run: |
	          docker compose \
	            -f compose.yaml \
	            -f compose/tests.yaml \
	            -f <(echo 'secrets: { ".git-credentials": !override { environment: GIT_CREDENTIALS } }') \
	            up --exit-code-from tests

	      - uses: docker/login-action@v3
	        with:
	          registry: ghcr.io
	          username: ${{ github.repository_owner }}
	          password: ${{ secrets.GITHUB_TOKEN }}

	      - name: build and push
	        uses: docker/build-push-action@v6
	        with:
	          context: .
	          build-args: |
	            VERSION=${{ github.ref_name }}
	            COMMIT=${{ github.sha }}
	            COMMIT_DATE=${{ env.COMMIT_DATE }}
	            BUILD_DATE=${{ env.BUILD_DATE }}
	          platforms: ${{ inputs.platforms || 'linux/amd64' }}
	          push: true
	          tags: |
	            ghcr.io/<org>/<svc>:${{ github.sha }}
	            ghcr.io/<org>/<svc>:${{ inputs.ref || github.ref_name }}
	            ${{ (inputs.latest == 'yes' || inputs.latest != 'no' && github.ref_name == 'main') && 'ghcr.io/<org>/<svc>:latest' || '' }}
	          cache-from: type=gha
	          cache-to: type=gha,mode=max
	          secrets: |
	            .git-credentials=https://x:${{ secrets.GH_DEPS_TOKEN }}@github.com

### deploy.yaml

Manual `workflow_dispatch`: SSH to the host and roll the new image. Production has no
source — it pulls the tag, never builds. Host/credentials default to secrets, overridable
per run.

	name: Deploy

	on:
	  workflow_dispatch:
	    inputs:
	      server:
	        description: Server hostname to deploy to
	        default: ''
	      directory:
	        description: Directory with deployment
	        default: /opt/<org>/deploy/<name>/

	jobs:
	  deploy:
	    runs-on: ubuntu-latest
	    steps:
	      - uses: actions/checkout@v6

	      - name: deploy over SSH
	        uses: appleboy/ssh-action@master
	        with:
	          host: ${{ inputs.server != '' && inputs.server || secrets.HOST }}
	          username: ${{ secrets.USERNAME }}
	          key: ${{ secrets.GIT_SSH }}
	          port: ${{ secrets.SSH_PORT }}
	          script: |
	            cd "${{ inputs.directory }}" &&
	            docker compose pull <svc> &&
	            docker compose up -d <svc>

### Staging shortcut

When iteration speed beats a registry, collapse all three onto a self-hosted runner that
*is* the staging host — checkout, build, up, in place:

	name: Staging

	on:
	  push:
	    branches: [main, deploy-<svc>]
	    paths: ['<svc>/**', '.github/workflows/staging.yaml']

	jobs:
	  deploy:
	    runs-on: [self-hosted, staging]
	    defaults:
	      run:
	        working-directory: ./<svc>/
	    env:
	      GOPRIVATE: github.com/<org>
	      COMPOSE_PROJECT_NAME: <name>
	    steps:
	      - uses: actions/checkout@v6
	      - run: docker compose build
	      - run: docker compose up -d

In a monorepo, keep the `working-directory` + `paths:` filter so a workflow only fires for
its own module; at repo root, drop both.
