# dotfiles

Configs in independent `home/*` branches, all checked out directly into `~`
from a single clone: `home/base` (shell, git, editor, terminal) and
`home/ai` (ai agent rules). One tool, `dotgit`, manages everything and
takes simple names: `base`, `ai`.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/nikandfor/dotfiles/readme/dotgit | sh -s add base ai
```

Existing files in `~` are kept and show as modifications to review;
`add -f` overwrites them with branch content. `.bashrc` of `base` aliases
`dotgit` to `~/.config/dotfiles/dotgit` (set `DOTFILES` for another location).

## Use

```sh
dotgit                              # attached worktrees, clean or dirty
dotgit add                          # list available branches
dotgit add ai / dotgit rm ai        # attach, detach

dotgit base status                  # any git command, aimed at one branch
dotgit ai commit -am 'update rules'
dotgit base push

dotgit base fetch                   # one fetch serves all branches
dotgit base pull                    # apply updates to ~ (ff-only)
dotgit base checkout -- .bashrc     # discard a local change
dotgit base reset --hard 'home/base@{1}'  # roll back, e.g. after a bad pull
```

The `.*` catch-all in `.gitignore` hides everything untracked, so adding a
new file takes `add -f`; modified tracked files work with `add -u` /
`commit -am` as usual.

## How it works

The clone at `~/.config/dotfiles` has this `readme` branch checked out.
Each `home/*` branch is attached as a hand-made linked worktree
(`.git/worktrees/<name>`: own `HEAD` and index, `commondir` pointing at the
shared repo) with `~` as the work tree — several branches checked out into
the same directory, sharing objects, refs, and remote. Branches must not
track overlapping paths.
