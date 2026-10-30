//! End-to-end proof game: a real project library that loads an authored
//! `.bsn` scene at runtime through `JackdawPlugin`.
//!
//! `GamePlugin` spawns a `JackdawSceneRoot` pointing at `assets/scene.bsn`
//! at startup; `JackdawPlugin` (added from `main`) then parses that file
//! and spawns its entities. An update system watches for the authored
//! marker entity (`SceneNodeId(999)`) and, once it appears, prints a
//! unique stderr line carrying real counts read out of the live world.
//!
//! T16: the scene also carries a `Bgm Probe` entity — an `AudioPlayer`
//! naming `sounds/probe.wav` on the music bus — and the game builds the
//! template's three-way mix around it. Once the entity's `SoundLive`
//! mirror reports a playing sink, a second stderr line carries the mixed
//! volume, so the real-pipeline proof covers audio too.

use bevy::audio::Volume;
use bevy::prelude::*;
use jackdaw_runtime::prelude::*;
use jackdaw_scene_types::{SceneNodeId, types::ScatterGroup};

/// The mix the probe reads back: master × music = 0.5 × 0.8, times the
/// scene entity's authored base 0.4, lands at 0.16.
#[derive(Asset, Resource, Reflect, Clone, Default)]
#[reflect(Resource, Default)]
pub struct GameAudioConfig {
    pub master: f32,
    pub music: f32,
    pub sfx: f32,
}

/// The bus markers and mirror, the same shape the template ships.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
pub struct MusicBus;

#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
pub struct SfxBus;

#[derive(Component, Reflect, Clone, Default)]
#[reflect(Component, Default)]
pub struct SoundLive {
    pub kind: String,
    pub volume: f32,
    pub paused: bool,
    pub finished: bool,
    pub position_secs: f32,
}

fn mix_volume(base: f32, music: bool, sfx: bool, config: &GameAudioConfig) -> f32 {
    let bus = if music {
        config.music
    } else if sfx {
        config.sfx
    } else {
        1.0
    };
    base * bus * config.master
}

fn apply_audio_mix(
    config: Res<GameAudioConfig>,
    plain: Query<
        (
            &PlaybackSettings,
            Option<&MusicBus>,
            Option<&SfxBus>,
            &mut AudioSink,
        ),
        Without<SpatialAudioSink>,
    >,
) {
    if !config.is_changed() {
        return;
    }
    for (settings, music, sfx, mut sink) in plain {
        let volume = mix_volume(
            settings.volume.to_linear(),
            music.is_some(),
            sfx.is_some(),
            &config,
        );
        sink.set_volume(Volume::Linear(volume));
    }
}

fn apply_audio_mix_to_new_sinks(
    config: Res<GameAudioConfig>,
    plain: Query<
        (
            &PlaybackSettings,
            Option<&MusicBus>,
            Option<&SfxBus>,
            &mut AudioSink,
        ),
        (Added<AudioSink>, Without<SpatialAudioSink>),
    >,
) {
    for (settings, music, sfx, mut sink) in plain {
        let volume = mix_volume(
            settings.volume.to_linear(),
            music.is_some(),
            sfx.is_some(),
            &config,
        );
        sink.set_volume(Volume::Linear(volume));
    }
}

fn mirror_sound_live(
    mut commands: Commands,
    plain: Query<
        (Entity, &AudioSink, Option<&MusicBus>, Option<&SfxBus>),
        Without<SpatialAudioSink>,
    >,
    mut live: Query<&mut SoundLive>,
) {
    for (entity, sink, music, sfx) in plain {
        let kind = if music.is_some() {
            "music"
        } else if sfx.is_some() {
            "sfx"
        } else {
            "plain"
        };
        let value = SoundLive {
            kind: kind.to_string(),
            volume: sink.volume().to_linear(),
            paused: sink.is_paused(),
            finished: sink.empty(),
            position_secs: sink.position().as_secs_f32(),
        };
        match live.get_mut(entity) {
            Ok(mut slot) => *slot = value,
            Err(_) => {
                commands.entity(entity).insert(value);
            }
        }
    }
}

/// A minimal editor extension type kept in this fixture for
/// `jackdaw_extension` API surface coverage beside the game plugin.
#[derive(Default)]
pub struct BundleFixtureExtension;

impl jackdaw_extension::JackdawExtension for BundleFixtureExtension {
    fn id(&self) -> String {
        "bundle_fixture".to_string()
    }

    fn register(&self, _ctx: &mut jackdaw_extension::ExtensionRegistrar<'_>) {}
}

#[derive(Default)]
pub struct GamePlugin;

impl Plugin for GamePlugin {
    fn build(&self, app: &mut App) {
        app.init_asset::<GameAudioConfig>()
            // `AudioPlayer` is generic, and the reflect derive's automatic
            // registration skips generic types: the scene's audio entity
            // only applies with this line.
            .register_type::<AudioPlayer<AudioSource>>()
            .insert_resource(GameAudioConfig {
                master: 0.5,
                music: 0.8,
                sfx: 1.0,
            })
            .add_systems(Startup, spawn_scene)
            .add_systems(
                Update,
                (
                    // Chained: a fresh sink gets the mix before the mirror
                    // reads it, so the reported volume is never the raw base.
                    // Tuple order alone is not execution order.
                    (
                        apply_audio_mix,
                        apply_audio_mix_to_new_sinks,
                        mirror_sound_live,
                    )
                        .chain(),
                    report_scene_loaded,
                    report_sound_live,
                ),
            );
    }
}

/// Load the authored scene. `JackdawPlugin` spawns its entities as children
/// of this root once the async asset load completes.
fn spawn_scene(mut commands: Commands, asset_server: Res<AssetServer>) {
    commands.spawn(JackdawSceneRoot(asset_server.load("scene.bsn")));
    eprintln!("BSN_GAME_STARTED");
}

/// The authored entity to wait for. Defaults to the committed fixture scene's
/// marker; callers that author their own scene (the editor journey) pass the
/// id the editor minted for theirs.
fn target_node_id() -> u64 {
    std::env::var("JACKDAW_E2E_NODE_ID")
        .ok()
        .and_then(|raw| raw.parse().ok())
        .unwrap_or(999)
}

/// Once the authored marker entity has spawned from the `.bsn`, emit a single
/// unique line with counts taken from the live world. Waiting on a specific id
/// rather than "any entity" avoids reporting a half-spawned scene.
fn report_scene_loaded(
    mut done: Local<bool>,
    node_ids: Query<&SceneNodeId>,
    names: Query<&Name>,
    transforms: Query<Entity, With<Transform>>,
    scatter_groups: Query<&ScatterGroup>,
) {
    if *done {
        return;
    }
    let ids: Vec<u64> = node_ids.iter().map(|n| n.0).collect();
    let target = target_node_id();
    // Wait until the specific authored entity from the scene file exists.
    if !ids.contains(&target) {
        return;
    }
    let names: Vec<String> = names.iter().map(|n| n.as_str().to_owned()).collect();
    // Scatter provenance is scene data, so a runtime that cannot apply it
    // loads the scene with the groups stripped back to bare models. The
    // keys are reported so the test reads what arrived rather than what
    // failed to be complained about.
    let scatter: Vec<String> = scatter_groups
        .iter()
        .map(|group| group.key.clone())
        .collect();
    eprintln!(
        "BSN_SCENE_LOADED entities={} node_ids={} target={} has_target={} ids={:?} names={:?} \
         scatter_keys={:?}",
        transforms.iter().count(),
        ids.len(),
        target,
        ids.contains(&target),
        ids,
        names,
        scatter,
    );
    *done = true;
}

/// Once the scene's audio entity is playing, print its mirrored state once:
/// the engine-level proof that BSN-loaded audio reaches a real sink at the
/// mixed volume. The `audio:` prefix keeps the line greppable beside the
/// other markers.
fn report_sound_live(mut done: Local<bool>, live: Query<&SoundLive>) {
    if *done {
        return;
    }
    for sound in &live {
        if sound.finished || sound.volume <= 0.0 {
            continue;
        }
        eprintln!(
            "AUDIO_SINK_LIVE kind={} volume={:.3} paused={} finished={} position={:.2}",
            sound.kind, sound.volume, sound.paused, sound.finished, sound.position_secs,
        );
        *done = true;
        return;
    }
}
