# Sandboxing — default-on for every project

Every project runs its untrusted toolchain inside an OS sandbox by default. Dev servers, bundlers, build steps, test runners, codegen — anything that executes third-party code (npm/jsr/go modules, esbuild, a compiler plugin) is contained by `scripts/box.sh`, not run bare.

**Box belongs in the harness, invoked manually only for one-offs.** The durable home of the box is the entrypoints: new-project setup drops in the script and routes the run/dev/build/test commands (deno tasks, Makefile targets, scripts) through it once. After that you call the task (`deno task dev`), not the box — it is already wrapped. **Don't box what's already boxed** — no `box.sh deno task …` when the task itself calls box; that nests a box in a box for nothing. Reach for `scripts/box.sh <cmd>` by hand only for a **one-time untrusted action that isn't wired into any script** — an ad-hoc `deno check` on a fresh dep, a throwaway codegen run. If you find yourself manually boxing the same command repeatedly, that's the signal to wire it into the harness instead.

**Exception:** a project with **no third-party dependencies** — no external libraries and no external tools beyond the language toolchain itself — needs no box; there's nothing untrusted to contain, so run it bare. Your own code reused as a dependency does not count as third-party.

`bubblewrap` (`bwrap`) confines the command **and all its children** to an explicit filesystem view: only the repo, the toolchain (read-only), and a throwaway `/tmp`. Network is shared so a dev server stays reachable; the boundary is the filesystem — no `~/.ssh`, no dotfiles, no sibling repos, no writes outside the workspace. The command runs fully trusted (`-A`, no flags) inside the box; the bind list is the explicit statement of what it can touch.

## Skeleton — `scripts/box.sh`, `chmod +x`

`./scripts/box.sh <cmd…>` runs any command confined to the workspace. Per-language caches live in a gitignored `$root/.cache/*`.

```sh
#!/bin/sh
# Run a command filesystem-confined to this project via bubblewrap: it sees only this
# repo, the toolchain (ro), and a throwaway /tmp. Network is shared; the boundary is the
# filesystem. The wrapped command runs fully trusted (-A) inside the box.
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
mkdir -p "$root/.cache/deno"

exec bwrap \
	--ro-bind /usr /usr \
	--symlink usr/bin /bin --symlink usr/lib /lib --symlink usr/lib64 /lib64 --symlink usr/sbin /sbin \
	--ro-bind /etc /etc \
	--ro-bind-try /run/systemd/resolve /run/systemd/resolve \
	--proc /proc --dev /dev --tmpfs /tmp \
	--bind "$root" "$root" \
	--unshare-pid --unshare-ipc --unshare-uts \
	--die-with-parent \
	--chdir "$PWD" \
	--ro-bind "$HOME/.deno" "$HOME/.deno" \
	--setenv DENO_DIR "$root/.cache/deno" \
	--setenv PATH "$HOME/.deno/bin:/usr/bin" \
	-- "$@"
```

Wire it: route entrypoints through the script — `./scripts/box.sh deno run -A --watch scripts/dev.ts`, `./scripts/box.sh go test ./...`. (A task runner invoking it from a subdir uses the matching relative path, e.g. `../scripts/box.sh`.) Caches go under `$root/.cache/*`, which is in the global gitignore — no per-project entry needed.

## Toolchain block (the last lines — swap per project)

- **Deno** (shown): bind `~/.deno` ro; `DENO_DIR=$root/.cache/deno`.
- **Node:** bind the node `bin` dir ro; `npm_config_cache=$root/.cache/npm`; add it to `PATH`.
- **Go — exception:** bind the **shared global** `GOPATH` and `GOCACHE` (the module dir is too large to copy per project), plus `GOROOT` ro:
  ```sh
  --ro-bind "$(go env GOROOT)" "$(go env GOROOT)" \
  --bind "$(go env GOPATH)" "$(go env GOPATH)" \
  --bind "$(go env GOCACHE)" "$(go env GOCACHE)" \
  --setenv PATH "$(go env GOROOT)/bin:$(go env GOPATH)/bin:/usr/bin" \
  ```

## Notes

- Prereqs: `bwrap` installed and unprivileged user namespaces enabled (`cat /proc/sys/user/max_user_namespaces` > 0). Check once per host.
- usr-merge assumed (`/bin`,`/lib`→`usr/*`). On a split-`/usr` host, `--ro-bind` those dirs instead of `--symlink`.
- `--chdir "$PWD"` preserves the caller's working directory so relative entrypoints resolve when a task runner invokes the script from a subdir.
- First run with project-local caches re-downloads deps once; warm runs are normal speed.
- Verify confinement once: `./scripts/box.sh sh -c 'ls -a ~; ls ~/.ssh 2>&1'` — home shows only the repo path + toolchain dir; `~/.ssh` is absent.
- Stop: `pkill -x bwrap` / `pkill -x <runtime>` (plain `pkill -f` also matches the launching shell).
