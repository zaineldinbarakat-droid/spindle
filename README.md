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
- **Focus timer.** The timer tab in the notch is a Pomodoro clock: 25/5 by default with
  a long break every four sessions, all adjustable in Settings. While it runs, the
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
- **Vinyl or cover.** *Show Song As* switches between the spinning record and the plain
  album cover, in the notch, the widgets and full screen.
- **Full-screen turntable.** The same scene as an interactive full-screen space.
  Esc leaves it.

Everything is in the menu-bar icon's menu and in Settings.

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
open build/Spindle.app
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
- **An app icon.** Drop an `AppIcon.icns` into `Packaging/` and `build.sh` picks it up.

## Known rough edge

`build.sh` signs ad-hoc. The code directory hash changes on every build, so macOS
re-asks for Automation permission each time you rebuild. Signing with a real Developer ID
certificate makes the grant stick.
