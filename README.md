# Spindle

A retro turntable that lives in your MacBook's notch. Hover the notch and a panel drops
down with a spinning record, the current album art pressed into the centre label, and a
tonearm you can pick up and drag to scrub through the track.

## Status

Built and verified against a MacBook Pro `Mac17,2` on macOS 27.0.

| Area | State |
| --- | --- |
| Apple Events scripts (Spotify) | Verified live — all 8 fields parse |
| Apple Events scripts (Apple Music) | Compiles clean; not yet run against a live library |
| Notch detection | Verified on hardware — 185 × 32 pt, centred |
| Tonearm inverse geometry | Unit-tested, round-trip error 1.4e-15 |
| SwiftUI view layer | **Needs Xcode to compile — see below** |

## What it does

- **Notch turntable.** Hover the notch: the record spins with the cover art on the label,
  and the tonearm tracks the playhead. Drag the arm to scrub.
- **Click to open the source app.** Click the record (in the notch, a widget or full
  screen), the track title, or the left side of the notch strip, and Spotify or Music
  comes to the front with its window showing.
- **Focus timer.** The timer tab in the notch is a Pomodoro clock with two presets —
  *Classic* 25/5 (15-minute long break) and *Deep Work* 50/10 (30-minute long break) —
  switchable from the timer tab, the menu or Settings, and every length adjustable. While it runs, the
  countdown sits in the collapsed notch. When a phase ends you get a chime and a
  notification, and the notch drops open briefly. It can also pause your music during
  breaks and start it again when focus begins.
- **Desktop widgets.** A small *Record* widget and a wide *Turntable* widget sit on the
  desktop like macOS widgets: above the icons, below your windows, on every Space.
  They're live, so the record spins and you can drag the tonearm. Drag the wooden edge
  to move one; right-click it to remove it.
- **Turntable wallpaper.** A full-screen retro scene (walnut deck, blurred cover-art
  room, film grain, big serif type) drawn behind your desktop icons. Off by default;
  *Desktop Wallpaper → My Wallpaper* puts yours back.
- **Notch look.** *Song Color* (the default) washes the notch in a deep tint of the
  cover's dominant colour, cross-fading when the song changes; *Black* blends into the
  hardware notch; and
  *Liquid Glass* uses macOS 26's glass material tinted with the cover.
- **Vinyl or cover.** *Show Song As* switches between the spinning record and the plain
  album cover, in the notch, the widgets and full screen.
- **Full-screen turntable.** The same scene as an interactive full-screen space.
  Esc leaves it.

Everything is in the menu-bar icon's menu and in Settings.

## Sleeve — the menu bar manager

Sleeve is a second, separate app in this repo: a free menu bar manager in the spirit of
Ice/Bartender, built to sit next to Spindle without the two ever fighting over the top
of the screen.

- **Hide all apps until hover (default).** Like Ice: the menu bar shows only Sleeve and
  Apple's own icons. Hover over Sleeve's icon (or the right side of the bar) and every
  app icon comes back; move away and they tuck away again. Pick apps to always keep
  visible under *Settings → Layout*.
- **Instant and steady.** Revealing on hover and hiding when the cursor leaves the menu
  bar have no delay (measured on macOS 27: ~100 ms to show, ~70 ms to hide, including
  macOS redrawing the bar), with a little spatial slack so resting on the bar's edge
  never flickers. An open menu holds things in place.
- **No icon, if you like.** Turn Sleeve's icon off and the menu bar itself is the
  interface: hover to show, move away to hide. Open Sleeve again to get to Settings.
- **Two-finger click** on Sleeve's icon or an empty part of the bar shows or hides the
  hidden apps (⌃-click the icon for Sleeve's menu).
- **An icon with two faces,** like Ice's image sets: an outlined eye while your apps are
  tucked away, a filled one while they're showing — or dot, ellipsis, chevron, door,
  record, or your own image.
- **Three sections** (with hide-all off). Visible, Hidden and Always Hidden, separated by Sleeve's toggle and
  two faint │ dividers. ⌘-drag icons across the dividers. On macOS 14–26 you can also
  drag them between the columns in *Settings → Layout* and Sleeve performs the ⌘-drag
  for you; macOS 27 ignores synthesized ⌘-drags, so there it's done by hand.
- **Reveal** by clicking the toggle (⌥-click for Always Hidden too), hovering or clicking
  an empty stretch of the bar, scrolling/swiping on the bar, or a hotkey.
- **Auto-rehide** when the cursor leaves the menu bar (never while a menu is open), after
  a delay, or never.
- **Sleeve Bar.** A floating drawer under the menu bar that lists hidden icons, so on a
  notched MacBook they can't end up behind the camera. Click one and its real menu opens.
- **Styling.** Solid tints or multi-stop gradients (add, drag and recolour stops, set
  any angle; Sunset, Aurora, Ice and Neon presets), Full / Rounded / Split-capsule shapes, shadows and
  borders, with a separate Dark Mode style and per-display overrides.
- **Spacing.** A slider for icon spacing (applied by restarting the apps that own icons).
- **Search.** ⌃⌥⌘S opens a finder for every menu bar icon; Return opens its menu.
- **Automation.** Keep a section open while the battery is low, a given Wi-Fi network is
  connected, a Focus is on, or a script exits 0.
- **Zen mode.** ⌃⌥⌘Z covers the whole menu bar on every display (and hides Spindle's
  notch pill); double-click the bar or press the hotkey again to come back.

Default hotkeys are ⌃⌥⌘ + H (hidden), A (all), S (search), Z (Zen), all rebindable.

### How Sleeve hides icons on macOS 27

Every menu bar manager before macOS 27 hid icons by stretching a divider to 10 000 pt so
it pushed its neighbours off the screen. macOS 27 moved status item layout into a system
process (MenuBarAgent) that caps item width: measured on this machine, an icon "behind" a
10 000 pt divider moved 20 pt. It also ignores synthesized ⌘-drags.

So on macOS 27 Sleeve uses **native hiding**: the private `MenuBarClientCore` restriction
behind macOS's exam mode (first used by [Hidden Bar](https://github.com/dwarvesf/hidden)).
Sleeve hands MenuBarAgent an allow-list of apps and macOS removes every other app's icons
and reflows the bar, so hidden icons really disappear and free their space. The bridge is
a small Objective-C target (`Sources/MenuBarVisibility`) that resolves everything at
runtime and catches exceptions, and Sleeve fails open: if the API is missing or errors,
it releases any restriction and falls back to **covering** — a frosted capsule with a
quiet "•••" over each hidden stretch; click it to reveal. (An earlier cover painted the
wallpaper and froze Sleeve when the wallpaper lived in a protected folder; the cover now
reads no files.) Limits: native hiding is per app, and Apple's own icons are always
kept (Sleeve covers those when they're in a hidden section). Verified on macOS 27.0.1:
the restriction is accepted, the bar reflows, and hover reveal/rehide cycle cleanly.

On macOS 14–26 Sleeve uses the classic push-off-screen method. macOS 27's own "Show
Hidden Menu Bar Items" button, and anything macOS has overflowed into it, is left alone.

### Working with Spindle

The apps talk over distributed notifications (`Sources/SpindleSync`). Spindle publishes
the strip it occupies around the notch; Sleeve keeps its hover zone, styling and Sleeve
Bar out of it. Only one dropdown is open at a time, and Zen mode hides Spindle too.

### Permissions

Both apps are signed with a requirement pinned to their bundle identifier rather than
the per-build hash, so a permission granted once keeps working after a rebuild. An entry
left over from an older build stays switched on but no longer matches; Sleeve's
**Fix Permission** button clears its own entry (`tccutil reset Accessibility
com.spindle.sleeve`) and asks again, and Sleeve picks the grant up without a restart.


Sleeve needs **Accessibility** (to see, click and rearrange icons). Wi-Fi rules need
**Location** (macOS hides network names otherwise) and Focus rules need **Full Disk
Access** (there is no public Focus API). Each is asked for only when a feature needs it.

## App icons

Both icons are drawn in code by `Packaging/make-icons.swift` (run it with `swift` to
regenerate the `.icns` files): Spindle's vinyl on a walnut tile, and Sleeve's flat
menu-bar capsule — faded dots for the hidden apps, solid ones for those on show.
`build.sh` bundles them.

## Updates

Both apps check this repository for updates once a day (and on demand from their menu
or Settings → Updates). `updates/latest.json` holds the newest version and its notes;
`updates/Spindle.zip` and `updates/Sleeve.zip` hold the builds. When there's a newer
version the app shows what changed and offers **Install & Relaunch**: it downloads its
zip, checks the bundle identifier and code signature, sets the old copy aside, puts the
new one in its place and reopens. Permissions carry over (see below).

To publish a fix — say, for a new macOS release:

```bash
./release.sh 0.3.1 "Works with macOS 28"
```

then commit and push. `VERSION` is the single version number both apps are built with.

## Requirements

**Xcode is required.** The Command Line Tools are not enough: in the macOS 26+ SDK
SwiftUI's `@State`, `@Binding` and `@AppStorage` are macros, and the plugin that
implements them (`libSwiftUIMacros.dylib`) ships only inside Xcode.

```
error: external macro implementation type 'SwiftUIMacros.StateMacro'
       could not be found for macro 'State()'
```

After installing Xcode:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
./build.sh
open build/Spindle.app build/Sleeve.app
```

On first launch macOS asks permission to control Music and Spotify. That prompt is the
whole integration — say no and the app has nothing to display.

## How it reads your music

Spindle talks to the *locally running* Music and Spotify apps over Apple Events. It has
no account, no API key and makes no network request except to fetch Spotify's cover art
URL. Nothing about what you listen to leaves the machine.

This is deliberate rather than incidental:

- **The private `MediaRemote` framework is not an option.** Apple restricted it to
  Apple-signed binaries in macOS 15.4, and even before that it could not seek a third
  party app's playhead.
- **Apple Events can seek.** `player position` is read/write in both apps' scripting
  dictionaries, which is the only reason drag-to-scrub can exist at all.

### Two bugs this design surfaced early

Both were caught by running the scripts before writing the UI, and both are the kind that
only appear on some machines:

1. **`st` is a reserved word.** It is AppleScript's ordinal suffix (as in "1st"), so
   `set st to ...` is a syntax error. So are `nd`, `rd` and `th`. Variables are spelled
   out for this reason.
2. **AppleScript returns numbers in the system locale.** On this Mac
   (`en_SA@rg=dezzzz`) `player position` comes back as `42,5`, and `Double("42,5")` is
   `nil` — which would have pinned the playhead at zero and silently broken both the
   progress bar and scrubbing. `String.appleScriptDouble` normalises it. The write
   direction needs the opposite care: `set player position to 42,5` is a syntax error,
   only `42.5` parses, which is what Swift's interpolation emits anyway.

## Architecture

```
Sources/Spindle/
  Player/            Apple Events layer — no UI dependency
    AppleScriptBridge   serial queue, compiled-script cache, TCC classification
    SpotifyProvider     8-field snapshot, ms durations, artwork by URL
    AppleMusicProvider  7-field snapshot, second durations, artwork as raw bytes
    PlayerManager       provider arbitration, 1 Hz poll + interpolation, scrub
    ArtworkLoader       actor; caches art and derives the accent colour
  Notch/
    NotchGeometry       safeAreaInsets + auxiliaryTop*Area -> notch rect
    NotchPanel          borderless non-activating NSPanel above the menu bar
    NotchWindowController  global mouse monitors, hover state
    NotchRootView       collapsed pill / expanded panel
  Focus/
    PomodoroTimer       deadline-based phases, notifications, music pause/resume
    FocusView           kitchen-timer dial, controls, mini now-playing
  Desktop/
    DesktopPanel        desktop-layer panels (widget level / wallpaper level)
    DesktopController   widgets, wallpaper backdrop, full-screen window
    DesktopWidgetViews  walnut chrome, small and wide widgets
    BackdropView        the full-screen retro scene
  Vinyl/
    TonearmGeometry     pivot maths, exact progress <-> angle inverse
    VinylView           static grooves + rotating sheen, label, spindle
    TonearmView         arm, headshell, drag-to-scrub
  UI/                 shape, transport, progress, marquee, visualizer, settings

Sources/SpindleSync/  shared by both apps: the notification channel

Sources/Sleeve/
  Core/               AX scanner, sections, cover hiding (macOS 27), item mover,
                      reveal gestures, hotkeys, automation, spacing, Spindle bridge
  Appearance/         style model and the overlay drawn behind the bar
  UI/                 Sleeve Bar, search, Zen, settings
```

Two details worth knowing before changing things:

**Polling is 1 Hz, motion is not.** One Apple Event per second sets a position anchor;
everything smoother (progress bar, record rotation) is interpolated from a monotonic
clock. Polling at frame rate would mean 60+ IPC round-trips a second for no gain.

**The panel never resizes.** It is always the expanded size and becomes click-through
when collapsed, so it doesn't swallow menu-bar clicks. Resizing the window on every hover
produced visible tearing; hit-testing carries the state instead.

## Not built

Honest list, so nothing here is a surprise:

- **WidgetKit widgets.** The desktop widgets are Spindle's own windows, not
  Notification Centre widgets. Apple's widgets need an App Group backed by a
  provisioning profile (so a paid developer team; this machine has no signing
  identity). They are also limited to timeline snapshots, so the record couldn't spin
  and the arm couldn't be dragged. iPhone home-screen widgets would need a separate
  iOS app.
- **YouTube, Tidal, Amazon Music, SoundCloud.** None expose a scripting dictionary. They
  are browser or Electron apps, so the only routes are a browser extension or each
  service's Web API with OAuth — a different and much larger integration than the one
  here. Spotify's Web API could also drive this if you ever want it working while the
  desktop app is closed.
- **A real spectrum analyser.** The collapsed-view visualizer is decorative motion from
  layered sine waves. Reading actual system audio needs a loopback device or an audio
  tap, which a passive widget has no business installing.
- **Sleeve per-Space and per-Focus styles.** macOS has no public API for the current
  Space, and Focus filters need an App Intents extension that SwiftPM can't build.
  Styles switch per light/dark mode and per display.

## Known rough edge

`build.sh` signs ad-hoc. The code directory hash changes on every build, so macOS
re-asks for Automation (Spindle) and Accessibility (Sleeve) permission each time you
rebuild — for Sleeve, remove the old entry in Privacy & Security → Accessibility and add
the new build. Signing with a real Developer ID
certificate makes the grant stick.
