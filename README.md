# ❄ Snowdrift

A small menu bar app that brings a snowy evening to your Mac desktop.

- **Snow falls over everything**, in soft layers: far-away flakes are small and slow, close ones are big and drift with the wind.
- **Snow settles on your windows.** It piles up along the top edge of every app window you can see, and on the bottom of the screen. Drag a window and the snow slides off it.
- **Snowball mode.** Hold the mouse button to scoop up snow (near a pile it grows faster), then flick to throw. Snowballs splat on windows, drip, and fade away. Throw one down onto a window and it adds to the pile.
- **Snowmen.** Build one from the menu, or double-click in snowball mode. Hit it with a snowball and it wobbles.
- **Wind and gusts**, from calm to gusty.
- **Your cursor stirs the snow** as you move it through the flakes.
- **Frosty screen edges**, if you want the "looking out a cold window" feel.

Snow never gets in the way: you can click, type and drag through it as usual. Only snowball mode takes over the mouse, and Esc gets you out.

## Install (about 5 minutes, no Xcode needed)

You need macOS 13 Ventura or newer.

1. **Install Apple's free command line tools** (skip if you've done this before).
   Open **Terminal** (press ⌘ Space, type `Terminal`, press Return) and paste:

   ```
   xcode-select --install
   ```

   Click **Install** in the window that pops up and wait for it to finish. If Terminal says they are already installed, you're set.

2. **Unzip** `Snowdrift.zip` by double-clicking it. You get a `Snowdrift` folder (say it's in Downloads).

3. **Build and open it.** In Terminal, paste:

   ```
   cd ~/Downloads/Snowdrift
   bash build.sh install
   ```

   This builds the app, copies it into your Applications folder, and starts it. The first build takes a minute or two.

4. Look for the **❄ snowflake in your menu bar** (top right of the screen). Snow should start falling right away.

To start it again later, open **Snowdrift** from Applications or Launchpad, or turn on **Open at login** in its menu.

## Using it

Click the ❄ in the menu bar:

| Menu item | What it does |
|---|---|
| Let it snow | Turns snowfall on or off (settled snow slowly melts while it's off) |
| Snowfall | Light flurries, steady snow, heavy snow, or a blizzard |
| Wind | Calm, gentle breeze, or gusty |
| Snow settles on windows | Lets snow pile up on window tops |
| Cursor stirs the snow | Flakes swirl away from your moving mouse |
| Frosty screen edges | A soft frost glow around the edges of the screen |
| Snowball mode (⌃⌥S) | Hold to scoop, flick to throw, double-click for a snowman, Esc or right-click to exit |
| Build a snowman | Puts a snowman at the bottom of your screen |
| Shake snow off windows | Knocks all the settled snow off |
| Clear all snow | Clears everything, snowmen included |
| Open at login | Start Snowdrift when you log in (works once it's in Applications) |

**Shortcut:** press **Control-Option-S** anywhere to jump in and out of snowball mode.

## Permissions

None. Snowdrift only reads where windows are (not what's in them), which macOS allows without asking.

## Troubleshooting

- **`xcrun: error` or "developer tools aren't installed":** do step 1, then run `bash build.sh install` again.
- **No snowflake in the menu bar:** on a MacBook with a notch, the menu bar may be full. Quit an app with a menu bar icon or hold ⌘ and drag icons to make room.
- **Snow doesn't pile on a window:** it only settles where the top edge of the window is visible. Full-screen apps have no visible top edge, so snow falls past them.
- **To quit:** ❄ menu → Quit Snowdrift.
- **To uninstall:** quit it, then drag Snowdrift from Applications to the Trash.

## For the curious

It's a small Swift package (AppKit, no dependencies):

- `SnowEngine.swift`: the simulation (flakes, piles, snowballs, splats, snowmen) and all the drawing.
- `WindowTracker.swift`: reads other windows' positions with `CGWindowListCopyWindowInfo`.
- `Overlay.swift`: transparent, click-through windows, one per display.
- `AppDelegate.swift`: menu bar menu, timers, snowball mode.
- `HotKey.swift`: the Control-Option-S shortcut.

`swift build` compiles it; `build.sh` wraps the binary into `Snowdrift.app`.
