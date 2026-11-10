#!/bin/sh
# release-notes.sh TAG: prints the release notes for TAG as Markdown.
# A pre-release lists the commits since the previous tag. A final release
# lists everything since the previous final release. Commits that only touch
# tests, CI or contributor docs go in a collapsed section.
set -eu
tag=$1

case $tag in
*-*) prev=$(git describe --tags --abbrev=0 "$tag^" 2>/dev/null || true) ;;
*) prev=$(git describe --tags --abbrev=0 --exclude='*-*' "$tag^" 2>/dev/null || true) ;;
esac
range=${prev:+$prev..}$tag

list=$(mktemp)
trap 'rm -f "$list"' EXIT
git log --reverse --format='%H %s' "$range" | while read -r sha subject; do
	if git diff-tree --no-commit-id --name-only -r "$sha" |
		grep -qvE '^(test/|\.github/|CONTRIBUTING\.md$)'; then
		case $subject in
		Add*) kind=added ;;
		Fix*) kind=fixed ;;
		*) kind=changed ;;
		esac
	else
		kind=maintenance
	fi
	printf '%s\t- %s (%s)\n' "$kind" "$subject" "$(printf %s "$sha" | cut -c1-7)"
done > "$list"

section() {
	grep "^$1	" "$list" | cut -f2- || true
}

for kind in added fixed changed; do
	items=$(section "$kind")
	[ -n "$items" ] || continue
	case $kind in
	added) echo "### Added" ;;
	fixed) echo "### Fixed" ;;
	changed) echo "### Changed" ;;
	esac
	echo
	printf '%s\n\n' "$items"
done

items=$(section maintenance)
if [ -n "$items" ]; then
	echo "<details><summary>Tests, CI and contributor docs</summary>"
	echo
	printf '%s\n' "$items"
	echo
	echo "</details>"
fi

[ -n "$prev" ] && echo && echo "Changes since $prev."
exit 0
