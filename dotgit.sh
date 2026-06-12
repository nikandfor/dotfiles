#!/bin/sh

# Manages dotfiles collections - git branches checked out into $HOME as worktrees.
#
#	dotgit install [-d dir] [-u url] [-b branch] [-l bin] [-n]
#	                                            clone repo if missing, link dotgit into bin
#	dotgit [status]                             available collections and their state
#	dotgit main [args]                          run commands in main worktree
#	dotgit add <collection>                     attach collection: check out into $HOME
#	dotgit detach <collection>                  detach collection, files in $HOME are kept
#	dotgit <collection> <git args ...>          git aimed at one collection: dotgit home/base status

repo="${DOTFILES:-$HOME/.config/dotfiles}"
url="${url:-https://github.com/nikandfor/dotfiles}"
remote="${remote:-origin}"

usage() {
	sed -n '3,11p' "$0"
}

precheck() {
	test -e "$repo/.git" || { echo "no repo at $repo"; return 1; }
}

verifyref() {
	rootgit rev-parse -q --verify "refs/$1" >/dev/null
}

rootgit() {
	git -C "$repo" "$@"
}

# worktree dir for a collection; flat name, git scans only one level
# under worktrees/ and commondir is relative
wtdir() {
	echo "$repo/.git/worktrees/$(echo "$1" | tr / -)"
}

dotgit() {
	local br="$1"
	local gitdir="$(wtdir "$1")"
	shift

	if test -e "$gitdir"; then
		: # we are fine
	elif verifyref "heads/$br"; then
		echo "collection is not attached. to attach run:"
		echo "  $0 add $br"
		return 1
	else
		echo "unknown collection. maybe to fetch updates:"
		echo "  $0 main fetch"
		return 1
	fi

	git --git-dir="$gitdir" --work-tree="$HOME" "$@"
}

install() {
	local loc rem branch binpath noinstall

	loc=
	rem="$url"
	branch=main
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

	if test -e "$loc/.git"; then
		git -C "$loc" fetch "$rem" "$branch" &&
		git -C "$loc" checkout -q -f -B "$branch" FETCH_HEAD &&
		git -C "$loc" clean -qfd
	else
		git clone "$rem" "$loc" -b "$branch"
	fi || return 1

	git -C "$loc" config status.showUntrackedFiles no

	test -n "$noinstall" || {
		mkdir -p "$binpath" &&
		ln -sf "$loc/dotgit.sh" "$binpath"/dotgit
	}
}

status() {
	precheck || return 1

	local br wt att st sync n

	for br in $({
		rootgit for-each-ref --format='%(refname:lstrip=2)' refs/heads
		rootgit for-each-ref --format='%(refname:lstrip=3)' refs/remotes
	} | grep / | sort -u); do
		wt="$(wtdir "$br")"
		att=-
		st=

		if ! verifyref "heads/$br"; then
			printf '%-14s %-11s %s\n' "$br" "$att" "remote only"
			continue
		fi

		if test -e "$wt/HEAD"; then
			att=attached
			n=$(git --git-dir="$wt" --work-tree="$HOME" status --porcelain -uno | wc -l)
			if test "$n" = 0; then st=; else st="{$n}"; fi
		fi

		sync="no remote"
		if verifyref "remotes/$remote/$br"; then
			sync=$(rootgit rev-list --count --left-right "$br...$remote/$br" |
				xargs sh -c 'test "$1" = 0 || a=" (+$1 ahead)"
					test "$2" = 0 && echo "up to date$a" || echo "new version available$a"' sync)
		fi

		printf '%-14s %-11s %s\n' "$br$st" "$att" "$sync"
	done
}

addone() {
	case "$1" in
	*/*) ;;
	*) echo "collection is a branch of the form group/name: $1"; return 1 ;;
	esac

	wt="$(wtdir "$1")"

	rootgit branch -q --track "$1" "$remote/$1" 2>/dev/null ||
		rootgit branch -q "$1" --set-upstream-to "$remote/$1" 2>/dev/null ||
		{ echo "unknown collection: $1"; return 1; }

	mkdir -p "$wt"

	echo "ref: refs/heads/$1" > "$wt/HEAD"
	echo "../.." > "$wt/commondir"
	echo "$HOME/.git" > "$wt/gitdir" # fake backpointer, makes `git worktree list` and branch protection work
	echo "work tree is $HOME, managed by dotgit" > "$wt/locked"

	dotgit "$1" reset -q &&
	dotgit "$1" pull --ff-only ||
	return 1
}

add() {
	precheck || return 1

	local col

	for col in "$@"; do
		addone "$col" || return 1
	done
}

detach() {
	precheck || return 1

	rm -rf "$(wtdir "$1")"
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
	main)
		rootgit "$@"
		;;
	*)
		dotgit "$cmd" "$@"
		;;
	esac
}

main "$@"
