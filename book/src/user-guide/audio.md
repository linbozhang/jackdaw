# Audio

Where [The Player Controller](player-controller.md) moves a body,
[Game Flow](game-flow.md) decides which world exists, and
[Game UI](game-ui.md) wires an interface, this chapter covers the
game's **sound**. Three sounds ship with the template — a looping
menu theme, a click each screen button acknowledges itself with, and
a spatial drone in the level — so a new project makes noise before
you have added a single file of your own.

The division of labor is strict: **the editor is the authoring
surface and never the speaker; the game is the speaker.** You attach
files, choose loop or one-shot, set volumes and buses in the editor,
then hear all of it in Play and in exported builds. This chapter
covers the authoring side, the template's three sounds, the three-way
mix, and the two ways a sound can fail to play.

## The editor is silent

A scene full of Audio Source entities, opened in the editor, makes no
sound — the editor process runs the audio engine with its global
volume pinned at zero. Your authored numbers are untouched by this:
a `PlaybackSettings` volume of 0.6 reads back 0.6 in the inspector,
saves as 0.6, and plays at 0.6 in the game. The pin lives in the
editor's own setup, not in your data.

This is deliberate. Sound belongs to the two places a player exists —
Play and the export — and pinning it in the editor also means opening
a scene never blasts a theme at you, and Play never doubles the sound
with a second voice from the editor's own world. The Audio Source
entities still show themselves: each draws a small wireframe marker in
the viewport, and the marker survives save and reopen (it is derived
from the entity's audio components, not stored in the document, so a
reloaded scene gets it back for free).

If you hear anything while only the editor is open — no Play, no
game process — that is a regression worth reporting.

## Adding a sound

**Add > Audio & Animation > Audio Source.** The entity that spawns is
a speaker from the first frame, not a bare marker: it carries the two
components that make sound happen —

* **`AudioPlayer`** — which file. Its one field is an asset handle;
  the inspector renders it as an asset row with **Pick** (lists every
  `.wav` and `.ogg` under `assets/`), **Browse** (the system file
  dialog), drag-and-drop from the Project window, and a typeable path;
  **Clear** empties it.
* **`PlaybackSettings`** — how it plays. The fields you author most:

| Field | Values | Meaning |
|---|---|---|
| `mode` | `Once`, `Loop`, `Despawn`, `Remove` | `Once` plays through and stops; `Loop` repeats forever; `Despawn`/`Remove` end with the sound taking the entity down with it — the one-shot lifecycle |
| `volume` | `Linear(f)` or `Decibels(db)` | the sound's authored base level; the mix multiplies it (below) |
| `spatial` | bool | pan the sound by distance and direction (needs a listener — below) |
| `speed` | f32 | playback rate multiplier |
| `paused` / `muted` | bool | start paused / start silent |

One entrance, deliberately: `AudioPlayer` is not in the Add Component
picker, because a file handle has no meaningful default an editor
could construct — the template entity (or your own code) is how an
`AudioPlayer` comes into the world. The picker's Audio section holds
what *is* default-constructible: the template's `MusicBus`/`SfxBus`
markers, and `PlaybackSettings`/`SpatialListener` appear too (under
their `bevy_audio` crate group), so a scene authored by hand can
attach settings, ears and buses around an `AudioPlayer` your code
spawns.

In a scene document the pair reads like this — note the full generic
path, which BSN requires (`AudioPlayer(...)` unqualified does not
resolve):

```bsn
#MenuBgm
bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/bgm.wav")
bevy_audio::audio::PlaybackSettings {
    mode: bevy_audio::audio::PlaybackMode::Loop,
    volume: bevy_audio::volume::Volume::Linear(0.6),
}
```

Save, reopen, and all of it comes back — the file, the settings, the
buses, the viewport marker. What does not come back is sound in the
editor, for the reason at the top of this chapter.

## The template's three sounds

| Sound | Lives in | Authored as |
|---|---|---|
| Menu theme | `assets/menu.bsn`, entity `#MenuBgm` | `bgm.wav`, `Loop`, `Linear(0.6)`, `MusicBus` |
| Button click | spawned by the game's code | `blip.wav`, `PlaybackSettings::DESPAWN`, `SfxBus` — one short entity per press that takes itself down when the sound ends |
| Level drone | `assets/scene.bsn`, entity `#Ambient` | `ambient.wav`, `Loop`, `Linear(0.8)`, `spatial: true`, positioned at (6, 2, −4) |

The menu theme and the level drone are scene entities, so their
lifespan is the document's: the theme exists only while the menu does,
the drone only while the level does — [Game Flow](game-flow.md)'s
document switching is the start/stop mechanism, and no code has to
fade anything in or out. That is also the "stop" story for looping
sounds: to stop one, stop hosting it (or flip `paused`/`muted` from
code); a one-shot stops itself, and `Despawn` mode deletes its entity
when done, which is exactly the shape the button click uses.

The drone is the spatial one, and spatial needs a listener: an
entity with a **`SpatialListener`** component defines the ears. The
template puts it on the player's camera rig
([The Player Controller](player-controller.md)'s follow camera), so
the drone pans against the player's position — walk away and it fades
and slides to one side. Bevy's spatial audio is **stereo panning by
distance and direction, not HRTF**; it sells direction and distance,
not around-the-head positioning.

## The three-way mix

Volume control is the config-asset pattern again
([Game Parameters](game-parameters.md)): a `GameAudioConfig` resource
with three numbers, authored as `assets/audio-config.bsn` through
**New Asset** (or by editing the file), and every sink's real volume
is derived from it:

```
effective volume = authored base × bus factor × master
```

* **`master`** multiplies every sound in the game.
* **`music`** multiplies every sound whose entity carries a
  **`MusicBus`** marker (the menu theme).
* **`sfx`** multiplies every sound whose entity carries an
  **`SfxBus`** marker (the button click).
* No marker — plain: master only (the level drone, which is world
  noise rather than music or feedback).

The markers are components in the Add Component picker's Audio
category, so routing a sound is an inspector checkbox, and a scene can
author them like any component. Until `audio-config.bsn` exists the
game runs with everything at full.

One engine quirk makes the mix a template feature rather than a
given: the engine reads the global volume exactly once, when it
creates a sink, and never follows a change. The template therefore
does the mixing itself — when the config changes, every sink's real
volume is rebuilt from `base × bus × master`, and a fresh sink is
corrected the frame it appears. The payoff: **edit
`audio-config.bsn` while the game runs and the already-playing sounds
follow** — set `master` to 0 and the theme silences mid-note.

While a sound plays, its entity grows a **`SoundLive`** component —
`kind` (`music`/`sfx`/`plain`), `volume` (the mixed value), `paused`,
`finished`, `position_secs` — refreshed every frame. The engine's
sink objects are not reflected, so this mirror is the one inspectable
audio surface: the Resources panel and a
[BRP query](remote-debugging.md) read it like any component, which
makes "is it actually playing, and at what volume" a checkable
question instead of a listenable guess.

A settings screen is the natural consumer of the same resource: its
sliders write `GameAudioConfig` (a resource is not a binding
*target*, so the write goes through a few lines of game code —
[Game UI](game-ui.md) has the binding kinds and their limits), and
the mix system does the rest. The template's pause screen is exactly
this, and the player's mix survives a restart: the save
([Game Saves](game-saves.md)) puts the changed values back over the
authored config on the next launch.

## Files and formats

Two formats are wired in, in the editor and in template games alike:

| Format | Extension | State |
|---|---|---|
| Ogg Vorbis | `.ogg` | plays |
| WAV (PCM) | `.wav` | plays |
| MP3 / FLAC | `.mp3` / `.flac` | **not enabled** — the asset picker won't offer them and the loader won't decode them; broader decode is future asset-import work |

The template's three sounds are generated `.wav` files under
`assets/sounds/` — replace them with your own, same names or new
paths via Pick.

## When a sound doesn't play

Two failure shapes, worth telling apart:

* **Missing file (silent).** A handle naming a file that isn't there
  is *quiet, not loud*: the entity sits in the scene fully authored,
  no sink ever appears, no crash — the only trace is a load warning
  in the game's log naming the path. If a sound you know you authored
  isn't playing, suspect the path first, and let the picker do the
  pointing instead of typing it.
* **Broken file (loud).** A file whose extension promises a format
  the bytes don't deliver crashes the process at decode. Keep real
  files under real names; forgiving decode is future asset-import
  work.

The 30-second version: point the menu theme at `sounds/missing.wav`,
Save, Play — the menu runs silent and the log names the path; point
it back at `sounds/bgm.wav` — the music returns.

## The 30-second check

1. Device precheck: `afplay assets/sounds/blip.wav` — hear a blip.
2. New project, `cargo run`: the menu theme loops. Click **Start**:
   a click, then the level drone, which pans as you walk
   ([Game Input](game-input.md) moves the body).
3. Edit `assets/audio-config.bsn`: `music: 0.5` → theme quieter;
   `master: 0.0` → everything silent, mid-note; restore.
4. Export the game: the exported build sounds the same as Play.
5. Open the editor and browse the scene with the theme in it:
   silence. The editor is never the speaker.
