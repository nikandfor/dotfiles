# dotfiles

Collection of dotfiles + managing script. Collections:
* base - shell, git, terminal, ...
* ai   - AGENTS.md, rules, ...

Script adds/removes one or more collection to $HOME.
Collection is a git branch under the hood, which is checked out treating home directory as a worktree.
No other files are affected.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/nikandfor/dotfiles/main/dotgit.sh | sh -s install
# or
git clone https://github.com/nikandfor/dotfiles ~/.config/dotfiles

# getting started
~/.config/dotfiles/dotgit.sh --help
```

## Use

```sh
dotgit --help

dotgit install                      # clone repo if not yet; link dotgit command to ~/.local/bin
dotgit fetch                        # fetch updates from remote repo

dotgit [status]                     # available collections and their status
dotgit add ai                       # checkout and attach collection
dotgit detach ai                    # detach collection: stop tracking files; but keep them

dotgit ai status                    # any git command, aimed at one branch
dotgit ai commit -am 'update rules'
dotgit ai push

dotgit base fetch                   # one fetch serves all branches
dotgit base pull                    # apply updates to ~ (ff-only)
dotgit base checkout -- .bashrc     # discard a local change
dotgit base reset --hard 'home/base@{1}'  # roll back, e.g. after a bad pull
```
