# dotfiles

Collection of dotfiles + managing script. Collections:
* home/base - shell, git, terminal, ...
* home/ai   - AGENTS.md, rules, ...

Script adds/removes one or more collection to $HOME.
Collection is a git branch of the form group/name, checked out with the home directory as its work tree.
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
dotgit main fetch                   # fetch updates from remote repo

dotgit [status]                     # available collections and their status
dotgit add home/ai                  # checkout and attach collection
dotgit detach home/ai               # detach collection: stop tracking files; but keep them

dotgit home/ai status               # any git command, aimed at one branch
dotgit home/ai commit -am 'update rules'
dotgit home/ai push

dotgit home/base fetch              # one fetch serves all branches
dotgit home/base pull               # apply updates to ~ (ff-only)
dotgit home/base checkout -- .bashrc      # discard a local change
dotgit home/base reset --hard 'home/base@{1}'  # roll back, e.g. after a bad pull
```
