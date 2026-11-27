#!/bin/bash
# Works out the next release from the Conventional Commits since the last v* tag.
#
#   scripts/next-version.sh [notes-file]
#
# Prints KEY=value lines (for $GITHUB_OUTPUT):
#   last=0.7.0  bump=minor|patch|major|none  version=0.8.0 (empty when bump=none)
# and, with a notes file, writes the release notes there (commits grouped by type).
#
# Bumps (https://www.conventionalcommits.org):
#   major  "type!: …" or a "BREAKING CHANGE:" footer
#   minor  feat
#   patch  fix, perf, revert
#   none   docs, style, refactor, test, build, ci, chore (no release)
# Subjects that aren't Conventional Commits are reported as warnings and release nothing.
set -euo pipefail
cd "$(dirname "$0")/.."

NOTES="${1:-}"
LAST_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
LAST="${LAST_TAG#v}"
[[ -n "$LAST" ]] || LAST="0.0.0"
RANGE="${LAST_TAG:+$LAST_TAG..}HEAD"

TYPES='feat|fix|perf|revert|docs|style|refactor|test|build|ci|chore'
RE="^($TYPES)(\([^)]+\))?(!)?: .+"
rank=0 # 0 none, 1 patch, 2 minor, 3 major
features=() fixes=() breaking=()

while IFS= read -r -d $'\x1e' record; do
  record="${record#$'\n'}"
  [[ -n "$record" ]] || continue
  sha="${record%%$'\x1f'*}"; rest="${record#*$'\x1f'}"
  subject="${rest%%$'\x1f'*}"; body="${rest#*$'\x1f'}"
  if [[ ! "$subject" =~ $RE ]]; then
    case "$subject" in Merge\ *) ;; *) echo "::warning::Not a Conventional Commit, so it releases nothing: ${sha:0:7} $subject" >&2 ;; esac
    continue
  fi
  type="${BASH_REMATCH[1]}"; bang="${BASH_REMATCH[3]}"
  text="${subject#*: }"
  line="- $text (${sha:0:7})"
  if [[ -n "$bang" ]] || grep -qE '^BREAKING[ -]CHANGE: ' <<<"$body"; then
    rank=3; breaking+=("$line")
  fi
  case "$type" in
    feat) (( rank < 2 )) && rank=2; features+=("$line") ;;
    fix|perf|revert) (( rank < 1 )) && rank=1; fixes+=("$line") ;;
  esac
done < <(git log --reverse --format='%H%x1f%s%x1f%b%x1e' "$RANGE")

IFS=. read -r MAJOR MINOR PATCH <<<"$LAST"
case $rank in
  3) BUMP=major; VERSION="$((MAJOR + 1)).0.0" ;;
  2) BUMP=minor; VERSION="$MAJOR.$((MINOR + 1)).0" ;;
  1) BUMP=patch; VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  *) BUMP=none; VERSION="" ;;
esac

echo "last=$LAST"
echo "bump=$BUMP"
echo "version=$VERSION"

if [[ -n "$NOTES" ]]; then
  {
    if (( ${#breaking[@]} )); then echo "### Breaking changes"; printf '%s\n' "${breaking[@]}"; echo; fi
    if (( ${#features[@]} )); then echo "### Features"; printf '%s\n' "${features[@]}"; echo; fi
    if (( ${#fixes[@]} )); then echo "### Fixes"; printf '%s\n' "${fixes[@]}"; echo; fi
  } > "$NOTES"
fi
