#!/usr/bin/env bash
# Installs (or updates) this checkout as ~/.config/omarchy/plugins/js.solo-display
# and puts the widget next to the indicators on first install.
# Omarchy refuses symlinked plugins, so the files are copied; rerun after edits.
set -euo pipefail

id="js.solo-display"
project=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
plugins="$HOME/.config/omarchy/plugins"
target="$plugins/$id"

mkdir -p "$plugins"
# Hidden names are ignored by the plugin scanner, so staging can't be picked up half-copied.
stage=$(mktemp -d "$plugins/.$id.XXXXXX")
old="$plugins/.$id.old"
trap 'rm -rf -- "$stage" "$old"' EXIT
chmod 755 "$stage"

cp "$project/manifest.json" "$project/SoloDisplay.qml" "$project/README.md" "$stage/"
mkdir "$stage/scripts"
cp "$project/scripts/solo-display" "$stage/scripts/"
chmod +x "$stage/scripts/solo-display"
omarchy plugin validate "$stage"

first_install=true
if [[ -e $target ]]; then
  first_install=false
  mv -T -- "$target" "$old"
fi
mv -T -- "$stage" "$target"

omarchy-shell shell rescanPlugins >/dev/null

if $first_install; then
  for ((attempt = 0; attempt < 40; attempt++)); do
    if omarchy plugin list --json | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null; then
      omarchy plugin enable "$id" --after omarchy.indicators
      exit 0
    fi
    sleep 0.1
  done
  echo "Files installed, but discovery timed out. Run: omarchy plugin enable $id --after omarchy.indicators" >&2
  exit 1
fi

echo "Updated $target"
