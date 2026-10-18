# Sorae

A soundscape you **build**, not one you pick.

Five environmental layers — rain, wind, birds, river, campfire — on a vertical mixing
desk, each raised and lowered until the room sounds the way you need it to. A sugar
glider called Sorae reads the mix and cools from overwhelmed to calm as it fills out,
which is what turns setting volumes into something with a point.

iOS · SwiftUI · AVAudioEngine · no third-party dependencies.

> **Status:** working prototype, pre-validation. The audio is real and measured; the
> premise — that people would rather build a mix than choose one — has not been tested
> with anyone outside the project. See [Known gaps](#known-gaps).

---

## Requirements

| | |
|---|---|
| Xcode | 26.6 or later |
| iOS deployment target | 26.5 |
| Swift | 5.0 language mode, MainActor default isolation |
| Dependencies | none |

## Running it

```bash
git clone <your-remote> Sorae
cd Sorae
open Sorae.xcodeproj
```

Pick an iPhone simulator and run. There is nothing to install and no configuration
step. To run on a device, set your own team under **Signing & Capabilities** for both
targets and change the bundle identifiers — the app is `com.mufiiin.Sorae` and the
widget must stay prefixed by it (`com.mufiiin.Sorae.SoraeWidgets`).

Two capabilities are already declared and matter if you touch the project settings:
**Background Modes → Audio** (a sleep app that stops when you lock the phone is not a
sleep app) and **Live Activities**.

## Targets

| Target | What it is |
|---|---|
| `Sorae` | The app. |
| `SoraeWidgets` | Widget extension, hosting only the Live Activity. Embedded in the app. |
| `Shared/` | Compiled into both. Currently one file: the Live Activity's data contract. |

## Project structure

```
Sorae/
  Design/       Palette, typography, motion, haptics — the whole visual system
  Model/        SoundChannel, SoundCatalog, Soundscape, CalmEvaluator
  Audio/        The engine. See below.
  State/        MixerModel, SoundscapeStore, SessionActivityController
  Components/   Mascot, faders, particles, cards
  Features/     Home · Mix · Explore · Library · Session · Onboarding
  Debug/        Launch hooks and the audio probe. #if DEBUG only.
SoraeWidgets/   Live Activity + its own asset catalog
Shared/         Types both targets need
```

## How the audio works

Everything the interface says to the audio layer is one call: `setIntensity(_:)`.
How a sound turns "how present should this feel" into gain, tone and space is the
layer's business, described by an `AmbientIntensityProfile`.

```
AVAudioPlayerNode
  → AVAudioUnitEQ        makeup gain + three gentle tone bands
  → width stage          optional; only sounds that ask for one build it
  → AVAudioUnitReverb    a hint of space
  → peak limiter         protection, not an effect
  → gain mixer           the intensity curve
  → main mixer
```

Two orderings matter. The **gain mixer is last**, so returning to zero takes the reverb
tail down with the source rather than leaving it ringing. The **limiter sits before it**,
so it always sees the same calibrated signal — after the gain it would engage only at
the top of the fader and the sound's character would change as you moved it.

**Recordings are calibrated, not hand-tuned.** Each layer measures its own source once at
load (RMS, plus a percentile peak from a histogram) and derives makeup gain from the
profile's targets. Drop in a new recording at any level and it lands at a sensible one.

**Loops are prepared, not assumed.** Where a profile asks for it, the tail is
equal-power crossfaded over the head, any head-to-tail tilt is ramped out, and the
join position is chosen by searching for the calmest spot — for intermittent sounds
like birds, one that also falls in a gap between calls.

### Adding a sixth sound

1. Drop the audio in as a **data set** in `Assets.xcassets`.
2. Add one entry to `SoundCatalog.channels` with its `audioResource`.
3. Give it an `AmbientIntensityProfile` and route it in
   `AmbientIntensityProfile.profile(for:)`.

No view changes. The mixing desk reads the catalog and switches to horizontal
scrolling past five layers on its own.

## Verifying the audio

The app carries an offline harness that renders the real audio graph through
`AVAudioEngine`'s manual rendering mode and measures it, so the sound can be checked
without anyone having to listen and guess:

```bash
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted /path/to/Sorae.app
SIMCTL_CHILD_SORAE_AUDIO_PROBE=1 \
  xcrun simctl launch --console-pty booted com.mufiiin.Sorae
```

It reports, per sound: source statistics and the makeup gain derived from them, output
level and peak at nine intensities, band tilt, dynamic range, the largest step the gain
ramp takes per frame, whether the loop join is distinguishable from ordinary variation,
and whether zero is bit-exact silence. Then it checks all five together — that they sum
as independent sources and that moving one leaves the others' gains bit-identical.

It has caught real bugs: a cold start whose fade ran to completion while the file was
still loading, and a pause that left the player stopped but the level set, so the next
play was silent.

There is a second, faster check for the session timer:

```bash
SIMCTL_CHILD_SORAE_TIMER_CHECK=1 \
  xcrun simctl launch --console-pty booted com.mufiiin.Sorae
```

## Debug launch options

`#if DEBUG` only, read from the environment. Pass them through `simctl` with the
`SIMCTL_CHILD_` prefix, or add them to the scheme in Xcode.

| Variable | Effect |
|---|---|
| `SORAE_TAB` | `home` · `mix` · `explore` · `library` — open on a tab |
| `SORAE_MIX` | `rain:0.8,river:0.5,campfire:0.3` — start with a mix playing |
| `SORAE_TIMER` | Seconds. A short session timer, for watching one end |
| `SORAE_SESSION` | `1` — open the full-screen session with a 10-minute timer |
| `SORAE_SHEET` | `save` · `detail` — open a sheet that needs a tap to reach |
| `SORAE_SEED` | `1` — seed a couple of saved mixes |
| `SORAE_ONBOARDING` | `1` · `0` — force or suppress the first-run tour |
| `SORAE_ONB_STEP` | Step number, 1-based — open the tour partway through |
| `SORAE_AUDIO_PROBE` | `1` — run the offline audio measurements |
| `SORAE_TIMER_CHECK` | `1` — assert the session timer's pause behaviour |

```bash
SIMCTL_CHILD_SORAE_TAB=mix SIMCTL_CHILD_SORAE_MIX=rain:0.6,campfire:0.4 \
  xcrun simctl launch booted com.mufiiin.Sorae
```

## Live Activity

Playback continues when the app is minimised, and a Live Activity appears in the
Dynamic Island: the mascot on the left, a countdown or `∞` on the right. Both states
occupy the same width, so setting a timer does not change the island's length.

The countdown carries the session's **end date**, not seconds remaining, and is drawn
with `Text(timerInterval:)` — so it ticks accurately with the app suspended and the app
pushes one update per session rather than one per second.

It exists only while audio is actually playing. Minimising a silent app shows nothing,
and stopping playback removes it immediately, including when a timer expires while the
app is suspended.

To see it in the simulator, start audio, then foreground another app:

```bash
SIMCTL_CHILD_SORAE_MIX=rain:0.6 xcrun simctl launch booted com.mufiiin.Sorae
xcrun simctl launch booted com.apple.Preferences   # backgrounds Sorae
```

The tour runs once on a fresh install and can be replayed at any time from the `?`
button on Home. It remembers itself in a file in the app's container rather than in
`UserDefaults` — the preferences daemon caches a domain in memory and writes it back
after the app is deleted, which left reinstalls with no tour.

## Known gaps

Honest list, in rough order of how much they matter.

- **No lock-screen transport.** Background audio ships, but `MPNowPlayingInfoCenter`
  and `MPRemoteCommandCenter` were never wired up — so audio can be started, the phone
  locked, and there is no way to stop it without unlocking and finding the app.
- **No analytics.** Nothing is instrumented, so none of the product's success metrics
  can currently be measured.
- **Saved mixes are local only.** A JSON file in Application Support. Deleting the app
  destroys everything the user made; there is no backup or sync.
- **iPad is unlaid-out.** The target allows it and it runs, but nothing has been
  designed for the size. Either lay it out or restrict to iPhone.
- **Wind loops every 5 seconds.** The recording is 5.9 s. The join is prepared and
  inaudible, but nothing hides a five-second period from someone lying awake. A
  20–30 second bed is the single biggest quality win available.
- **The river recording is mono** (channels 98% correlated), so it sits as a point in
  the middle of the listener's head. Processing cannot substitute for a stereo take.
- **`soraeconcept.png` is dead weight** — 1.5 MB of original concept art compiled into
  the app and never displayed. Same for the app target's copy of `DyImg1`, which the
  widget carries its own copy of.
- **Audio ships as uncompressed WAV** — 40 MB of the repo and of the app binary.
  Compressed loops would cut that by roughly an order of magnitude.

## Assets

The mascot artwork, environment banners and audio recordings are **not covered by the
code licence**. Do not reuse them without permission.

## Licence

TODO — pick one before making the repository public. Note the split above: whatever
licence covers the code should not be read as covering the artwork or the recordings.
