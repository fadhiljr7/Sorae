# Sorae — launch film plan (55s, 1920×1080, 30fps)

Reference: Muse launch film (Meta). Borrowed grammar, not content: icon→object-grid pull-out
opener with radial burst, kinetic sentences with art popping in *between* words, floating
UI (no phone frames) with camera push-ins, slot-machine word swaps, a celebration beat, a
dense object grid reprise, and a dark end card.

## The rubric
- **What:** an iOS soundscape app where you build the mix yourself — rain, wind, birds,
  river, campfire on a vertical mixing desk.
- **For whom:** anyone who needs the room to sound right to sleep, focus or calm down.
- **What sets it apart:** Sorae, a sugar glider who reads your mix. Silence leaves her
  overwhelmed (red island, papers flying); as you layer sound she cools to serene (ice island).
  The whole UI tints ember → sky with her.
- **Most impressive claim:** the mascot is driven by a real calm score — not decoration.
- **Visual hook:** the app icon swallowed by a flood of Sorae stickers / sound icons, then a burst.
- **Real UI to show:** the Mix desk (5 faders + calm meter), Explore's featured card, the
  full-screen Session with CalmRing + timer, the Live Activity.
- **Tone:** freeform — "Muse-grade Apple launch film", airy, white + sky, playful but precise.
- **Caption:** "Sorae is out on the App Store. Build a soundscape, calm a sugar glider."

## Identity (from the code)
- Canvas `#FFFFFF` / tint `#F6FAFF`, well `#EEF4FC`, ink `#0F1B2A`, inkSoft `#5B6D82`
- Sky `#4C9AF0`, skyDeep `#2A6DBF`, skySoft `#C7E0FA`, skyMist `#E8F2FE`
- Ember `#EF4A3C`, emberSoft `#FFDCD6`; dark canvas `#0B1017`
- Channel tints: rain `#5A9BE8`, wind `#7FB6E9`, birds `#6FC5C0`, river `#4FA9D8`, campfire `#F0954E`
- Type: SF Pro Rounded (the app's display face), real SF Symbols
- Motion: long low-bounce springs ("breathing, not reacting")

## Calm math (real `CalmEvaluator`)
rain .70 → 19% restless · +river .50 → 44% settling · +wind .40 → 65% calm ·
+campfire .45 → 88% **serene** (pose swaps to resting above 0.86). Every number on screen is
what the app would show.

## Storyboard (video time; music = vol-10 offset 4.37s, groove lands 13.64, gap 29.47, break 39.28, drop 41.45)
| # | Time | Scene | Notes |
|---|---|---|---|
| 1 | 0.0–3.0 | **Hook.** App icon alone → stickers, SF-symbol sound chips, scene cards and snowflakes fly in; camera pulls out to a dense floating grid; radial zoom-burst to white. | whoosh build → soft impact on 3.0 |
| 2 | 3.0–5.6 | "Introducing" (blur→ink) / "Sorae" (sky) rises beneath. | |
| 3 | 5.6–9.4 | "Sorae [sticker] is a / soundscape [rain chip] you / [fader chip] build." — art pops in as words make room. Words scatter out. | pops on beats |
| 4 | 9.4–11.6 | Canvas warms to ember mist. "Your world is **loud.**" with Sorae's tremor. | |
| 5 | 11.6–23.0 | **Demo — the desk.** Overwhelmed island pops in with status pill → morphs into the real Mix state card + 5 faders. Rain 70 / River 50 / Wind 40 / Campfire 45 rise on the downbeats (13.64, 15.82, 18.00, 20.19) with touch dot + value chip; calm meter, mood copy, mascot art, aura and background all move with the real score. Each layer's **real recording** fades in; music low-passes as the world quiets. Push-in on serene Sorae: "❄ Serene." | music muffles to near-silence at 21.3, snaps back 22.9 |
| 6 | 23.0–29.5 | Slot machine: "Five layers. / [chip] rain on the window → wind in the pines → birds, far away → a river over stones → a fire, crackling low / Yours to mix." Each slot solos its real recording. | swaps every 2 beats |
| 7 | 29.5–39.3 | **Demo — places.** Explore cards glide past in perspective → Rainy Night expands full-bleed (real art, Ken Burns, rain) → layer chips (85/35/20) → Session: CalmRing + countdown → lock: Dynamic Island + Lock Screen Live Activity, "Keeps playing when you lock your phone." | hush in the 29.47 gap |
| 8 | 39.3–44.0 | Breakdown: "Your world is loud." reprise → on the drop it cools: "Sorae [cheering sticker] makes / it [❄] gentle." + snowflake burst. | the celebration beat |
| 9 | 44.0–48.0 | Object grid returns, centre text "Find your quiet." | real Home copy |
| 10 | 48.0–55.0 | Icon + "Sorae" + tagline on sky; dims to night (dark canvas, sky glow); **Download on the App Store** badge. | outro, final hit ~54.6 |

## Sound
Bundled "Happy Beats vol 10" (110 BPM) as the bed; Sorae's own five WAV recordings as
the instrument of the demo; soft UI ticks/whooshes kept under the music. One mix: music
ducks and low-passes while nature rises, so the "world gets gentle" is heard, not told.
