#!/bin/sh

# Manages dotfiles collections - git branches checked out into $HOME as worktrees.
#
#	dotgit install [-d dir] [-u url] [-b branch] [-l bin] [-n]
#	                                            clone repo if missing, link dotgit into bin
#	dotgit [status]                             available collections and their state
#	dotgit fetch [args]                         fetch updates from the remote
#	dotgit add <collection>                     attach collection: check out into $HOME
#	dotgit detach <collection>                  detach collection, files in $HOME are kept
#	dotgit <collection> <git args ...>          git aimed at one collection: dotgit base status

repo="${DOTFILES:-$HOME/.config/dotfiles}"
url="${url:-https://github.com/nikandfor/dotfiles}"

usage() {
	sed -n '3,11p' "$0"
}

precheck() {
	test -e "$repo/.git" || { echo "no repo at $repo"; return 1; }
}

fetch() {
	git --git-dir="$repo/.git" fetch "$@"
}

dotgit() {
	local br="$1"
	shift

	git --git-dir="$repo/.git/worktrees/$br" --work-tree="$HOME" "$@"
}

install() {
	local loc rem branch binpath noinstall

	loc=
	rem="$url"
	branch=readme
	binpath=~/.local/bin
	noinstall=

	while test "$#" != 0; do
		case "$1" in
		-d) loc="$2"; shift ;;
		-u) rem="$2"; shift ;;
		-b) branch="$2"; shift ;;
		-l) binpath="$2"; shift ;;
		-n) noinstall=1 ;;
		*) echo "install: unexpected argument: $1"; return 1 ;;
		esac

		shift
	done

	test -z "$loc" &&
		loc="$repo" ||
		{
			mkdir -p "$(dirname "$loc")" &&
			loc=$(realpath "$loc")
		} ||
		return 1

	test -e "$loc/.git" ||
		git clone "$rem" "$loc" -b "$branch" || return 1

	test -n "$noinstall" || {
		mkdir -p "$binpath" &&
		ln -sf "$loc/dotgit.sh" "$binpath"/dotgit
	}
}

status() {
	precheck || return 1

	local br wt att st sync n

	for br in $({
		git --git-dir="$repo/.git" for-each-ref --format='%(refname:lstrip=2)' refs/heads/home/*
		git --git-dir="$repo/.git" for-each-ref --format='%(refname:lstrip=3)' refs/remotes/*/home/*
	} | sort -u); do
		if ! git --git-dir="$repo/.git" rev-parse -q --verify "refs/heads/$br" >/dev/null; then
			printf '%-14s %-11s %s\n' "$br" "" "remote only"
			continue
		fi

		wt="$repo/.git/worktrees/${br#home/}"

		att=-
		st=
		if test -e "$wt/HEAD"; then
			att=attached
			n=$(git --git-dir="$wt" --work-tree="$HOME" status --porcelain -uno | wc -l)
			if test "$n" = 0; then st=; else st="{$n}"; fi
		fi

		sync="no remote"
		if git --git-dir="$repo/.git" rev-parse -q --verify "refs/remotes/origin/$br" >/dev/null; then
			sync=$(git --git-dir="$repo/.git" rev-list --count --left-right "$br...origin/$br" |
				xargs sh -c 'test "$1" = 0 || a=" ($1 ahead)"
					test "$2" = 0 && echo "up to date$a" || echo "new version available$a"' sync)
		fi

		printf '%-14s %-11s %s\n' "$br$st" "$att" "$sync"
	done
}

add() {
	precheck || return 1

	wt="$repo/.git/worktrees/$1"

	git -C "$repo" rev-parse -q --verify "refs/heads/home/$1" >/dev/null ||
		git -C "$repo" branch --track "home/$1" "origin/home/$1" || return 1

	mkdir -p "$wt"

	echo "ref: refs/heads/home/$1" > "$wt/HEAD"
	echo "../.." > "$wt/commondir"
	echo "$HOME/.git" > "$wt/gitdir" # fake backpointer, makes `git worktree list` and branch protection work
	echo "work tree is $HOME, managed by dotgit" > "$wt/locked"

	dotgit "$1" reset -q || return 1
}

detach() {
	precheck || return 1

	rm -rf "$repo/.git/worktrees/$1"
}

main() {
	cmd="$1"
	test "$#" = 0 || shift

	case "$cmd" in
	""|status)
		status
		;;
	-h|--help)
		usage "$@"
		;;
	add)
		add "$@"
		;;
	detach)
		detach "$@"
		;;
	install)
		install "$@"
		;;
	fetch)
		fetch "$@"
		;;
	*)
		dotgit "$cmd" "$@"
		;;
	esac
}

main "$@"
