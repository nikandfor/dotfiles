# dotfiles

Collection of dotfiles + managing script. Collections:
* [home/base](tree/home/base) - shell, git, terminal, ...
* [home/ai](tree/home/ai)   - AGENTS.md, rules, ...

Script adds/removes one or more collection to `$HOME`.
Collection is a git branch of the form `group/name`, checked out with the home directory as its work tree.
No other files are affected.

## Collections
### home/base
My shell goodies. Nice shell prompt, git aliases, configs for htop, ghostty, ssh.

### home/ai
Knowledge base distilled from my public code prepared for agents.

* `AGENTS.md` is an entry point and core instructions and principles.
* `rules/` is for language/technology specific instructions.
* `env/` is for local not tracked instructions,
  such as where to store code,
  how to deal with local networking, etc.

All the common instructions live in `~/.ai/`,
symlinks or imports used to wire specific agents to that knowlege base.
```
~/.claude/CLAUDE.md  -symlink->  ~/.ai/CLAUDE.md
```

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/nikandfor/dotfiles/main/dotgit.sh | sh -s install
# or
git clone https://github.com/nikandfor/dotfiles ~/.config/dotfiles && ~/.config/dotfiles/dotgit.sh install

# install makes a link from ~/.local/bin/dotgit to ...dotfiles/dotgit.sh (whereever it is cloned to)

# start from help
dotgit --help
```

## Usage

```sh
dotgit install                      # clone repo if not yet; link dotgit command to ~/.local/bin
dotgit main fetch                   # fetch updates from remote repo

dotgit [status]                     # available collections and their status
dotgit add home/ai                  # attach collection and check it out
dotgit detach home/ai               # detach collection: stop tracking files; but keep them unchanged

dotgit home/ai status               # any git command, aimed at one branch
dotgit home/ai commit -am 'update rules'
dotgit home/ai push

dotgit home/base fetch              # one fetch serves all branches
dotgit home/base pull               # apply updates to ~ (ff-only)
dotgit home/base checkout -- .bashrc      # discard a local change
dotgit home/base reset --hard 'home/base@{1}'  # roll back, e.g. after a bad pull
```
