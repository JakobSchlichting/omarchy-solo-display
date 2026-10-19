# Solo Display

An [Omarchy](https://omarchy.org/) shell plugin (`js.solo-display`). A bar
indicator, living next to the stock indicators (stay awake, night light, …),
that switches to a single display and back:

- **On:** every display except the chosen one is turned off, workspaces 1-5
  are pinned to it, and every open workspace lands on it. You stay on the
  workspace you were on.
- **Off:** all displays come back, every workspace returns to the display it
  was on, each display shows the workspace it showed before, and focus goes
  back to the display that had it.

Left-click toggles. Right-click picks the display to keep.

## Choosing the display

Displays are picked by connector name (`DP-1`, `DP-2`, `HDMI-A-1`, …), the
same names `air.workspaces` uses for its groups. Find yours with
`hyprctl monitors | grep Monitor`. Choose one from the right-click menu or
set it on the widget's `shell.json` entry:

```json
{
  "id": "js.solo-display",
  "monitor": "DP-1",
  "workspaces": "1-5",
  "suspendWidget": "air.workspaces",
  "replaceWith": "omarchy.workspaces"
}
```

| Key             | Default              | Meaning                                                        |
|-----------------|----------------------|----------------------------------------------------------------|
| `monitor`       | focused display      | Connector to keep on                                           |
| `workspaces`    | `1-5`                | Workspaces pinned to it while on (comma list and/or ranges)    |
| `suspendWidget` | `air.workspaces`     | Bar widget taken off the bar while on; `""` to keep the bar    |
| `replaceWith`   | `omarchy.workspaces` | Widget shown in its place while on; `""` for none              |
| `alwaysShow`    | `false`              | Show the indicator while off without hovering the bar center   |

## Workspaces by Monitor (`air.workspaces`)

`air.workspaces` colors and groups workspace numbers per display and its Save
button rewrites workspace pins and reloads Hyprland. With only one display on,
its groups don't match reality, so while solo mode is on its bar entry is
swapped for the stock `omarchy.workspaces` widget in the same slot. Turning
solo mode off puts the original entry back verbatim, groups and all. If you
re-add it by hand in the meantime, the stand-in is simply dropped.

Workspaces opened while solo mode was on (say 8) return to the display their
`air.workspaces` group names (DP-2 for 6-10), so they don't all pile up on
the solo display.

## How it works

Everything happens in `scripts/solo-display`; the widget only runs it and
shows its state.

- Before changing anything it snapshots displays, workspaces, focus and the
  suspended widget entry to `~/.local/state/solo-display/state.json`. That
  file's presence is the on/off state.
- Displays are turned off through Omarchy's Hyprland toggle directory: it
  writes `~/.local/state/omarchy/toggles/hypr/solo-display.lua`
  (`hl.monitor({ output = …, disabled = true })` plus workspace pins), which
  Hyprland loads after `monitors.lua` on every reload. Solo mode therefore
  survives `hyprctl reload`, theme switches and reboots, and turning it off is
  deleting that file and reloading.
- The same file asks Hyprland to run `solo-display off` if the remaining
  display is unplugged, so you can't end up with nothing lit.

It can also be triggered from a keybinding in `~/.config/hypr/bindings.lua`,
either through the bar (same as a click) or by running the script directly:

```lua
o.bind("SUPER + CTRL + S", "Solo display", "omarchy-shell js.solo-display toggle")
-- or, independent of the shell:
-- o.bind("SUPER + CTRL + S", "Solo display", "~/.config/omarchy/plugins/js.solo-display/scripts/solo-display toggle")
```

A newly added IPC target only registers when the shell starts, so after the
first install run `omarchy restart shell` once before using `omarchy-shell`.

```
solo-display <on|off|toggle|status> [--monitor <connector>]
```

### Recovering by hand

If something goes wrong and displays stay off:

```sh
~/.config/omarchy/plugins/js.solo-display/scripts/solo-display off
# or, as a last resort:
rm ~/.local/state/omarchy/toggles/hypr/solo-display.lua && hyprctl reload
```

## Development

```sh
tests/run.sh                 # runs the script against a simulated hyprctl
scripts/install-local.sh     # installs/updates the copy in ~/.config/omarchy/plugins
```

Omarchy refuses symlinked plugins, so the install script copies the files;
rerun it after editing.
