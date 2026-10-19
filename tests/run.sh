#!/usr/bin/env bash
# Runs solo-display against tests/fake-hyprctl in a throwaway directory.
# Usage: tests/run.sh
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
script="$here/../scripts/solo-display"
failures=0
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

export SOLO_DISPLAY_HYPRCTL="$here/fake-hyprctl"
export SOLO_DISPLAY_QUIET=1
export SOLO_DISPLAY_NO_SHELL=1
export SOLO_DISPLAY_SETTLE_TIMEOUT=2

check() {
  local name="$1"
  shift
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

# jq -e against a file: check_jq <name> <file> <filter> [jq args...]
check_jq() {
  local name="$1" file="$2" filter="$3"
  shift 3
  check "$name" quiet jq -e "$@" "$filter" "$file"
}

quiet() {
  "$@" >/dev/null
}

setup() {
  local case_dir="$tmp/$1"
  mkdir -p "$case_dir"
  export SOLO_DISPLAY_SHELL_CONFIG="$case_dir/shell.json"
  export SOLO_DISPLAY_STATE_DIR="$case_dir/state"
  export SOLO_DISPLAY_FLAG_FILE="$case_dir/toggles/solo-display.lua"
  export FAKE_HYPR_WORLD="$case_dir/world.json"
  WORLD="$FAKE_HYPR_WORLD"
  CONFIG="$SOLO_DISPLAY_SHELL_CONFIG"

  cat >"$CONFIG" <<'JSON'
{
  "bar": {
    "layout": {
      "center": [
        { "id": "omarchy.indicators" },
        { "id": "js.solo-display", "monitor": "DP-1" },
        { "id": "omarchy.clock" }
      ],
      "left": [
        { "id": "omarchy.menu" },
        {
          "id": "air.workspaces",
          "groups": [
            { "monitor": "DP-1", "ids": [1, 2, 3, 4, 5], "colorKey": "bright_red" },
            { "monitor": "DP-2", "ids": [6, 7, 8, 9, 10], "colorKey": "accent" },
            { "monitor": "HDMI-A-1", "ids": [11], "colorKey": "green" }
          ]
        }
      ],
      "right": [ { "id": "omarchy.audio" } ]
    }
  },
  "plugins": [],
  "version": 1
}
JSON
  cp "$CONFIG" "$case_dir/shell.orig.json"
  ORIG="$case_dir/shell.orig.json"

  cat >"$WORLD" <<'JSON'
{
  "log": [],
  "monitors": [
    { "name": "DP-1", "active": 1, "focused": true },
    { "name": "DP-2", "active": 2, "focused": false },
    { "name": "HDMI-A-1", "active": 3, "focused": false }
  ],
  "workspaces": [
    { "id": 1, "monitor": "DP-1", "windows": 1 },
    { "id": 4, "monitor": "DP-1", "windows": 2 },
    { "id": 2, "monitor": "DP-2", "windows": 0 },
    { "id": 7, "monitor": "DP-2", "windows": 1 },
    { "id": 3, "monitor": "HDMI-A-1", "windows": 1 }
  ]
}
JSON
  cp "$WORLD" "$case_dir/world.orig.json"
}

layout_restored() {
  [[ $(jq -S . "$CONFIG") == "$(jq -S . "$ORIG")" ]]
}

# ws-monitor/active pairs equal to the starting world.
world_restored() {
  local expected actual
  expected=$(jq -S '{mons: [.monitors[] | {name, active, focused}], ws: ([.workspaces[] | {id, monitor}] | sort_by(.id))}' "$(dirname "$WORLD")/world.orig.json")
  actual=$(jq -S '{mons: [.monitors[] | {name, active, focused}], ws: ([.workspaces[] | {id, monitor}] | sort_by(.id))}' "$WORLD")
  [[ $expected == "$actual" ]] || { diff <(echo "$expected") <(echo "$actual") >&2; return 1; }
}

# ------------------------------------------------------------------ expand_ids
(
  # shellcheck source=../scripts/solo-display
  source "$script"
  check "expand range" test "$(expand_ids "1-5" | tr '\n' ' ')" = "1 2 3 4 5 "
  check "expand mixed" test "$(expand_ids "3,1-2, 7" | tr '\n' ' ')" = "1 2 3 7 "
  check "expand reversed" test "$(expand_ids "5-3" | tr '\n' ' ')" = "3 4 5 "
  check "expand empty" test -z "$(expand_ids "")"
  check "expand junk" test "$(expand_ids "a,0,2" | tr '\n' ' ')" = "2 "
  check "array setting" test "$(setting '{"workspaces":[1,2]}' workspaces x)" = "1,2"
  check "default setting" test "$(setting '{}' workspaces 1-5)" = "1-5"
) || failures=$((failures + 1))

# ------------------------------------------------------ round trip on DP-1
setup roundtrip
"$script" on
check_jq "only DP-1 enabled" "$WORLD" '[.monitors[] | select(.disabled | not) | .name] == ["DP-1"]'
check_jq "all workspaces on DP-1" "$WORLD" 'all(.workspaces[]; .monitor == "DP-1")'
check_jq "focus kept on ws 1" "$WORLD" '.monitors[] | select(.name == "DP-1") | .active == 1 and .focused'
check "flag disables others" grep -q 'output = "DP-2", disabled = true' "$SOLO_DISPLAY_FLAG_FILE"
check "flag pins ws 5" grep -q 'workspace = "5", monitor = "DP-1"' "$SOLO_DISPLAY_FLAG_FILE"
check "flag watches target" grep -q 'name == "DP-1"' "$SOLO_DISPLAY_FLAG_FILE"
check_jq "workspace widget swapped in place" "$CONFIG" '.bar.layout.left == [{"id": "omarchy.menu"}, {"id": "omarchy.workspaces"}]'
check "status reports active" test "$("$script" status | jq -r .target)" = "DP-1"
"$script" on >/dev/null
check_jq "second on is a no-op" "$WORLD" '[.monitors[] | select(.disabled | not)] | length == 1'
"$script" off
check "flag removed" test ! -e "$SOLO_DISPLAY_FLAG_FILE"
check "state removed" test ! -e "$SOLO_DISPLAY_STATE_DIR/state.json"
check "shell.json restored" layout_restored
check "displays and workspaces restored" world_restored

# ------------------------------------- target taken from --monitor, focus elsewhere
setup other-target
jq '(.monitors[] | .focused) = false | (.monitors[] | select(.name == "DP-2") | .focused) = true' "$WORLD" >"$WORLD.t" && mv "$WORLD.t" "$WORLD"
cp "$WORLD" "$(dirname "$WORLD")/world.orig.json"
"$script" toggle --monitor HDMI-A-1
check_jq "only HDMI-A-1 enabled" "$WORLD" '[.monitors[] | select(.disabled | not) | .name] == ["HDMI-A-1"]'
check_jq "focused workspace follows" "$WORLD" '.monitors[] | select(.name == "HDMI-A-1") | .active == 2'
"$script" toggle
check "restored after --monitor run" world_restored
check "layout restored after --monitor run" layout_restored

# ----------------------------------- new workspace follows the widget's groups
setup new-workspace
"$script" on
jq '.workspaces += [{"id": 8, "monitor": "DP-1", "windows": 1}]' "$WORLD" >"$WORLD.t" && mv "$WORLD.t" "$WORLD"
"$script" off
check_jq "ws 8 goes to its DP-2 group" "$WORLD" 'any(.workspaces[]; .id == 8 and .monitor == "DP-2")'
check_jq "DP-2 still shows ws 2" "$WORLD" '.monitors[] | select(.name == "DP-2") | .active == 2'

# ------------------------------------------- widget re-added by hand meanwhile
setup readded
"$script" on
jq '.bar.layout.right += [{"id": "air.workspaces", "groups": []}]' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
"$script" off
check_jq "stand-in dropped" "$CONFIG" '[.bar.layout[][] | select(.id == "omarchy.workspaces")] | length == 0'
check_jq "hand-added copy kept, no duplicate" "$CONFIG" '[.bar.layout[][] | select(.id == "air.workspaces")] | length == 1'

# ---------------------------------------------------- no widget to suspend
setup no-widget
jq '.bar.layout.left = [{"id": "omarchy.menu"}]' "$CONFIG" >"$CONFIG.t" && mv "$CONFIG.t" "$CONFIG"
cp "$CONFIG" "$ORIG"
"$script" on
check "layout untouched without suspend widget" layout_restored
"$script" off
check "restored without suspend widget" world_restored

# ----------------------------------------------- target unplugged while active
setup lost
"$script" on
jq '(.monitors[] | select(.name == "DP-1")) |= (.connected = false | .disabled = true)' "$WORLD" >"$WORLD.t" && mv "$WORLD.t" "$WORLD"
"$script" off --lost
check_jq "others re-enabled after loss" "$WORLD" '[.monitors[] | select(.disabled | not) | .name] == ["DP-2", "HDMI-A-1"]'
check "state cleared after loss" test ! -e "$SOLO_DISPLAY_STATE_DIR/state.json"

# ------------------------------------------------------------ bad input
setup bad
check "rejects unknown display" bash -c '! "$0" on --monitor DP-9 2>/dev/null' "$script"
check "rejects unsafe display name" bash -c '! "$0" on --monitor "x\"); os.execute(\"id" 2>/dev/null' "$script"
check "nothing written on rejection" test ! -e "$SOLO_DISPLAY_FLAG_FILE"

echo
if ((failures)); then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
