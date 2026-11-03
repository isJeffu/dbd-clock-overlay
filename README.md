# DbD Clock Overlay

A see-through overlay for **Dead by Daylight** that shows the clock-callout map
for the map you're on, so your group calls out with the same numbers
(12 = top-middle, clockwise). It also reads your lobby perks, counts down the
Endgame Collapse and has a perk roulette on the loadout screen.

It only looks at the screen (Windows' built-in text recognition). It never
reads or changes the game's files or memory. Fan-made; use at your own risk.

## Install

1. Download **`DbD-Clock-Overlay-Setup.cmd`** from the
   [latest release](../../releases/latest).
2. Double-click it. Windows may ask before running it because it isn't
   signed: click **Run** (or **More info -> Run anyway**).
3. In DbD set Display Mode to **Windowed Fullscreen**.

Updates: Start menu -> DbD Clock Overlay -> **Update**.
Remove: Start menu -> DbD Clock Overlay -> **Uninstall**.

Prefer unzipping by hand? Use `DbD-Clock-Overlay.zip` from the release
(see README.txt inside).

## What's in here

| | |
|---|---|
| `scripts/` | the overlay itself (PowerShell): `ClockOverlay.ps1` is the main program, plus the roulette, timers, screen reading, installer and updater |
| `data/` | maps, perks (with roulette themes), killers and map labels, as JSON |
| `assets/` | the Roboto font, the perk-slot texture and the shortcut icon |
| `*.cmd` | for a hand-unzipped copy: download maps, start, auto-start on/off, update, uninstall |
| `Install.ps1` | hands over to `scripts/Install.ps1` (kept for older updaters) |

## Credits

- Callout maps: [Hens333](https://hens333.com/callouts), images by Lethia -
  **not included here**; the installer downloads them from Hens333's site.
- Perk icons: [Dead by Daylight wiki](https://deadbydaylight.wiki.gg), game
  art by Behaviour Interactive - downloaded, not included.
- Perk descriptions (roulette tooltips, `data/perk-text.json`): [Dead by Daylight wiki](https://deadbydaylight.wiki.gg),
  CC BY-SA 4.0; game text by Behaviour Interactive.
- Roulette look: the box frame, perk slot and tier pips (`assets/textures/dbd-*.png`) are cut from Dead by
  Daylight's own loadout screen - Behaviour Interactive's art, used under their
  [fan-content guidelines](https://support.deadbydaylight.com/hc/en-us/articles/4437901307668-General-Guidelines-on-Fan-Created-Content)
  (free, non-commercial; no donations).
- Font: Roboto by Christian Robertson, Apache License 2.0.

Not affiliated with Behaviour Interactive.

## License

Copyright (C) 2026 isJeffu. Released under the
[GNU General Public License v3.0](LICENSE.txt): you may use, change and share
it, and shared changes must stay under the GPL. It comes with no warranty.

The license covers this repository's own code and files only. The callout maps
and perk icons the installer downloads belong to their owners and are not part
of this project. Roboto (in `assets/fonts/`) is under the Apache License 2.0.
`data/perk-text.json` holds perk descriptions from the Dead by Daylight wiki and
stays under its licence, [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/). `assets/textures/dbd-*.png`
are Behaviour Interactive's art and are not covered by the GPL either.
