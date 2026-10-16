#!/usr/bin/env bash
# Tests install against a sandboxed HOME and stand-ins for every component, so running these never
# touches the real repos or anything they install. Each stand-in's install.sh only records that it
# ran, in the order the components were installed. install runs from a copy with stand-in
# component directories beside it, so the repo's own components are never installed from here.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT

pass=0; fail=0

check() {
  if [ "$2" = "$3" ]; then printf '  PASS %s\n' "$1"; pass=$((pass+1))
  else printf '  FAIL %s\n       got:  %s\n       want: %s\n' "$1" "$2" "$3"; fail=$((fail+1)); fi
}

git_quiet() { git -c user.email=test@test -c user.name=Test -c commit.gpgsign=false "$@" >/dev/null 2>&1; }

# An install.sh in <dir> that appends <name> to $INSTALL_LOG.
stand_in() {
  mkdir -p "$1"
  printf '#!/usr/bin/env bash\necho %s >> "$INSTALL_LOG"\n' "$2" > "$1/install.sh"
  chmod +x "$1/install.sh"
}

# A bare remote for git-tools, holding one commit with a stand-in install.sh.
make_remote() {
  local remotes work
  remotes="$(mktemp -d "$ROOT/remotes.XXXXXX")"
  work="$(mktemp -d "$ROOT/work.XXXXXX")"
  git_quiet init -q -b main "$work"
  stand_in "$work" git-tools
  git_quiet -C "$work" add install.sh
  git_quiet -C "$work" commit -q -m init
  git_quiet clone -q --bare "$work" "$remotes/git-tools"
  printf '%s' "$remotes"
}

# One sandbox per case: a HOME, a code directory, a log, and the share and managed directories
# pointed somewhere that does not exist unless a case creates them. micro and yazi have
# installers; herdr has none, unless a case adds one.
new_sandbox() {
  box="$(mktemp -d "$ROOT/box.XXXXXX")"
  mkdir "$box/dotfiles"
  cp "$repo_root/install" "$box/dotfiles/install"
  installer="$box/dotfiles/install"
  stand_in "$box/dotfiles/micro" micro
  stand_in "$box/dotfiles/yazi" yazi
  remotes="$(make_remote)"
  mkdir -p "$box/home"
  : > "$box/log"
}

run_install() {
  HOME="$box/home" INSTALL_LOG="$box/log" \
    DOTFILES_CODE_DIR="$box/code" DOTFILES_REMOTE_BASE="$remotes" \
    DOTFILES_SHARE_DIR="$box/share" DOTFILES_MANAGED_DIR="$box/managed" \
    "$installer" "$@" 2>&1
}

installed() { tr '\n' ' ' < "$box/log" | sed 's/ $//'; }

echo "=== fresh machine: clones git-tools, then runs every installer in order ==="
new_sandbox
out="$(run_install)"; status=$?
check "exits 0" "$status" "0"
check "git-tools, then the local components" "$(installed)" "git-tools micro yazi"
check "git-tools is cloned into the code directory" "$(test -d "$box/code/git-tools/.git" && echo yes)" "yes"
check "a component without an installer is skipped, and says why" \
  "$(echo "$out" | grep -c 'herdr/install.sh does not exist yet')" "1"

echo "=== second run: pulls instead of cloning ==="
upstream="$(mktemp -d "$ROOT/upstream.XXXXXX")"
git_quiet clone -q "$remotes/git-tools" "$upstream"
echo change > "$upstream/new-file"
git_quiet -C "$upstream" add new-file
git_quiet -C "$upstream" commit -q -m change
git_quiet -C "$upstream" push -q origin main
: > "$box/log"
out="$(run_install)"; status=$?
check "exits 0" "$status" "0"
check "the new upstream commit is pulled" "$(test -f "$box/code/git-tools/new-file" && echo yes)" "yes"
check "every installer runs again" "$(installed)" "git-tools micro yazi"

echo "=== --only installs just the named component ==="
new_sandbox
out="$(run_install --only yazi)"; status=$?
check "exits 0" "$status" "0"
check "only yazi runs" "$(installed)" "yazi"
check "git-tools is not cloned" "$(test -e "$box/code/git-tools" && echo present || echo absent)" "absent"

echo "=== --only keeps the install order, whatever order it is given in ==="
new_sandbox
run_install --only yazi --only git-tools >/dev/null
check "git-tools still goes first" "$(installed)" "git-tools yazi"

echo "=== an unknown component is refused before anything runs ==="
new_sandbox
out="$(run_install --only nope)"; status=$?
check "exits 2" "$status" "2"
check "names the component" "$(echo "$out" | grep -c 'Unknown component: nope')" "1"
check "nothing installed" "$(installed)" ""

echo "=== a dirty repo stops the run, and nothing after it is installed ==="
new_sandbox
run_install >/dev/null
echo wip > "$box/code/git-tools/wip"
: > "$box/log"
out="$(run_install)"; status=$?
check "exits 1" "$status" "1"
check "names the repo" "$(echo "$out" | grep -c 'Stopped at git-tools')" "1"
check "nothing installed" "$(installed)" ""
check "the change is left in place" "$(cat "$box/code/git-tools/wip")" "wip"

echo "=== local commits stop the run ==="
new_sandbox
run_install >/dev/null
echo local > "$box/code/git-tools/local"
git_quiet -C "$box/code/git-tools" add local
git_quiet -C "$box/code/git-tools" commit -q -m local
: > "$box/log"
out="$(run_install)"; status=$?
check "exits 1" "$status" "1"
check "says why" "$(echo "$out" | grep -c 'commits that are not on its remote')" "1"
check "nothing installed" "$(installed)" ""

echo "=== a failing installer stops the run ==="
new_sandbox
run_install --only git-tools >/dev/null
printf '#!/usr/bin/env bash\nexit 3\n' > "$box/code/git-tools/install.sh"
git_quiet -C "$box/code/git-tools" update-index --assume-unchanged install.sh
: > "$box/log"
out="$(run_install)"; status=$?
check "exits 1" "$status" "1"
check "names the installer" "$(echo "$out" | grep -c 'git-tools: its installer failed')" "1"
check "nothing after it is installed" "$(installed)" ""

echo "=== a local component with an installer is run ==="
new_sandbox
stand_in "$box/dotfiles/herdr" herdr
run_install >/dev/null
check "herdr runs last" "$(installed)" "git-tools micro yazi herdr"

echo "=== a devspaces pod is refused before anything runs ==="
new_sandbox
mkdir -p "$box/share" "$box/managed" "$box/bin"
printf '#!/bin/sh\n' > "$box/bin/devspaces"
chmod +x "$box/bin/devspaces"
out="$(PATH="$box/bin:$PATH" run_install)"; status=$?
check "exits 1" "$status" "1"
check "points to /wire-up" "$(echo "$out" | grep -c '/wire-up')" "1"
check "nothing cloned" "$(test -e "$box/code" && echo present || echo absent)" "absent"
check "nothing installed" "$(installed)" ""

echo "=== only some pod signals: still an owned machine ==="
new_sandbox
mkdir -p "$box/share"
out="$(run_install)"; status=$?
check "exits 0" "$status" "0"
check "installs as usual" "$(installed)" "git-tools micro yazi"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
