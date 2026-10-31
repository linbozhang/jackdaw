//! The Viewport section of the Graphics panel is editor preference, and the
//! scene document must never hear about it. This pins the document layer of
//! "editor preferences don't pollute the game" (the T19 plan's GR2): after
//! the whole `viewport.*` operator family has had its way -- driven the way
//! a user drives it, each call asking for a history entry it must not get --
//! a saved scene is byte-identical to the save before them and the undo
//! history gained nothing. A companion test walks the fixture-prep chain the
//! T19 live matrix will drive (select, `component.add`, `environment.set`,
//! `scene.save`), so the plan's decision 3 -- authoring the fixture's
//! environment through the operators instead of a hand-written document --
//! is settled on the same operator surface the prep leg uses.

use std::path::{Path, PathBuf};

use bevy::prelude::*;
use jackdaw::viewport_settings::{
    AntiAliasing, DetailDistance, ShadowQuality, SsaoQuality, ViewportSettings,
    ViewportSettingsFile,
};
use jackdaw_api::prelude::*;
use jackdaw_commands::CommandHistory;
use jackdaw_scene_types::{Antialiasing, Environment, PropertyValue};

use crate::util;
use crate::util::OperatorResultExt as _;

fn settle(app: &mut App) {
    for _ in 0..8 {
        app.update();
    }
}

/// A scene with the pieces the boundary is about: a root that carries the
/// scene's environment and a camera the dressing would want to touch.
const SCENE: &str = "#valley\n\
     bevy_transform::components::transform::Transform\n\
     jackdaw_scene_types::environment::Environment\n\
     bevy_ecs::hierarchy::Children [\n    \
     #lookout\n    \
     bevy_transform::components::transform::Transform\n    \
     bevy_camera::components::Camera3d\n\
     ]\n";

/// An editor with a project of its own and a scene open from disk.
fn editor_on_a_scene() -> (App, tempfile::TempDir, PathBuf) {
    let tmp = tempfile::tempdir().expect("tempdir");
    std::fs::copy(
        Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/definition_project/jackdaw.toml"),
        tmp.path().join("jackdaw.toml"),
    )
    .expect("the manifest copies");
    std::fs::create_dir_all(tmp.path().join("assets")).expect("an assets folder");

    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    settle(&mut app);

    let scene = tmp.path().join("assets/valley.bsn");
    std::fs::write(&scene, SCENE).expect("the scene is written");
    jackdaw::scenes::operators::scene_open_system(app.world_mut(), &scene);
    settle(&mut app);
    (app, tmp, scene)
}

/// Run one clause the way a toolbar button or a keybind does: the caller
/// asks for a history entry, so a viewport preference that created one can
/// no longer hide behind a quieter dispatch path.
fn user_op(app: &mut App, clause: &str) {
    jackdaw::boot_ops::run_op_clause_as_user(app.world_mut(), clause)
        .unwrap_or_else(|err| panic!("{clause}: {err}"))
        .assert_finished();
    settle(app);
}

/// Every operator the Graphics panel's Viewport section reaches, in one
/// pass: both presets, every single quality choice, every show flag, the
/// sharpening pair and the three redraw toggles. Returns so only after each
/// call has settled.
fn run_the_whole_viewport_suite(app: &mut App) {
    user_op(app, "viewport.quality.preset preset=low");
    user_op(app, "viewport.quality.preset preset=high");
    user_op(
        app,
        "viewport.quality.set render_scale=50 anti_aliasing=smaa shadow_quality=high \
         detail_distance=far ssao_quality=ultra",
    );
    for flag in [
        "sun_shadows",
        "point_shadows",
        "sky_reflection",
        "fog",
        "post_processing",
        "bloom",
        "ambient_occlusion",
        "terrain_detail",
    ] {
        user_op(app, &format!("viewport.show.toggle flag={flag} on=false"));
    }
    user_op(app, "viewport.ssao.set on=true quality=ultra");
    user_op(app, "viewport.sharpen.set on=true strength=0.8");
    user_op(app, "viewport.realtime.toggle on=false");
    user_op(app, "viewport.stats.toggle on=true");
    user_op(app, "viewport.stats.graph.toggle on=true");
}

/// The settings really did move, every field the suite touches -- so the
/// byte-identity assertion after them cannot pass because the operators
/// silently did nothing.
fn assert_the_settings_moved(app: &mut App) {
    let settings = app.world().resource::<ViewportSettings>();
    let quality = &settings.quality;
    assert_eq!(
        settings.preset(),
        None,
        "the mixed choices left every preset behind"
    );
    assert_eq!(
        quality.render_scale, 50,
        "viewport.quality.set render_scale"
    );
    assert_eq!(
        quality.anti_aliasing,
        AntiAliasing::Smaa,
        "viewport.quality.set anti_aliasing"
    );
    assert_eq!(
        quality.shadow_quality,
        ShadowQuality::High,
        "viewport.quality.set shadow_quality"
    );
    assert_eq!(
        quality.detail_distance,
        DetailDistance::Far,
        "viewport.quality.set detail_distance"
    );
    assert_eq!(
        quality.ssao_quality,
        SsaoQuality::Ultra,
        "viewport.quality.set + viewport.ssao.set ssao_quality"
    );
    assert!(
        quality.ambient_occlusion,
        "viewport.ssao.set on=true re-lit what the toggles turned off"
    );
    assert!(!quality.sun_shadows, "viewport.show.toggle sun_shadows");
    assert!(!quality.point_shadows, "viewport.show.toggle point_shadows");
    assert!(!quality.fog, "viewport.show.toggle fog");
    assert!(
        !quality.post_processing,
        "viewport.show.toggle post_processing"
    );
    assert!(!quality.bloom, "viewport.show.toggle bloom");
    assert!(
        !settings.sky_reflection,
        "viewport.show.toggle sky_reflection"
    );
    assert!(
        !settings.terrain_detail,
        "viewport.show.toggle terrain_detail"
    );
    assert!(!settings.realtime, "viewport.realtime.toggle on=false");
    assert!(settings.stats, "viewport.stats.toggle on=true");
    assert!(settings.frame_graph, "viewport.stats.graph.toggle on=true");
    assert!(settings.sharpen, "viewport.sharpen.set on=true");
    assert_eq!(
        settings.sharpen_strength, 0.8,
        "viewport.sharpen.set strength"
    );
}

/// After the whole `viewport.*` family has had its way, `scene.save` writes
/// back exactly the bytes it wrote before any of them ran, and no undo entry
/// appeared. The document on disk is re-dirtied between the two saves so a
/// save that silently did not happen reads as a failure too, not as a pass.
#[test]
fn the_viewport_preferences_leave_the_scene_document_untouched() {
    let (mut app, _tmp, scene) = editor_on_a_scene();
    let settings_path = _tmp.path().join("viewport-settings.json");
    app.world_mut().resource_mut::<ViewportSettingsFile>().path = Some(settings_path);

    // The first save normalizes the document; its bytes are the digest to
    // hold, taken before any preference is touched.
    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves before any preference is touched"
    );
    let before = std::fs::read(&scene).expect("the scene is on disk");
    let undo_before = app.world().resource::<CommandHistory>().undo_stack.len();

    run_the_whole_viewport_suite(&mut app);
    assert_the_settings_moved(&mut app);

    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        undo_before,
        "viewport preferences never enter the undo history: ran the whole \
         viewport.* family through the user path and the stack went from \
         {undo_before} entries to {}",
        app.world().resource::<CommandHistory>().undo_stack.len(),
    );

    // Re-dirty the file on disk. The save below must rewrite it; if it
    // silently did not, the junk would survive and fail this test.
    std::fs::write(&scene, "// clobbered\n").expect("the scene is re-dirtied");

    user_op(&mut app, "scene.save");
    let after = std::fs::read(&scene).expect("the saved scene is on disk");
    assert_eq!(
        after, before,
        "scene.save after the whole viewport.* family writes back the same \
         bytes: the editor preferences (preset, AA, SSAO, sharpening, every \
         show flag, realtime/stats/graph) reached only the user-level \
         settings, not the scene document",
    );
}

/// The fixture-prep chain the T19 live matrix will drive lands an
/// environment the editor itself wrote: select the scene's root, add the
/// component, seed it by paths, save -- and a reopened scene reads the same
/// values back. One undo entry per writing call, as the Scene section's
/// contract names.
#[test]
fn the_prep_chain_authors_an_environment_through_the_operators() {
    let (mut app, _tmp, scene) = editor_on_a_scene();

    user_op(&mut app, "selection.select name=valley");
    let valley = {
        let world = app.world_mut();
        let mut query = world.query::<(Entity, &Name)>();
        query
            .iter(world)
            .find(|(_, named)| named.as_str() == "valley")
            .map(|(entity, _)| entity)
            .expect("the scene's root answers to its name")
    };

    let result = app
        .world_mut()
        .operator("component.add")
        .settings(jackdaw_api_internal::operator::CallOperatorSettings {
            execution_context: jackdaw_api_internal::operator::ExecutionContext::Invoke,
            creates_history_entry: true,
        })
        .param("entity", PropertyValue::Entity(valley))
        .param(
            "type_path",
            PropertyValue::from("jackdaw_scene_types::environment::Environment"),
        )
        .call()
        .expect("component.add dispatched");
    result.assert_finished();
    settle(&mut app);
    assert!(
        app.world().get::<Environment>(valley).is_some(),
        "component.add put an environment on the scene's root"
    );

    user_op(
        &mut app,
        "environment.set sky.enabled=true post.enabled=true post.exposure=13 \
         post.bloom_intensity=0.8 post.antialiasing=Smaa",
    );

    user_op(&mut app, "scene.save");
    let text = std::fs::read_to_string(&scene).expect("the scene is on disk");
    assert!(
        text.contains("Environment"),
        "the document carries the environment, got\n{text}"
    );

    jackdaw::scenes::operators::scene_open_system(app.world_mut(), &scene);
    settle(&mut app);
    let reopened = {
        let world = app.world_mut();
        let mut query = world.query::<(Entity, &Name)>();
        query
            .iter(world)
            .find(|(_, named)| named.as_str() == "valley")
            .map(|(entity, _)| entity)
            .expect("the scene spawned its root again")
    };
    let environment = app
        .world()
        .get::<Environment>(reopened)
        .cloned()
        .expect("the reopened scene's environment");
    assert!(
        environment.sky.enabled && environment.post.enabled,
        "the seeds survive the round trip"
    );
    assert_eq!(environment.post.exposure, 13.0);
    assert_eq!(environment.post.bloom_intensity, 0.8);
    assert_eq!(
        environment.post.antialiasing,
        Antialiasing::Smaa,
        "the scene-level AA seed is the matrix's authorization face"
    );
}
