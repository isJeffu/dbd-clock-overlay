DbD Clock Callouts Overlay
==========================

Shows the clock-callout map for the Dead by Daylight map you're on, in the
top-left corner of your screen, so everyone in the group calls out with the
same numbers. 12 = top-middle of the map, numbers go round clockwise.

Callout maps: Hens333 (hens333.com/callouts), images made by Lethia.
Perk icons: Dead by Daylight wiki (deadbydaylight.wiki.gg), game art by Behaviour.
Font: Roboto by Christian Robertson (fonts folder), Apache License 2.0 -
https://www.apache.org/licenses/LICENSE-2.0
They are NOT included in this zip - step 1 downloads them from those sites.
Please don't re-share the images themselves.


SETUP (once)
------------
EASIEST: double-click "DbD Clock Overlay Setup.cmd". It installs into your
own AppData folder, downloads the 58 maps and ~180 perk icons (a minute),
puts a "DbD Clock Overlay" shortcut on your desktop and in the Start menu,
and asks whether it should open by itself whenever you start DbD (a tiny
watcher starts with Windows and checks every 5 s whether the game runs).
Windows may ask whether to run it, because it isn't signed: click Run (or
"More info" > "Run anyway"). Running Setup again later updates it and keeps
your settings. Then in DbD set Display Mode to "Windowed Fullscreen"
(in true Fullscreen nothing can draw over the game).

BY HAND (the zip instead):
1. Right-click the zip > "Extract All..." (e.g. into Documents) and open the
   extracted folder. Don't run the files from inside the zip - they need
   each other, and Windows only pulls out the one you double-click.
2. Double-click "1 - Download maps" (takes a minute), then press any key.
3. Set DbD's Display Mode to "Windowed Fullscreen".
4. Optional: double-click "3 - Auto-start with DbD". Turn it off again with
   "Remove auto-start".

PLAYING
-------
Use the desktop shortcut, or "2 - Start overlay" if you unzipped it by hand
(neither is needed if auto-start is on). A small green label appears top-right -
that means it's running ("waiting for Dead by Daylight" until the game is
in front, then "watching for map").

- When a match starts it reads the map name off the intro (bottom-left of
  the screen for a few seconds) and shows the map top-left. This works even
  if you've tabbed to Discord or another monitor while the match loads.
- If it hasn't found it, the label turns amber: "Map not detected - hold TAB".
  Hold TAB for a second (the match details screen shows the map name) and
  it will pick it up.
- When you're back on the end screen / lobby, the map goes away again.

Keys (all single keys: Shift is "run" and Ctrl is "crouch" in DbD, so the
overlay never uses them as modifiers):
  F6        pick a map by hand         PageDown  auto-detect on/off
  F7        move the map to another corner
  F8        show / hide the map
  F9        change see-through level   F10       change size
  (auto)    In the lobby, the overlay reads your 4 perk icons from the screen
            and uses them for the timers - the status label shows what it read.
            It's tuned for a 16:9 screen with the default HUD size; if it
            reads wrong perks, untick "Read my perks" in PageUp and tick them.
  PageUp    pick the perks you run (tick them in a list; saved). Perks that
            have a timer get a I / II / III dropdown - set it to the tier you
            own, since the lengths differ (e.g. Sprint Burst exhaustion is
            60 / 50 / 40 s). The timers below then show YOUR perks. With nothing picked, a generic set is
            used: Borrowed Time / Will to Live (DS) / Off the Record / Sprint Burst.
            You can also tick "assume Lethal Pursuer": a 9 s countdown at the
            start of every match while the killer could see your aura.
  F4        you unhooked someone - starts by itself from the "HOOK RESCUE"
            score pop-up; press F4 if it misses. (Borrowed Time, Babysitter,
            We'll Make It - or, with none of those, the 10 s basekit
            Endurance every unhooked Survivor gets) plus 10 s Elusive: the
            unhooked Survivor leaves no scratch marks, grunts or blood and the
            killer can't see their aura (not after all gens are done)
  Insert    you were unhooked - also starts by itself when "ENDURANCE" and
            "HASTE" appear in your status strip (Will to Live, Off the Record,
            Second Wind, Deliverance / Shoulder the Burden broken timers, plus
            the 10 s basekit Endurance). The status label says which of the
            two it started, in case F4 / Insert get mixed up.
  F3        you used your exhaustion perk - Exhausted countdown (40 s, or
            20 s for Smash Hit / Background Player). With no exhaustion perk
            in your build the label just says so.
            Timers are perk icons counting down at the bottom middle.
  Delete    clear the unhook timers
  F5        chase timer: press when a chase starts. It stops by itself when the
            chase ends (the "CHASED" / "ESCAPED" score pop-up), or press F5 again.

MAP LABELS
  Symmetric maps get extra labels drawn on the callout image (landmarks.json):
  Midwich shows every room on both floors (stairs only at the 11 and 4-5
  corners, exits at 12 and 6 on the ground floor, library / chem lab on the
  12 side upstairs). Wreckers' Yard has no fixed landmark except the shack, so
  it's labelled by shape: narrow side at 12, wide side at 6, wings at 3 and 9.

STATUS EFFECTS
  When a status effect lands on you (Oblivious, Exhausted, Hindered...) the
  label shows it for a few seconds with the cause the game printed next to
  it, e.g. "Oblivious (Killers Power)". status-log.txt keeps the list.
  When you get unhooked, any perk the screen names at that moment (the
  rescuer's Borrowed Time, Babysitter) starts its timer for you too.

PERK ROULETTE
  Open your LOADOUT: a SPIN button appears just above your 4 perk slots.
  Click it: four diamond reels spin right on top of your slots, lock in one
  by one (ticks and a mechanical clunk - sounds are made by the overlay
  itself, in the "sounds" folder), then slide into a list on the right with
  the perk names, so your own slots are free to click.
  It only shows the build - equip the perks yourself; the overlay reads them
  from the lobby as usual. Clicking it doesn't take focus away from the game.
  The pick is from every survivor perk, not just the ones you own.

TIMERS AND COMPASS ARE OFF AT FIRST
  Out of the box you get the map, perk reading, the collapse countdown and
  the roulette. The perk timers and the compass (a trial) start switched off.
  To turn them on: close the overlay, open settings.json (it appears after
  the first run) and set "TimersOn": true and/or "CompassOn": true.
  Timer lengths are from before DbD's 10.2 perk rework - some may be off.

ENDGAME COLLAPSE COUNTDOWN
  Once a gate is opened, the game shows the collapse bar at the top of the
  screen. The overlay measures how full it is and shows the seconds left
  just right of the bar, e.g. "Collapse 1:21". A full bar is 2 minutes; it
  drains at half speed while anyone is downed, hooked or caged - then the
  label says "slowed" and shows the time if it stays that slow (up to 4
  minutes). It turns orange when the bar does. Read from screen pixels only.
  While it shows, the compass moves down a little so the bar stays visible.

COMPASS (trial - expect some drift)
  A Skyrim-style strip at the top middle of the screen shows which clock
  direction you're facing, worked out from your mouse movement. The turn
  rate comes from your survivor mouse sensitivity in the game's own settings
  file, so there's nothing to set up. Nothing in the game tells it where you
  started, though, so you set that yourself:
  ScrollLock  only if the strip turns too far or not far enough: press it,
            turn exactly ONE full circle to the right, press it again.
  F2        "I'm facing 12 now" - sets north for this match. It resets every
            new match, and also when the killer picks you up (the strip greys
            out until you press F2 again once you're free). Vaults, lockers
            and stuns also turn the camera without the mouse, so press F2
            again whenever it looks off. Mouse movement on other windows
            (alt-tab) and on the TAB / Esc screens doesn't count, and the
            strip switches off once your match is over.
  F1        show / hide the strip. While the chat wheel's mouse button is
            held the camera is frozen, so the strip ignores the mouse then.
  Home      move the timers: low / middle / high at the bottom of the screen
  End       timer size: normal / bigger / biggest
  PrintScreen  save a screenshot WITH the overlay in it (Screenshots folder) -
            normal screenshots won't show the overlay, on purpose
  Pause     quit  (or right-click the tray icon > Quit)
The keys only work while Dead by Daylight is the window in front.
Don't press F11 in DbD - the game uses it to switch out of borderless.
It remembers your position, size and see-through choices.
Timers clear themselves when the match ends. Perk lengths for all three tiers
live in perks.json - edit them there if a patch changes them.

Status label colours: green = working, amber = map not detected or auto-detect off,
red = something's wrong (it says what).


UPDATING
--------
Start menu > DbD Clock Overlay > "Update DbD Clock Overlay" (or Update.cmd
in its folder). It checks github.com/isJeffu/dbd-clock-overlay for a newer
version and installs it in place - your settings, maps and auto-start stay.
When the overlay starts it also asks GitHub once whether there's a newer
version and, if so, says "Update ... available" on its label in the lobby.
That's a plain web request; nothing about you or your games is sent.

REMOVING IT
-----------
No registry entries, no changes to the game.
- Installed with Setup: Start menu > DbD Clock Overlay > "Uninstall DbD
  Clock Overlay". It turns auto-start off, closes the overlay, removes the
  shortcuts and deletes its folder.
- Unzipped by hand: if you turned auto-start on, double-click "Remove
  auto-start"; quit the overlay (Pause in game, or tray icon > Quit); then
  delete the folder.

SCREEN SETUP
------------
- Any resolution (1080p, 1440p, 4K), ultrawide (21:9, 32:9) and any Windows
  display scaling: everything is placed relative to your screen, the way DbD
  places its own menus (loadout panel on the left, your lobby perks on the
  right, collapse bar in the middle). Animations run at your monitor's
  refresh rate (60 / 144 / 240 Hz...).
- Play DbD on your MAIN monitor, in Windowed Fullscreen.
- DbD's own Menu / HUD scale (Settings > Graphics, 70-100%) is read from the
  game's settings file automatically, so the SPIN button, perk reading and
  the collapse countdown follow it. Changed it while the overlay runs? Close
  and start the overlay again so the SPIN button resizes too.
- Ultrawide and things look off (SPIN button not on your perks, wrong perks
  read, no collapse countdown)? Close the overlay, open settings.json, set
  "UiLayout": "16:9" (for DbD showing its menus in a 16:9 box in the middle)
  and start it again. "auto" is the default.

GOOD TO KNOW
------------
- How it finds the map: every couple of seconds it takes a picture of the
  game and reads the text on it with the text recognition built into
  Windows. While the game is the window in front that's a screenshot; if
  you've tabbed to something else it photographs the game window alone, so
  your other windows are never read. It never
  reads or changes the game's files or memory - it's a separate see-through
  window, like a crosshair overlay. That said, it's a fan-made tool: use it at
  your own risk.
- It only works with Windows and the game set to English.
- Needs Windows 10 or 11. If step 1 says a decoder is missing, install
  "Webp Image Extensions" from the Microsoft Store and run step 1 again.
- Your antivirus may be wary of it because it's a script that takes
  screenshots. You can read every file in Notepad - it's all plain text.
- It writes "ocr-log.txt" next to itself: the text it read from your screen
  (includes player names). It never leaves your PC; delete it any time.
- Shift is the run key in DbD, so the overlay never treats it as a modifier -
  F2 while running is still F2.
- The game also receives F1-F10 when you press them (DbD doesn't use them by
  default). If you've bound any of them in DbD's keybinds, change one of the two.
