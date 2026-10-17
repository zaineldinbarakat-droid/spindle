<p align="center">
  <img src="../../Packaging/Spindle-icon.png" width="120" alt="Spindle icon">
</p>

<h1 align="center">Spindle</h1>

<p align="center">
  <b>A retro turntable that lives in your MacBook's notch.</b><br>
  For Spotify and Apple Music · with a built-in focus timer.<br>
  <sub>Made to work hand in hand with <a href="../Sleeve/README.md">Sleeve</a> — and just as happy on its own.</sub>
</p>

<p align="center">
  <a href="https://github.com/zaineldinbarakat-droid/spindle-and-sleeve/releases/latest/download/Spindle.zip"><b>⬇︎ Download Spindle</b></a>
  &nbsp;·&nbsp; macOS 14+ · Apple Silicon
</p>

<p align="center">
  <img src="../../docs/images/spindle-notch.png" alt="Spindle's notch panel open, showing album art, track details, a progress bar and playback controls">
</p>

## What it does

- **A turntable in the notch.** Hover the notch and a panel springs out of it, Dynamic-Island style, and tucks back the moment you move away. Show the song as a **spinning vinyl record** — cover art pressed into the label, a tonearm that tracks the playhead — or as the **album cover**.
- **Drag the tonearm to scrub.** The arm's angle maps exactly to the playhead and back, so you can drop the needle anywhere in the song. A progress bar and play / pause / skip sit beside it.
- **One click to the source.** Click the cover, the record or the title and Spotify or Music comes to the front.
- **Closed, it's a quiet pill.** The cover on the left of the notch, a *now playing* indicator on the right — bars, a wave or a pulse, in the album's colour, white or any colour, with adjustable brightness and glow.

  <img src="../../docs/images/spindle-collapsed.png" alt="The closed notch: a small album cover on the left and glowing bars on the right">

- **Three looks.** *Black* (seamless with the hardware notch), *Song Color* (the panel takes on the album's colour) and **Liquid Glass** with a Clarity slider — from genuinely see-through glass that bends the light at its edges to fully frosted.

  <img src="../../docs/images/spindle-liquid-glass.png" alt="The notch panel in clear Liquid Glass over a colourful wallpaper">

- **Focus timer — "Lock In".** Pomodoro cycles with a one-tap 25 / 5 ↔ 50 / 10 switch, long breaks, a countdown in the closed notch, notifications, and optional pause-the-music-on-breaks.
- **Desktop widgets and a full-screen turntable.** Live *Record* and *Turntable* widgets, an optional animated wallpaper, and a full-screen scene with the timer beside the song.

  <img src="../../docs/images/spindle-fullscreen.jpg" alt="The full-screen turntable scene with a focus timer">

- **Light.** Idle, about 0.1 % CPU and 30 MB. The indicator and the spinning record are Core Animation loops, so playing music costs Spindle next to nothing.

## Made to work with Sleeve

Spindle and [**Sleeve**](../Sleeve/README.md) (the menu bar manager) were built as a pair and talk to each other directly:

- **They share the top of the screen politely.** Spindle tells Sleeve exactly where its notch pill and panel are, and Sleeve keeps its hover-to-reveal zone and menu bar colouring out of that area — so hovering the notch opens Spindle, never your hidden menu bar apps.
- **One dropdown at a time.** Opening Spindle's panel closes Sleeve's, and the other way round.
- **Zen mode covers both.** Sleeve's Zen mode can hide Spindle's pill too, for a completely clean top edge.
- **The menu bar can match the music.** Sleeve's *Album* colour tints the menu bar with the song playing in Spindle.
- **Tidy icons.** When Spindle starts, it lets Sleeve know first, so its menu bar icon lands next to your other apps.

Each app works fully on its own; together they feel like one.

## Install

1. [Download **Spindle.zip**](https://github.com/zaineldinbarakat-droid/spindle-and-sleeve/releases/latest/download/Spindle.zip), unzip it and drag **Spindle** into **Applications**.
2. Spindle isn't notarized yet, so the first launch is blocked: open **System Settings → Privacy & Security** and click **Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/Spindle.app`).
3. Allow Spindle to control **Music** and/or **Spotify** when asked — that's how it reads and controls playback.

Spindle updates itself from this repository.

## Privacy

No account, no API key, no tracking. Spindle talks only to the music apps running on your Mac (over Apple Events), fetches Spotify's cover art, and checks this repository for updates. Nothing about what you listen to leaves your Mac.

---

<p align="center"><sub><a href="../../README.md">← Back to Spindle &amp; Sleeve</a> · Built by <a href="https://github.com/zaineldinbarakat-droid">Zaineldein Barakat</a> · <a href="../../LICENSE">MIT License</a></sub></p>
