#!/bin/bash
# Rebuilds the public tree from scratch.
#
#   Scripts/make-release-tree.sh [destination]
#
# The public repo is a NEW history, not this one: the commits in here carry the
# spec, the handoffs and a running commentary written for one person, and one
# such commit is enough to make a whole history unpublishable. So the release is
# a fresh `git init` holding only the files this repo TRACKS, minus the ones the
# public .gitignore names.
#
# It is a script and not a manual copy for one reason: a tree assembled by hand
# stops matching its source the moment anything changes, and nobody notices.
# Run it twice and the second run must produce the same file list.
#
# It ends with the gates rather than with a promise: the identity sweep over the
# files and over the log, a release build, the tests, the benches. Any of them
# failing stops the script, so a tree that fails is never left looking finished.
#
# It adds no remote and pushes nothing. Publishing is a person's decision.

set -uo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD"

DESTINATION="${1:-$(cd .. && pwd)/Limbo-release}"
NAME="xmasyx"
EMAIL="16624475+xmasyx@users.noreply.github.com"
SUBJECT="Limbo — what you are moving, while you move it"

say() { printf '%s\n' "$*"; }
die() { printf 'STOPPED: %s\n' "$*" >&2; exit 1; }

# Everything the sweep must not find, in the tracked files OR in the log. It
# lives in a gitignored FILE and not inline here, because the list IS the
# private material: a script carrying it would publish what it looks for.
# Missing, this stops — building a public tree with no sweep at all is the one
# outcome worth refusing outright.
PATTERN_FILE="$SOURCE/Scripts/release/identity.pattern"
[ -s "$PATTERN_FILE" ] || die "no identity pattern at $PATTERN_FILE; refusing to publish unswept"
PATTERN="$(head -1 "$PATTERN_FILE")"

# The one sanctioned home path: the placeholder the benches use. It is
# neutralised before the grep instead of being carved out of the pattern, so
# the home-directory prefix stays as broad as it was and any OTHER name under
# it still trips.
SANCTIONED='/Users/esempio'

case "$DESTINATION" in
  "$SOURCE"|"$SOURCE"/*) die "the destination is inside the source: $DESTINATION" ;;
  /|"$HOME") die "refusing to treat $DESTINATION as a build directory" ;;
esac

command -v git >/dev/null || die "no git"
command -v swift >/dev/null || die "no swift"
[ -d "$SOURCE/.git" ] || die "$SOURCE is not a git repository"

# A public tree has to correspond to a commit: rsync copies the WORKING TREE of
# the tracked paths, so building from a dirty repo publishes something that
# matches nothing in the history.
DIRTY="$(git -C "$SOURCE" status --porcelain)"
if [ -n "$DIRTY" ] && [ "${LIMBO_ALLOW_DIRTY:-0}" != "1" ]; then
  printf '%s\n' "$DIRTY"
  die "the source tree is dirty; commit first, or set LIMBO_ALLOW_DIRTY=1"
fi

say "==> source      $SOURCE at $(git -C "$SOURCE" rev-parse --short HEAD)"
say "==> destination $DESTINATION"

# From zero. A destination emptied instead of deleted keeps whatever the last
# run left behind.
if [ -e "$DESTINATION" ]; then
  [ -d "$DESTINATION/.git" ] || [ -z "$(ls -A "$DESTINATION" 2>/dev/null)" ] \
    || die "$DESTINATION exists and is not a git tree; not deleting it"
  rm -rf "$DESTINATION"
fi
mkdir -p "$DESTINATION"

# Only what the source TRACKS, minus what the public .gitignore names. Using
# `git ls-files` and not a copy of the directory means anything ignored here —
# the bench output, the signing pattern — cannot arrive by being on the disk.
PRIVATE='^(ISA\.md|ISA\.html|RIPRESA\.md)$'
git -C "$SOURCE" ls-files | grep -Ev "$PRIVATE" | tr '\n' '\0' > /tmp/limbo-release-files.z
COUNT="$(git -C "$SOURCE" ls-files | grep -Evc "$PRIVATE")"
say "==> copying $COUNT tracked files"
( cd "$SOURCE" && rsync -a --files-from=- --from0 . "$DESTINATION" < /tmp/limbo-release-files.z ) \
  || die "the copy failed"

cp "$SOURCE/Scripts/release/gitignore.public" "$DESTINATION/.gitignore"

cd "$DESTINATION" || die "cannot enter $DESTINATION"
git init -q
# LOCAL, never inherited: the global identity on this machine is a real name.
git config user.name "$NAME"
git config user.email "$EMAIL"
git add -A
git -c commit.gpgsign=false commit -q -m "$SUBJECT" || die "the commit failed"

say ""
say "=== the gates, on the tree that was just built ======================"

say "--> the sweep bites"
# A gate that has never said no has never measured anything. The probe word is
# taken FROM the pattern instead of being written here, so this script does not
# carry the thing it is looking for.
PROBE="$(printf '%s' "$PATTERN" | cut -d'|' -f1)"
printf 'prova %s prova\n' "$PROBE" | grep -qE "$PATTERN" \
  || die "the sweep does not recognise its own first pattern"
say "    it does"

say "--> the identity sweep, over the files"
# The hits are COLLECTED and then judged. Reading the verdict off the exit
# status of `... | while ...; done | grep .` is wrong under `pipefail`: the
# while loop ends non-zero on the last file with no match, and that status wins
# over grep's zero — the gate prints what it found and then says clean.
HITS="$(git ls-files -z | while IFS= read -r -d "" f; do
     sed "s#$SANCTIONED#<HOME>#g" "$f" 2>/dev/null | grep -InE "$PATTERN" | sed "s#^#$f:#"
   done)"
if [ -n "$HITS" ]; then
  printf '%s\n' "$HITS"
  die "the sweep found something in the tracked files"
fi
say "    clean ($(git ls-files | wc -l | tr -d ' ') files)"

say "--> the identity sweep, over the log"
LOG_HITS="$(git log --format='%an <%ae> %s%n%b' | grep -InE "$PATTERN")"
if [ -n "$LOG_HITS" ]; then
  printf '%s\n' "$LOG_HITS"
  die "the sweep found something in the history"
fi
say "    clean ($(git log --oneline | wc -l | tr -d ' ') commit, $(git log -1 --format='%an <%ae>'))"

say "--> swift build -c release"
swift build -c release --product Limbo > /tmp/limbo-release-build.log 2>&1 || {
  tail -20 /tmp/limbo-release-build.log; die "the release build failed"; }
say "    built"

say "--> swift test"
swift test > /tmp/limbo-release-test.log 2>&1 || {
  tail -20 /tmp/limbo-release-test.log; die "the tests failed"; }
say "    $(grep -oE 'Test run with [0-9]+ tests[^.]*' /tmp/limbo-release-test.log | tail -1)"

say "--> the benches the build script runs"
for banco in stringhe geometria movimento deposito chat grazia nuove aggiornamenti; do
  ./.build/release/Limbo "--selftest-$banco" > /tmp/limbo-release-banco.log 2>&1 \
    || { tail -20 /tmp/limbo-release-banco.log; die "bench $banco failed"; }
done
say "    eight benches green"

say "--> the build left nothing behind"
DIRT="$(git status --porcelain)"
[ -z "$DIRT" ] || { printf '%s\n' "$DIRT"; die "the tree is dirty after building"; }
say "    git status is empty"

say ""
say "the tree is at $DESTINATION — no remote, nothing pushed."
