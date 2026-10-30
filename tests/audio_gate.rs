//! The audio authorization gate, probed and pinned (T16 plan §四-T1).
//!
//! Three facts this file establishes and then keeps true:
//!
//! 1. **Picker-side defaults.** `build_reflective_default` answers for the
//!    bevy audio components exactly as the plan v2 analysis predicted:
//!    `AudioPlayer` has no `ReflectDefault` and its `Handle` field defeats
//!    the field-walk fallback (so it never appears in Add Component), while
//!    `PlaybackSettings` and `SpatialListener` construct fine (so they do).
//! 2. **BSN apply shapes.** A full-value `AudioPlayer("path")` patch applies
//!    through the tuple-struct fallback (no `ReflectDefault` needed); a bare
//!    `AudioPlayer` line is refused with a warn; a partial `PlaybackSettings`
//!    patch seeds from its `ReflectDefault`. These pin the authoring forms
//!    the editor and the template teach.
//! 3. **Mix semantics** (an output device must exist — without one the
//!    engine builds no stream and no sink can appear, and the sink tests
//!    fail saying so rather than pass silently):
//!    a sink's volume equals `PlaybackSettings.volume × bus × master`, and
//!    a `GameAudioConfig` change re-applies to already-playing sinks — the
//!    "`GlobalVolume` does not affect already playing audio" gap the template's
//!    `apply_audio_mix` exists to close. The mirror math here is the spec the
//!    template implements; the fixture game (`tests/fixtures/bsn_game`)
//!    carries the same shape end-to-end through a real project build.
//!
//! ```text
//! cargo test --test audio_gate
//! ```

use std::any::TypeId;

use bevy::asset::{AssetPlugin, Assets, Handle};
use bevy::audio::{AudioPlugin, PlaybackMode, Volume};
use bevy::ecs::reflect::AppTypeRegistry;
use bevy::prelude::*;
use bevy::reflect::TypeRegistry;

use jackdaw::reflect_default::build_reflective_default;

// -- Shared helpers ---------------------------------------------------------

/// The app the apply probes run in: the minimal plugin set a scene load
/// needs (the loader test's construction), plus `AudioPlugin` so
/// `Handle<AudioSource>` resolves as a handle type. `AudioSource` itself
/// derives no `Reflect` and so never lands in the registry — the editor
/// names it specially (`typed_values`), which is part of what the gate pins.
fn probe_app() -> App {
    let mut app = App::new();
    app.add_plugins((
        bevy::app::TaskPoolPlugin::default(),
        AssetPlugin::default(),
        AudioPlugin::default(),
    ));
    {
        let registry = app.world().resource::<AppTypeRegistry>().clone();
        let mut registry = registry.write();
        registry.register::<Handle<AudioSource>>();
        registry.register::<AudioPlayer<AudioSource>>();
        registry.register::<PlaybackSettings>();
        registry.register::<SpatialListener>();
    }
    app.world_mut().init_resource::<jackdaw_bsn::SceneBsnAst>();
    app
}

/// A minimal but valid 16-bit mono PCM WAV file carrying `samples`.
fn wav_bytes(sample_rate: u32, samples: &[f32]) -> Vec<u8> {
    let data_len = samples.len() * 2;
    let mut out = Vec::with_capacity(44 + data_len);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&((36 + data_len) as u32).to_le_bytes());
    out.extend_from_slice(b"WAVE");
    out.extend_from_slice(b"fmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&1u16.to_le_bytes()); // PCM
    out.extend_from_slice(&1u16.to_le_bytes()); // mono
    out.extend_from_slice(&sample_rate.to_le_bytes());
    out.extend_from_slice(&(sample_rate * 2).to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&16u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&(data_len as u32).to_le_bytes());
    for sample in samples {
        out.extend_from_slice(&((sample.clamp(-1.0, 1.0) * 32767.0) as i16).to_le_bytes());
    }
    out
}

/// A quiet fraction of a second of sine, loud enough to decode, short enough
/// to finish within the drain loops below.
fn blip(sample_rate: u32, seconds: f32) -> Vec<u8> {
    let count = (sample_rate as f32 * seconds) as usize;
    let samples: Vec<f32> = (0..count)
        .map(|i| 0.5 * (2.0 * std::f32::consts::PI * 440.0 * i as f32 / sample_rate as f32).sin())
        .collect();
    wav_bytes(sample_rate, &samples)
}

/// The template's mix contract: what a sink on a bus should play at.
/// The same shape `apply_audio_mix` implements in the game template and the
/// fixture game mirrors; kept here as the unconditional spec.
fn effective_volume(
    base: f32,
    music_bus: bool,
    sfx_bus: bool,
    master: f32,
    music: f32,
    sfx: f32,
) -> f32 {
    let bus = if music_bus {
        music
    } else if sfx_bus {
        sfx
    } else {
        1.0
    };
    base * bus * master
}

// -- Probe 1: the picker-side default facts ---------------------------------

#[test]
fn audio_component_default_constructibility_matches_the_gate_analysis() {
    let mut registry = TypeRegistry::default();
    registry.register::<Handle<AudioSource>>();
    registry.register::<AudioPlayer<AudioSource>>();
    registry.register::<PlaybackSettings>();
    registry.register::<SpatialListener>();

    // `AudioPlayer` carries no `ReflectDefault`, and the field-walk fallback
    // cannot synthesise a `Handle` (opaque to the walker). This None is why
    // AudioPlayer never appears in Add Component, and why the template entity
    // is the main entrance (decision 1-A).
    let player = build_reflective_default(TypeId::of::<AudioPlayer<AudioSource>>(), &registry);
    assert!(
        player.is_none(),
        "AudioPlayer unexpectedly default-constructible; the picker analysis is stale"
    ); // The two audio components the picker CAN offer, today and after T16.
    let settings = build_reflective_default(TypeId::of::<PlaybackSettings>(), &registry);
    assert!(
        settings.is_some(),
        "PlaybackSettings must stay default-constructible for Add Component"
    );
    let listener = build_reflective_default(TypeId::of::<SpatialListener>(), &registry);
    assert!(
        listener.is_some(),
        "SpatialListener must stay default-constructible for Add Component"
    );
}

// -- Probe 2: the BSN apply shapes ------------------------------------------

#[test]
fn a_full_value_audio_player_patch_applies_without_reflect_default() {
    let mut app = probe_app();
    // The full generic type path, spelled out (the A8 discipline: bsn must
    // name a type exactly as its TypePath does, generic parameter included;
    // a short or re-exported path is silently another type).
    let text = r#"
        #Bgm
        bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>("sounds/probe.wav")
        bevy_audio::audio::PlaybackSettings {
            mode: bevy_audio::audio::PlaybackMode::Loop,
            volume: bevy_audio::volume::Volume::Linear(0.5),
        }
    "#;
    let loaded = jackdaw_bsn::load_bsn_scene(app.world_mut(), text)
        .expect("the full-value audio scene loads");
    assert_eq!(loaded.entities.len(), 1, "one entity spawned");
    let entity = loaded.entities[0];

    let world = app.world_mut();
    let player = world
        .get::<AudioPlayer<AudioSource>>(entity)
        .expect("AudioPlayer applied (tuple-struct fallback builds it without a Default)");
    assert_eq!(
        player
            .0
            .path()
            .map(bevy::asset::AssetPath::to_string)
            .as_deref(),
        Some("sounds/probe.wav"),
        "the handle resolves to the authored path",
    );

    let settings = world.get::<PlaybackSettings>(entity).unwrap();
    assert!(
        matches!(settings.mode, PlaybackMode::Loop),
        "mode applied: {:?}",
        settings.mode
    );
    assert!(
        (settings.volume.to_linear() - 0.5).abs() < 1e-6,
        "volume applied: {:?}",
        settings.volume
    );
}

#[test]
fn a_partial_playback_settings_patch_seeds_from_its_default() {
    let mut app = probe_app();
    let text = r#"
        #Sfx
        bevy_audio::audio::PlaybackSettings {
            mode: bevy_audio::audio::PlaybackMode::Despawn,
        }
    "#;
    let loaded =
        jackdaw_bsn::load_bsn_scene(app.world_mut(), text).expect("the partial scene loads");
    let entity = loaded.entities[0];
    let settings = app
        .world()
        .get::<PlaybackSettings>(entity)
        .expect("PlaybackSettings applied");
    assert!(matches!(settings.mode, PlaybackMode::Despawn));
    assert!(
        (settings.volume.to_linear() - 1.0).abs() < 1e-6,
        "fields the patch omits keep the type default: {:?}",
        settings.volume
    );
}

#[test]
fn a_bare_audio_player_line_is_refused_not_dropped_silently() {
    let mut app = probe_app();
    let text = r#"
        #Bare
        bevy_audio::audio::AudioPlayer
    "#;
    // The bare form names the type with no value: with no ReflectDefault the
    // apply warns and skips. That refusal is the teaching point — audio
    // authoring spells the full value — pinned here so a silent regression
    // (dropping the line without a warn) cannot come back.
    let loaded =
        jackdaw_bsn::load_bsn_scene(app.world_mut(), text).expect("the scene itself loads");
    let entity = loaded.entities[0];
    assert!(
        app.world()
            .get::<AudioPlayer<AudioSource>>(entity)
            .is_none(),
        "a bare AudioPlayer has no value to build and must not apply",
    );
}

// -- Probe 3: mix semantics on a live sink (device permitting) ---------------

/// The bus markers and config the sink tests route with — the same shape the
/// template ships as `MusicBus`/`SfxBus`/`GameAudioConfig`.
#[derive(Component, Default, Reflect)]
#[reflect(Component, Default)]
struct MusicBus;

#[derive(Component, Default, Reflect)]
#[reflect(Component, Default)]
struct SfxBus;

#[derive(Resource, Reflect, Default)]
#[reflect(Resource, Default)]
struct MixConfig {
    master: f32,
    music: f32,
    sfx: f32,
}

/// The template's `apply_audio_mix`, test-side: new sinks get
/// `base × bus × master`, and a config change re-applies to sinks already
/// playing (the gap `GlobalVolume` leaves).
fn apply_mix(
    config: Res<MixConfig>,
    plain: Query<
        (
            &PlaybackSettings,
            Option<&MusicBus>,
            Option<&SfxBus>,
            &mut AudioSink,
        ),
        Without<SpatialAudioSink>,
    >,
    spatial: Query<
        (
            &PlaybackSettings,
            Option<&MusicBus>,
            Option<&SfxBus>,
            &mut SpatialAudioSink,
        ),
        Without<AudioSink>,
    >,
) {
    for (settings, music, sfx, mut sink) in plain {
        let volume = effective_volume(
            settings.volume.to_linear(),
            music.is_some(),
            sfx.is_some(),
            config.master,
            config.music,
            config.sfx,
        );
        sink.set_volume(Volume::Linear(volume));
    }
    for (settings, music, sfx, mut sink) in spatial {
        let volume = effective_volume(
            settings.volume.to_linear(),
            music.is_some(),
            sfx.is_some(),
            config.master,
            config.music,
            config.sfx,
        );
        sink.set_volume(Volume::Linear(volume));
    }
}

/// Build the app the sink tests run in and put one WAV asset in the store.
/// Returns the app and the handle to play it with.
fn sink_app() -> (App, Handle<AudioSource>) {
    let mut app = App::new();
    app.add_plugins((
        MinimalPlugins,
        AssetPlugin::default(),
        AudioPlugin::default(),
    ))
    .init_asset::<AudioSource>()
    .init_resource::<MixConfig>()
    .add_systems(Update, apply_mix);
    let handle: Handle<AudioSource> = Handle::default();
    app.world_mut()
        .resource_mut::<Assets<AudioSource>>()
        .insert(
            &handle,
            AudioSource {
                bytes: blip(8_000, 0.25).into(),
            },
        )
        .expect("the probe WAV enters the empty store");
    (app, handle)
}

/// Whether this machine's audio stack produces sinks at all: a canary plays
/// and the test waits for its sink. A machine with no output device gives the
/// engine no stream, the queued-play system early-returns, and no sink ever
/// appears — the declared environment dependency of the sink facts below.
fn device_produces_sinks(app: &mut App, handle: &Handle<AudioSource>) -> bool {
    let canary = app
        .world_mut()
        .spawn((AudioPlayer(handle.clone()), PlaybackSettings::default()))
        .id();
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
    let mut produced = false;
    while std::time::Instant::now() < deadline {
        app.update();
        if app.world().get::<AudioSink>(canary).is_some() {
            produced = true;
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    if let Ok(entity) = app.world_mut().get_entity_mut(canary) {
        entity.despawn();
    }
    produced
}

#[test]
fn a_sink_receives_base_times_bus_times_master_and_follows_a_config_change() {
    let (mut app, handle) = sink_app();
    if !device_produces_sinks(&mut app, &handle) {
        // The declared environment dependency: a machine with no audio
        // output device has no sinks to read. Fail with the reason rather
        // than passing silently.
        panic!("no audio output device on this machine; sink facts undecidable");
    }
    app.world_mut().resource_mut::<MixConfig>().master = 0.5;
    app.world_mut().resource_mut::<MixConfig>().music = 0.8;
    let entity = app
        .world_mut()
        .spawn((
            AudioPlayer(handle),
            PlaybackSettings {
                volume: Volume::Linear(0.4),
                ..default()
            },
            MusicBus,
        ))
        .id();

    // The queued-play system builds the sink; the mix system then writes the
    // mix. A few frames for both to have run.
    for _ in 0..8 {
        app.update();
    }
    let world = app.world();
    let sink = world
        .get::<AudioSink>(entity)
        .expect("the engine built a sink for the playing entity");
    let expected = effective_volume(0.4, true, false, 0.5, 0.8, 1.0);
    assert!(
        (sink.volume().to_linear() - expected).abs() < 1e-4,
        "sink volume {} should be base 0.4 × music 0.8 × master 0.5 = {expected}",
        sink.volume().to_linear(),
    );
    assert!(!sink.empty(), "the sink is playing its clip");
    assert!(!sink.is_paused());

    // The re-apply: mutating the config reaches a sink that is already
    // playing — exactly what `GlobalVolume` does not do.
    app.world_mut().resource_mut::<MixConfig>().master = 0.0;
    app.update();
    app.update();
    let sink = app.world().get::<AudioSink>(entity).unwrap();
    assert!(
        sink.volume().to_linear().abs() < 1e-6,
        "master 0.0 silences an already-playing sink: {}",
        sink.volume().to_linear()
    );
}

#[test]
fn bus_routing_sends_each_sink_its_own_factor() {
    let (mut app, handle) = sink_app();
    if !device_produces_sinks(&mut app, &handle) {
        // The declared environment dependency: a machine with no audio
        // output device has no sinks to read. Fail with the reason rather
        // than passing silently.
        panic!("no audio output device on this machine; sink facts undecidable");
    }
    app.world_mut().resource_mut::<MixConfig>().master = 1.0;
    app.world_mut().resource_mut::<MixConfig>().music = 0.5;
    app.world_mut().resource_mut::<MixConfig>().sfx = 0.25;
    let music = app
        .world_mut()
        .spawn((
            AudioPlayer(handle.clone()),
            PlaybackSettings::default(),
            MusicBus,
        ))
        .id();
    let sfx = app
        .world_mut()
        .spawn((
            AudioPlayer(handle.clone()),
            PlaybackSettings::default(),
            SfxBus,
        ))
        .id();
    let plain = app
        .world_mut()
        .spawn((AudioPlayer(handle.clone()), PlaybackSettings::default()))
        .id();

    for _ in 0..8 {
        app.update();
    }
    let read = |world: &World, entity: Entity| {
        world
            .get::<AudioSink>(entity)
            .expect("sink built")
            .volume()
            .to_linear()
    };
    let world = app.world();
    assert!((read(world, music) - 0.5).abs() < 1e-4, "music bus 0.5");
    assert!((read(world, sfx) - 0.25).abs() < 1e-4, "sfx bus 0.25");
    assert!(
        (read(world, plain) - 1.0).abs() < 1e-4,
        "no bus rides master alone"
    );
}

#[test]
fn despawn_mode_removes_the_audio_entity_when_the_clip_ends() {
    let (mut app, handle) = sink_app();
    if !device_produces_sinks(&mut app, &handle) {
        // The declared environment dependency: a machine with no audio
        // output device has no sinks to read. Fail with the reason rather
        // than passing silently.
        panic!("no audio output device on this machine; sink facts undecidable");
    }
    // A 0.05 s clip in DESPAWN mode: the engine takes the entity down when
    // the sound finishes — the "stop" word's machine form for one-shots.
    app.world_mut()
        .resource_mut::<Assets<AudioSource>>()
        .insert(
            &handle,
            AudioSource {
                bytes: blip(8_000, 0.05).into(),
            },
        )
        .expect("the short clip replaces the store's only entry");
    let entity = app
        .world_mut()
        .spawn((AudioPlayer(handle), PlaybackSettings::DESPAWN, SfxBus))
        .id();

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while app.world().get_entity(entity).is_ok() && std::time::Instant::now() < deadline {
        app.update();
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert!(
        app.world().get_entity(entity).is_err(),
        "a DESPAWN one-shot takes its entity with it when the clip ends"
    );
}
