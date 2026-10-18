# Changelog

All notable changes to Spindle.

## 0.6.1 — Swipe and size
- **Swipe between the player and the timer** with two fingers, like flipping through photos: the pages follow your fingers, rubber-band at the ends and settle with a spring. Two small dots show where you are.
- The player / timer switch is one big button now — click anywhere on it.
- **Choose how big the panel opens** (Settings → Notch → Size, 75–115 %), with a live preview while you drag. The default is 10 % smaller than before.

## 0.6.0 — Its own repository
- Spindle now lives in its own repository and updates from it. Its companion menu bar manager, [Sleeve](https://github.com/zaineldinbarakat-droid/sleeve), has its own too; the two still work together.

## 0.5.0 — Lightweight, and genuinely clear glass
- **Very light:** idle, ~0.1 % CPU and 30 MB (it was using a third of a CPU core).
- The playing indicator and the spinning record run as Core Animation loops — no per-frame work in the app.
- Playback updates are event-driven (Spotify's and Music's own notifications) with a light re-sync poll.
- Liquid Glass is truly see-through at *Clear*, with Apple's lensing edges, fading to frosted.

## 0.4.2
- The focus phase is now called **Lock In**.

## 0.4.1
- No more album-colour glow or coloured edge behind the cover in the notch (optional *Glow behind the album cover* setting).
- A focus timer card on the full-screen turntable, with presets, pause, skip and reset; hide it with one click.

## 0.3.9
- The notch closes sooner after the cursor leaves.
- When Sleeve is running, Spindle's menu bar icon lands beside the other apps.

## 0.3.4 – 0.3.5
- Fixed a crash on next/previous track.
- An Apple-style notch: seamless black, smooth flared shoulders.
- Playing indicator options (style, colour, brightness, glow); Liquid Glass clarity slider; one-tap 25/5 ↔ 50/10 timer switch.

## 0.3.0 – 0.3.3
- Self-updating from this repository.
- Steady hover; the album cover and a *now playing* indicator in the closed notch; no album colour bleeding into the notch.

## 0.2
- Notch looks (Black, Song Color, Liquid Glass), the 50/10 timer preset, a smoother notch.
- Works alongside [Sleeve](https://github.com/zaineldinbarakat-droid/sleeve).

## 0.1
- A retro turntable in the MacBook notch for Spotify and Apple Music: spinning record, draggable tonearm, focus timer, desktop widgets, turntable wallpaper and full-screen mode.
