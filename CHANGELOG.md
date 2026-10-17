# Changelog

All notable changes to Spindle and Sleeve. Both apps share one version number.

## 0.5.1 — Spindle & Sleeve
- The project is now **spindle-and-sleeve** on GitHub; both apps fetch their updates from the new address.
- Each app has its own page and its own download, and both explain how they're made to work together.

## 0.5.0 — Lightweight, and genuinely clear glass
- **Both apps are now very light.** Idle: Spindle ~0.1 % CPU / 30 MB (was a third of a CPU core), Sleeve ~0.1 % / 15 MB.
- Spindle's playing indicator and spinning record run as Core Animation loops — no per-frame work in the app.
- Spindle's playback updates are event-driven (Spotify's and Music's own notifications) with a light re-sync poll.
- Sleeve only scans every app's menu bar when apps launch or quit; otherwise it re-reads the few that own icons.
- Spindle's Liquid Glass is truly see-through at *Clear*, with Apple's lensing edges, fading to frosted.

## 0.4.2
- The focus phase is now called **Lock In**.

## 0.4.1
- No more album-colour glow or coloured edge behind the cover in the notch (optional *Glow behind the album cover* setting).
- A focus timer card on the full-screen turntable, with presets, pause, skip and reset; hide it with one click.

## 0.4.0
- Sleeve's two-finger-click menu opens instantly at the click.
- Hover works whichever app is in front (passive event tap).
- 12 new icon styles and an **Emoji** style: any emoji, grey while hidden, full colour while showing.

## 0.3.9
- Sleeve's icon sits on the right with your apps; clicks never hide apps; adjustable icon spacing.
- Hovering Spindle's notch never triggers Sleeve; Spindle's icon lands beside the other apps.
- Spindle's notch closes sooner after the cursor leaves.

## 0.3.8
- Friendlier menu bar colour settings: live preview, quick looks, palettes, *Album* colour.

## 0.3.6 – 0.3.7
- Sleeve: apps appear in the bar itself on hover; a real hidden section; per-app *Always / On Hover / Hidden* placement.

## 0.3.4 – 0.3.5
- Fixed a crash on next/previous track.
- An Apple-style notch: seamless black, smooth flared shoulders.
- Playing indicator options (style, colour, brightness, glow); Liquid Glass clarity slider; one-tap 25/5 ↔ 50/10 timer switch.

## 0.3.0 – 0.3.3
- Self-updating from this repository.
- Steady, zero-delay hover; Sleeve's animated icon and menu; menu bar tint drawn over the bar.

## 0.2 — Sleeve
- **Sleeve**, a menu bar manager synced with Spindle: native macOS 27 hiding, hide-all-until-hover, gradients, Zen mode, search, hotkeys and automation.
- Spindle: notch looks (Black, Song Color, Liquid Glass) and the 50/10 preset.

## 0.1 — Spindle
- A retro turntable in the MacBook notch for Spotify and Apple Music: spinning record, draggable tonearm, focus timer, desktop widgets, turntable wallpaper and full-screen mode.
