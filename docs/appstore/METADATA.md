# App Store Connect listing — eTeleprompter 1.0

Draft copy for the App Store Connect fields. Nothing here is submitted
automatically; paste what you want into App Store Connect yourself.

## Basics

| Field | Value |
|---|---|
| Name (30 char max) | `eTeleprompter — Teleprompter` (24) |
| Subtitle (30 char max) | `Read your script, on cue` (24) |
| Bundle ID | `com.iprompter.iPrompter` — must be registered to your team first |
| Primary category | Productivity |
| Secondary category | Photo & Video |
| Age rating | 4+ (no objectionable content, no web access, no user-generated sharing) |
| Price | (your call) |
| Devices | iPad only — `TARGETED_DEVICE_FAMILY = 2` |

## Promotional text (170 char max)

> A distraction-free teleprompter for iPad. Mount it on a mirror rig or read
> straight from the screen, at a speed you control to the point per second.

## Description

> eTeleprompter is a distraction-free teleprompter for presenters. Mount your iPad
> on a mirror rig or read straight from the screen, then scroll your script at
> a steady, controllable speed while you talk.
>
> It does one thing well: it puts your words in front of you and moves them at
> exactly the pace you want. No accounts, no cloud, no network — your scripts
> never leave your iPad.
>
> SMOOTH, PRECISE SCROLLING
> Speed is measured in points per second, from 10 to 300, adjustable by slider,
> by ten-point steps, or from a hardware keyboard. Every speed change eases in
> over a third of a second, so the text never jumps under your eye. Playback
> stops on its own when you reach the end.
>
> BUILT FOR MIRROR RIGS
> Flip the text horizontally, vertically, or rotate it to any right angle — in
> any combination, instantly, without interrupting playback. The controls stay
> the right way round, so you can still read them while the glass reads your
> script.
>
> A READING VIEW THAT SUITS YOUR EYES
> Five typefaces, 20 to 120 point, adjustable line spacing and margins, and
> eight text and background colours — white on black by default, the standard
> for mirror rigs.
>
> YOUR SCRIPTS, ORGANISED
> Write or paste scripts, sort them into folders, and search titles and content
> as you type. Every edit saves itself — there is no Save button. Each script
> shows its word count and estimated reading time.
>
> KEYBOARD CONTROL
> With a hardware keyboard: space to play or pause, arrow keys for speed, escape
> to exit.
>
> eTeleprompter works entirely offline. It collects no data, contains no ads, no
> tracking, no subscriptions and no account.

## Keywords (100 char max, comma-separated, no spaces)

```
teleprompter,prompter,script,speech,presentation,video,mirror,autocue,speaking,rehearse
```
(89 characters)

## URLs

- **Support URL** — REQUIRED. A page where users can reach you. The GitHub repo
  works if it is public: `https://github.com/hungnv26/eTeleprompter`
- **Privacy policy URL** — REQUIRED for every app, including offline ones. See
  `PRIVACY-POLICY.md` in this folder for text you can host (GitHub Pages, a
  gist, or your own site).
- **Marketing URL** — optional, leave blank.

## App Privacy questionnaire

Answer **"Data Not Collected"**. This is accurate and verifiable: the app has no
networking code of any kind, no analytics, no third-party SDKs, and no account
system. The only persistence is SwiftData on-device plus one UserDefaults key,
both declared in `eTeleprompter/PrivacyInfo.xcprivacy`.

## Export compliance

Already declared in the build: `ITSAppUsesNonExemptEncryption = NO`. You will
not be asked at upload time.

## Screenshots

13-inch iPad, 2064 x 2752 — the required size, in this folder:

1. `01-prompter-reading.png` — the reading view, mid-script, controls visible
2. `02-library-editor.png` — sidebar, script list and editor with live counts
3. `03-mirror-mode.png` — mirrored text with the controls still readable
4. `04-reading-settings.png` — the reading-settings panel over a live script

Apple accepts 1–10 per size class. If you add more, keep them all the same
orientation.

## Review notes (optional but helps)

> eTeleprompter is fully offline and needs no account or sign-in. To try the core
> feature: create a script with the + button, type or paste some text, tap
> "Start Prompter", then press play. Tap anywhere to bring the controls back
> while it scrolls.

## Before you ship

Nothing outstanding in the app itself. The reading-settings panel was rebuilt
(opaque backdrop, captioned slider rows) and is in screenshot 4.

What is left is all account-side: register the bundle id, create the App Store
Connect record, host the privacy policy and paste its URL in, then upload a
build with `tools-appstore-archive.sh`.
