#!/usr/bin/env bash
#
# Build a CurseForge upload zip: dist/GoonWall-<version>.zip
#
# The zip contains a single top-level GoonWall/ folder built from the
# committed HEAD (not the working tree), minus dev-only files. Paths listed
# under "ignore:" in .pkgmeta are excluded too.
#
# Usage: scripts/package.sh [--allow-dirty]
#
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

ADDON=GoonWall
allow_dirty=0
[[ "${1:-}" == "--allow-dirty" ]] && allow_dirty=1

if [[ -n "$(git status --porcelain)" ]]; then
    if (( allow_dirty )); then
        echo "warning: uncommitted changes are NOT included (packaging HEAD)" >&2
    else
        echo "error: working tree has uncommitted changes; commit them or pass --allow-dirty" >&2
        exit 1
    fi
fi

# Version from the committed TOC
version=$(git show "HEAD:$ADDON.toc" | sed -n 's/^## Version:[[:space:]]*\([^[:space:]]*\).*/\1/p' | tr -d '\r')
if [[ -z "$version" ]]; then
    echo "error: no '## Version:' line in $ADDON.toc" >&2
    exit 1
fi

# The changelog's newest entry must match the TOC version
changelog_top=$(git show HEAD:CHANGELOG.md | sed -n 's/^## \([0-9][^ ]*\).*/\1/p' | head -n1)
if [[ "$changelog_top" != "$version" ]]; then
    echo "error: TOC version $version but newest CHANGELOG entry is ${changelog_top:-none}" >&2
    exit 1
fi

# Dev-only paths, plus whatever .pkgmeta ignores
excludes=(tests docs scripts dist .github .gitignore .gitattributes .pkgmeta)
if git cat-file -e HEAD:.pkgmeta 2>/dev/null; then
    while IFS= read -r p; do
        [[ -n "$p" ]] && excludes+=("$p")
    done < <(git show HEAD:.pkgmeta | awk '
        /^ignore:/ { on = 1; next }
        on && /^[[:space:]]*-[[:space:]]*/ { sub(/^[[:space:]]*-[[:space:]]*/, ""); print; next }
        on && /^[^[:space:]]/ { on = 0 }')
fi

pathspec=(.)
for p in "${excludes[@]}"; do
    pathspec+=(":(exclude)$p")
done

mkdir -p dist
out="dist/$ADDON-$version.zip"
rm -f "$out"

git archive --format=zip --prefix="$ADDON/" -o "$out" HEAD -- "${pathspec[@]}"

# Sanity check: TOC must sit at GoonWall/GoonWall.toc
if ! unzip -Z1 "$out" | grep -qx "$ADDON/$ADDON.toc"; then
    echo "error: $out is missing $ADDON/$ADDON.toc" >&2
    exit 1
fi

echo "Built $out ($(git rev-parse --short HEAD), v$version)"
unzip -Z1 "$out" | sed 's/^/  /'
