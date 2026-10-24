//! The Graphics panel: a registered window that opens into the right sidebar,
//! whose every control reaches the operator it names -- viewport preferences
//! without undo, scene post-processing with exactly one undo entry per
//! release -- and whose Realtime GI row stays honestly disabled.

use crate::util;
use crate::util::OperatorResultExt as _;

use bevy::prelude::*;
use bevy::ui::{Checked, InteractionDisabled};
use bevy::ui_widgets::{SliderValue, ValueChange};
use jackdaw::graphics_panel::{
    GRAPHICS_WINDOW_ID, GraphicsOptOutHint, GraphicsPanel, GraphicsRealtimeGi,
    GraphicsSceneEmptyHint, GraphicsSegment, GraphicsSlider, GraphicsToggle,
    GraphicsTonemapperField,
};
use jackdaw::viewport_settings::{
    AntiAliasing, QualityPreset, SsaoQuality, ViewportSettings, ViewportSettingsFile,
};
use jackdaw_commands::CommandHistory;
use jackdaw_feathers::combobox::ComboBoxChangeEvent;
use jackdaw_feathers::tooltip::Tooltip;
use jackdaw_panels::WindowRegistry;
use jackdaw_panels::tree::DockTree;
use jackdaw_scene_types::{Environment, Tonemapper};

fn settle(app: &mut App) {
    for _ in 0..8 {
        app.update();
    }
}

/// An editor past its first frames in the Editor state, so the dock tree has
/// materialized and with it the Graphics panel's content.
fn editor_on_a_panel() -> App {
    let mut app = util::editor_test_app();
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    settle(&mut app);
    app
}

fn open_panel(app: &mut App) {
    jackdaw::boot_ops::run_op_clause(app.world_mut(), "graphics.open")
        .unwrap_or_else(|err| panic!("graphics.open: {err}"))
        .assert_finished();
    settle(app);
}

fn segment(app: &mut App, wanted: GraphicsSegment) -> Entity {
    let world = app.world_mut();
    let mut query = world.query::<(Entity, &GraphicsSegment)>();
    query
        .iter(world)
        .find(|(_, found)| **found == wanted)
        .map(|(entity, _)| entity)
        .unwrap_or_else(|| panic!("a segment for {wanted:?}"))
}

fn toggle(app: &mut App, wanted: GraphicsToggle) -> Entity {
    let world = app.world_mut();
    let mut query = world.query::<(Entity, &GraphicsToggle)>();
    query
        .iter(world)
        .find(|(_, found)| **found == wanted)
        .map(|(entity, _)| entity)
        .unwrap_or_else(|| panic!("a toggle row for {wanted:?}"))
}

fn slider(app: &mut App, wanted: GraphicsSlider) -> Entity {
    let world = app.world_mut();
    let mut query = world.query::<(Entity, &GraphicsSlider)>();
    query
        .iter(world)
        .find(|(_, found)| **found == wanted)
        .map(|(entity, _)| entity)
        .unwrap_or_else(|| panic!("a slider row for {wanted:?}"))
}

/// Every entity at or below `root`, breadth first.
fn subtree(world: &World, root: Entity) -> Vec<Entity> {
    let mut found = vec![root];
    let mut queue = vec![root];
    while let Some(next) = queue.pop() {
        if let Some(children) = world.get::<Children>(next) {
            for child in children {
                found.push(*child);
                queue.push(*child);
            }
        }
    }
    found
}

fn panel_subtree(app: &mut App) -> Vec<Entity> {
    let world = app.world_mut();
    let mut query = world.query_filtered::<Entity, With<GraphicsPanel>>();
    let panel = query.single(world).expect("one Graphics panel");
    subtree(world, panel)
}

/// The panel's texts as one readable page, so a missing row names itself.
fn panel_text(app: &mut App) -> String {
    let under_panel = panel_subtree(app);
    let world = app.world_mut();
    let mut query = world.query::<&Text>();
    under_panel
        .into_iter()
        .filter_map(|entity| query.get(world, entity).ok())
        .map(|text| text.0.clone())
        .collect::<Vec<_>>()
        .join("\n")
}

/// The window is registered where the plan puts it, and its opening operator
/// is in the registry the command palette enumerates.
#[test]
fn the_graphics_window_is_registered_and_searchable() {
    let mut app = util::editor_test_app();
    let registry = app.world().resource::<WindowRegistry>();
    let descriptor = registry
        .get(GRAPHICS_WINDOW_ID)
        .expect("the Graphics window is registered");
    assert_eq!(descriptor.name, "Graphics");
    assert_eq!(descriptor.default_area, "right_sidebar");

    assert!(
        util::iter_operator_ids(&mut app)
            .iter()
            .any(|id| id == "graphics.open"),
        "the command palette can find graphics.open"
    );
}

/// Opening through the operator docks (or focuses) the panel's tab, and the
/// built panel names both sections and the disabled GI row.
#[test]
fn opening_the_panel_docks_a_tab_with_both_sections() {
    let mut app = editor_on_a_panel();
    open_panel(&mut app);

    let tree = app.world().resource::<DockTree>();
    assert!(
        tree.find_leaf_with_window(GRAPHICS_WINDOW_ID).is_some(),
        "the dock tree holds the Graphics tab"
    );

    let page = panel_text(&mut app);
    for expected in [
        "Viewport",
        "Quality Preset",
        "Anti-Aliasing",
        "Ambient Occlusion",
        "Sharpening",
        "Scene",
        "Tonemapper",
        "Exposure (EV100)",
        "Bloom Intensity",
        "Bloom Threshold",
        "Realtime GI",
    ] {
        assert!(
            page.contains(expected),
            "the panel names {expected:?}; it reads\n{page}"
        );
    }
}

/// Every kind of Viewport-section control reaches its operator: a segmented
/// pick, a checkbox, and a live slider tick each land in the user's settings
/// without leaving any undo entry.
#[test]
fn each_viewport_control_reaches_its_operator() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = editor_on_a_panel();
    app.world_mut().resource_mut::<ViewportSettingsFile>().path =
        Some(dir.path().join("viewport.json"));
    open_panel(&mut app);

    let low = segment(&mut app, GraphicsSegment::Preset(QualityPreset::Low));
    app.world_mut().trigger(ValueChange::<Entity> {
        source: low,
        value: low,
        is_final: true,
    });
    app.update();
    assert_eq!(
        app.world().resource::<ViewportSettings>().preset(),
        Some(QualityPreset::Low)
    );

    let smaa = segment(&mut app, GraphicsSegment::AntiAlias(AntiAliasing::Smaa));
    app.world_mut().trigger(ValueChange::<Entity> {
        source: smaa,
        value: smaa,
        is_final: true,
    });
    let ultra = segment(&mut app, GraphicsSegment::SsaoQuality(SsaoQuality::Ultra));
    app.world_mut().trigger(ValueChange::<Entity> {
        source: ultra,
        value: ultra,
        is_final: true,
    });
    let occlusion = toggle(&mut app, GraphicsToggle::AmbientOcclusion);
    app.world_mut().trigger(ValueChange::<bool> {
        source: occlusion,
        value: true,
        is_final: true,
    });
    app.update();
    let quality = app.world().resource::<ViewportSettings>().quality;
    assert_eq!(quality.anti_aliasing, AntiAliasing::Smaa);
    assert_eq!(quality.ssao_quality, SsaoQuality::Ultra);
    assert!(quality.ambient_occlusion);
    assert!(
        app.world().get::<Checked>(occlusion).is_some(),
        "the checkbox reflects the state it set"
    );

    let fog = toggle(&mut app, GraphicsToggle::Fog);
    app.world_mut().trigger(ValueChange::<bool> {
        source: fog,
        value: false,
        is_final: true,
    });
    let scale = slider(&mut app, GraphicsSlider::RenderScale);
    app.world_mut().trigger(ValueChange::<f32> {
        source: scale,
        value: 60.0,
        is_final: false,
    });
    let strength = slider(&mut app, GraphicsSlider::SharpenStrength);
    app.world_mut().trigger(ValueChange::<f32> {
        source: strength,
        value: 0.8,
        is_final: false,
    });
    app.update();
    let settings = app.world().resource::<ViewportSettings>();
    assert!(!settings.quality.fog);
    assert_eq!(settings.quality.render_scale, 60);
    assert_eq!(settings.sharpen_strength, 0.8);
    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        0,
        "viewport preferences never enter the undo history"
    );
}

/// The Scene sliders commit on release and only on release: a drag's
/// intermediate ticks write neither the environment nor the history, and the
/// release is exactly one undo entry that takes the value back.
#[test]
fn a_scene_slider_commits_once_on_release() {
    let mut app = editor_on_a_panel();
    let environment = app.world_mut().spawn(Environment::default()).id();
    open_panel(&mut app);

    let bloom = slider(&mut app, GraphicsSlider::BloomIntensity);
    for value in [0.2, 0.4] {
        app.world_mut().trigger(ValueChange::<f32> {
            source: bloom,
            value,
            is_final: false,
        });
        app.update();
        assert_eq!(
            app.world()
                .get::<Environment>(environment)
                .unwrap()
                .post
                .bloom_intensity,
            0.0,
            "an intermediate drag tick writes nothing"
        );
        assert_eq!(
            app.world().resource::<CommandHistory>().undo_stack.len(),
            0,
            "an intermediate drag tick is no undo entry"
        );
    }

    app.world_mut().trigger(ValueChange::<f32> {
        source: bloom,
        value: 0.6,
        is_final: true,
    });
    app.update();
    assert_eq!(
        app.world()
            .get::<Environment>(environment)
            .unwrap()
            .post
            .bloom_intensity,
        0.6
    );
    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        1,
        "one drag is one undo entry, however many ticks it took"
    );
    assert_eq!(
        app.world().get::<SliderValue>(bloom).unwrap().0,
        0.6,
        "the widget holds the released value"
    );

    jackdaw::boot_ops::run_op_clause(app.world_mut(), "history.undo")
        .unwrap_or_else(|err| panic!("history.undo: {err}"))
        .assert_finished();
    settle(&mut app);
    assert_eq!(
        app.world()
            .get::<Environment>(environment)
            .unwrap()
            .post
            .bloom_intensity,
        0.0,
        "the one entry takes the value back"
    );
}

/// The tonemapper dropdown and the post-processing switch reach the same
/// `environment.set` path the inspector uses.
#[test]
fn the_scene_rows_write_the_environment() {
    let mut app = editor_on_a_panel();
    let environment = app.world_mut().spawn(Environment::default()).id();
    open_panel(&mut app);

    let post = toggle(&mut app, GraphicsToggle::PostProcessing);
    app.world_mut().trigger(ValueChange::<bool> {
        source: post,
        value: true,
        is_final: true,
    });
    app.update();
    assert!(
        app.world()
            .get::<Environment>(environment)
            .unwrap()
            .post
            .enabled
    );

    let dropdown = {
        let world = app.world_mut();
        let mut query = world.query_filtered::<Entity, With<GraphicsTonemapperField>>();
        query.single(world).expect("the tonemapper row")
    };
    app.world_mut().trigger(ComboBoxChangeEvent {
        entity: dropdown,
        selected: 5,
        label: "AgX".to_string(),
        value: Some("AgX".to_string()),
    });
    app.update();
    assert_eq!(
        app.world()
            .get::<Environment>(environment)
            .unwrap()
            .post
            .tonemapper,
        Tonemapper::AgX
    );
}

/// The Realtime GI row is present but disabled: its checkbox cannot be
/// interacted with, and the tooltip says why and what stands in.
#[test]
fn the_realtime_gi_row_is_shown_but_disabled() {
    let mut app = editor_on_a_panel();
    open_panel(&mut app);

    let row = {
        let world = app.world_mut();
        let mut query = world.query_filtered::<Entity, With<GraphicsRealtimeGi>>();
        query.single(world).expect("the Realtime GI row")
    };
    let under_row = subtree(app.world(), row);
    assert!(
        under_row
            .iter()
            .any(|entity| app.world().get::<InteractionDisabled>(*entity).is_some()),
        "the row's checkbox is disabled"
    );
    let tooltip = app
        .world()
        .get::<Tooltip>(row)
        .expect("the row explains itself on hover");
    assert!(tooltip.description.contains("Solari"));
}

/// Turning the viewport's post-processing opt-out off shows the hint that the
/// Scene section is not being previewed, and turning it back on hides the
/// hint again.
#[test]
fn the_opt_out_hint_follows_the_viewport_setting() {
    let mut app = editor_on_a_panel();
    open_panel(&mut app);

    let wanted = |app: &mut App| -> Display {
        let world = app.world_mut();
        let mut query = world.query_filtered::<&Node, With<GraphicsOptOutHint>>();
        query.single(world).expect("the opt-out hint").display
    };

    assert_eq!(
        wanted(&mut app),
        Display::None,
        "the High preset previews post"
    );
    jackdaw::boot_ops::run_op_clause(
        app.world_mut(),
        "viewport.show.toggle flag=post_processing on=false",
    )
    .unwrap_or_else(|err| panic!("viewport.show.toggle: {err}"))
    .assert_finished();
    settle(&mut app);
    assert_eq!(
        wanted(&mut app),
        Display::Flex,
        "the note appears once opted out"
    );
}

/// With no environment in the scene the Scene section says so instead of its
/// controls sitting silently inert, and the note leaves — however the state
/// came about — once an environment exists again.
#[test]
fn the_scene_empty_hint_follows_the_scenes_environment() {
    let mut app = editor_on_a_panel();
    open_panel(&mut app);

    let wanted = |app: &mut App| -> Display {
        let world = app.world_mut();
        let mut query = world.query_filtered::<&Node, With<GraphicsSceneEmptyHint>>();
        query.single(world).expect("the scene-empty hint").display
    };

    assert_eq!(
        wanted(&mut app),
        Display::Flex,
        "a scene without an environment shows the note"
    );
    let page = panel_text(&mut app);
    assert!(
        page.contains("no environment"),
        "the note names the missing environment; it reads\n{page}"
    );

    let environment = app.world_mut().spawn(Environment::default()).id();
    settle(&mut app);
    assert_eq!(
        wanted(&mut app),
        Display::None,
        "an environment in the scene hides the note"
    );

    app.world_mut().despawn(environment);
    settle(&mut app);
    assert_eq!(
        wanted(&mut app),
        Display::Flex,
        "losing the environment brings the note back"
    );
}
