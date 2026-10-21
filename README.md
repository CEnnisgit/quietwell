# Quietwell

White noise machine for iPhone from Nimbus Web Design. Every sound is synthesized live on the
device with AVAudioEngine (`AVAudioSourceNode`); there are no bundled audio files, no network
calls, no account, no ads and no third-party analytics or packages.

Generated from [appkit-template](https://github.com/CEnnisgit/appkit-template) with
`scripts/new-app.sh Quietwell quietwell`.

> **Brand and bundle ID may change.** `com.nimbuswebdesign.quietwell` (and the
> `com.nimbuswebdesign.quietwell.pro.*` product IDs) are placeholders under Nimbus Web Design
> until the new LLC and Apple developer account exist. Rename in `project.yml`,
> `Quietwell/App/AppConfig.swift`, `Quietwell.storekit` and the workflow's `BUNDLE_ID`.

## Sounds

| Sound | Tier | How it's made |
|---|---|---|
| White noise | Free | xorshift32 uniform noise, optional low-pass "tone" |
| Pink noise | Free | Paul Kellet pink filter (-3 dB/oct) |
| Brown noise | Free | Leaky integrator (-6 dB/oct); tone low-pass makes it deeper |
| Fan | Free | Low-passed pink + brown air with blade-rate flutter (speed = intensity) |
| Rain | Free | High-passed pink hiss plus random band-passed droplets (density = intensity) |
| Green noise | Pro | Band-passed pink noise centred 250 Hz–1 kHz |
| Ocean | Pro | Brown/pink surf under a slow wave envelope |
| Thunder | Pro | Low brown rumble with randomly timed long rolls |
| Low hum | Pro | 40–80 Hz fundamental and harmonics with slow wobble |

DSP lives in `Quietwell/Audio/Synth.swift` (value types, no allocation on the audio thread).
`VoiceBank` mixes up to four layers with smoothed volume and master gain; `SoundEngine` owns the
engine, the timer, Now Playing and remote commands.

## Free vs Pro (from apps/sleep listing)

- **Free, no time limit:** white, pink and brown noise, fan and rain (one at a time), tone and
  intensity controls, sleep timer with fade-out, Lock Screen controls.
- **Quietwell Pro:** mix up to four sounds, ocean / thunder / green noise / low hum, saved mixes.
- **Prices (US):** Monthly $2.99, Yearly $12.99 (default, no trial), Lifetime $19.99 one-time.
  No weekly plan. Products: `com.nimbuswebdesign.quietwell.pro.monthly`, `.pro.yearly`
  (auto-renewing, one group) and `.pro.lifetime` (non-consumable).

## Playback

- Sleep timer: 15 min to 8 hours or all night; the last quarter (max 5 min) fades out on an
  equal-power curve, then the audio engine stops and the audio session is deactivated. Nothing
  keeps running in the background after the timer ends.
- `UIBackgroundModes: audio` + `AVAudioSession` `.playback` keeps the sound going with the screen
  off; `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` give Lock Screen / Control Center
  play, pause and toggle.

## Icon

`AppIcon-1024.png` comes from `apps/sleep/design/icon-1024.png` (1024x1024 RGB, no alpha).

## Build

```sh
brew install xcodegen && xcodegen generate && open Quietwell.xcodeproj
```

## Tests

`QuietwellTests/SynthTests.swift` measures spectral slope with a Hann-windowed Goertzel filter
(white ≈ 0, pink ≈ -1, brown ≈ -2 on log-power vs log-frequency), checks tone shaping, bounds,
determinism, the free-tier split and the voice mixer; plus sleep-timer and saved-mix
tests. Template tests cover product IDs, entitlement logic and the on-device counter.

## Screenshot hooks / CI

`-AppScreen home|mix|timer|onboarding|paywall|settings` (`-AppPro YES` forces Pro). The
`sim-proof` workflow (pushes to `feat/**` or manual) builds, tests and captures all six at
1320x2868 into the `sim-proof` artifact.

## Review notes

See `/workspace/apps/sleep/review-notes.txt`. Privacy: https://cennisgit.github.io/app-pages/apps/quietwell/privacy/ · Support: https://cennisgit.github.io/app-pages/apps/quietwell/support/. Privacy label: Data Not Collected. No health or
medical claims.
