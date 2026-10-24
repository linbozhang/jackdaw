//! The three-way consistency matrix: a value an inspector field takes must
//! reach the ECS (the viewport), the document (the AST patch), and a
//! save-reload cycle as the same value. Materials and custom components hold
//! coverage elsewhere; this file fills the light, camera, and
//! transform-anchor cells.

use std::path::{Path, PathBuf};

use bevy::feathers::controls::ColorPlaneValue;
use bevy::prelude::*;
use bevy::ui_widgets::ValueChange;
use jackdaw::selection::Selection;
use jackdaw_bsn::{BsnValue, SceneBsnAst};

use crate::util;

const TRANSFORM: &str = "bevy_transform::components::transform::Transform";
const DIRECTIONAL: &str = "bevy_light::directional_light::DirectionalLight";
const POINT: &str = "bevy_light::point_light::PointLight";
const CAMERA_3D: &str = "bevy_camera::components::Camera3d";

fn settle(app: &mut App) {
    for _ in 0..6 {
        app.update();
    }
}

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/definition_project")
}

/// An editor with a project of its own and a scene of `document` open. The
/// scene's root keeps the name the document gives it.
fn editor_on(document: &str) -> (App, tempfile::TempDir, PathBuf) {
    let tmp = tempfile::tempdir().expect("tempdir");
    std::fs::copy(
        fixture_dir().join("jackdaw.toml"),
        tmp.path().join("jackdaw.toml"),
    )
    .expect("the manifest copies");
    std::fs::create_dir_all(tmp.path().join("assets")).expect("an assets folder");

    let mut app = util::editor_test_app();
    app.world_mut()
        .spawn(jackdaw::layout::inspector_components_content(default()));
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

    let scene = tmp.path().join("assets/scene.bsn");
    std::fs::write(&scene, document).expect("the scene is written");
    jackdaw::scenes::operators::scene_open_system(app.world_mut(), &scene);
    settle(&mut app);
    (app, tmp, scene)
}

/// The last entity the open scene carries under `name`.
fn named(app: &mut App, name: &str) -> Entity {
    let found: Vec<Entity> = app
        .world_mut()
        .query::<(Entity, &Name)>()
        .iter(app.world())
        .filter(|(_, spawned)| spawned.as_str() == name)
        .map(|(entity, _)| entity)
        .collect();
    *found.last().unwrap_or_else(|| panic!("no {name} entity"))
}

fn select(app: &mut App, entity: Entity) {
    let world = app.world_mut();
    world.resource_scope(|world, mut selection: Mut<Selection>| {
        let mut commands = world.commands();
        selection.select_single(&mut commands, entity);
    });
    world.flush();
    settle(app);
}

/// The control that writes `(type_path, path)` on the selected card.
fn field(app: &mut App, type_path: &str, path: &str) -> Entity {
    let mut all = app.world_mut().query::<Entity>();
    let entities: Vec<Entity> = all.iter(app.world()).collect();
    entities
        .into_iter()
        .find(|entity| {
            jackdaw::inspector::field_edited_by(app.world(), *entity) == Some((type_path, path))
        })
        .unwrap_or_else(|| panic!("no row writes {type_path}.{path}"))
}

/// The number a document field holds, as `f32`, or `None` when the field is
/// not authored or not a number.
fn authored_number(app: &App, entity: Entity, type_path: &str, path: &str) -> Option<f32> {
    let ast = app.world().resource::<SceneBsnAst>();
    let node = ast.ast_for(entity)?;
    match jackdaw_bsn::get_bsn_field(ast, node, type_path, path)? {
        BsnValue::Float(value) => Some(value as f32),
        BsnValue::Int(value) => Some(value as f32),
        _ => None,
    }
}

/// Whether a document field is authored at all.
fn authored(app: &App, entity: Entity, type_path: &str, path: &str) -> bool {
    let ast = app.world().resource::<SceneBsnAst>();
    ast.ast_for(entity)
        .is_some_and(|node| jackdaw_bsn::get_bsn_field(ast, node, type_path, path).is_some())
}

fn commit_f64(app: &mut App, row: Entity, value: f64) {
    app.world_mut().trigger(ValueChange {
        source: row,
        value,
        is_final: true,
    });
    app.update();
    settle(app);
}

/// Close the document and open the saved file again.
fn reopen(app: &mut App, scene: &Path) {
    jackdaw::scenes::operators::scene_open_system(app.world_mut(), scene);
    settle(app);
}

#[test]
fn a_transform_edit_survives_save_and_reopen() {
    let (mut app, _tmp, scene) =
        editor_on("#block\nbevy_transform::components::transform::Transform\n");
    let block = named(&mut app, "block");
    select(&mut app, block);
    let row = field(&mut app, TRANSFORM, "translation.y");

    commit_f64(&mut app, row, 4.0);

    assert_eq!(
        app.world().get::<Transform>(block).unwrap().translation.y,
        4.0,
        "the ECS moves with the edit"
    );
    assert_eq!(
        authored_number(&app, block, TRANSFORM, "translation.y"),
        Some(4.0),
        "the document holds the edit"
    );

    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    reopen(&mut app, &scene);
    let block = named(&mut app, "block");
    assert_eq!(
        app.world().get::<Transform>(block).unwrap().translation.y,
        4.0,
        "the edit survives the reload"
    );
}

#[test]
fn a_directional_light_color_and_illuminance_edit_reach_everywhere() {
    let (mut app, _tmp, scene) = editor_on(
        "#sun\n\
         bevy_transform::components::transform::Transform\n\
         bevy_light::directional_light::DirectionalLight\n",
    );
    let sun = named(&mut app, "sun");
    select(&mut app, sun);

    // Color: the red/blue plane commits red to max and blue to min. The test
    // world carries two panel instances, so take either plane.
    let plane = app
        .world_mut()
        .query_filtered::<Entity, With<ColorPlaneValue>>()
        .iter(app.world())
        .next()
        .expect("the light card shows a color plane");
    app.world_mut().trigger(ValueChange {
        source: plane,
        value: Vec2::new(1.0, 0.0),
        is_final: true,
    });
    app.update();
    settle(&mut app);

    let color = app
        .world()
        .get::<DirectionalLight>(sun)
        .unwrap()
        .color
        .to_srgba();
    assert!(
        (color.red - 1.0).abs() < 1e-3 && color.blue.abs() < 1e-3,
        "the viewport color moved with the edit: {color:?}"
    );
    assert!(
        authored(&app, sun, DIRECTIONAL, "color"),
        "the document holds the color"
    );

    // Illuminance: the numeric chain, with undo putting the default back.
    let row = field(&mut app, DIRECTIONAL, "illuminance");
    let undo_depth = app
        .world()
        .resource::<jackdaw::commands::CommandHistory>()
        .undo_stack
        .len();
    commit_f64(&mut app, row, 2000.0);
    assert_eq!(
        app.world()
            .get::<DirectionalLight>(sun)
            .unwrap()
            .illuminance,
        2000.0,
        "the ECS moves with the edit"
    );
    assert_eq!(
        authored_number(&app, sun, DIRECTIONAL, "illuminance"),
        Some(2000.0),
        "the document holds the edit"
    );
    let undone =
        jackdaw::boot_ops::run_op_clause(app.world_mut(), "history.undo").expect("undo dispatches");
    assert_eq!(undone, jackdaw_api::prelude::OperatorResult::Finished);
    app.update();
    assert_eq!(
        app.world()
            .get::<DirectionalLight>(sun)
            .unwrap()
            .illuminance,
        DirectionalLight::default().illuminance,
        "undo puts the light back"
    );
    assert_eq!(
        app.world()
            .resource::<jackdaw::commands::CommandHistory>()
            .undo_stack
            .len(),
        undo_depth,
        "the undo consumed the entry"
    );

    // Take the edit again, then prove the save-reload cycle keeps both.
    let row = field(&mut app, DIRECTIONAL, "illuminance");
    commit_f64(&mut app, row, 2000.0);
    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    reopen(&mut app, &scene);
    let sun = named(&mut app, "sun");
    let light = app.world().get::<DirectionalLight>(sun).unwrap();
    let color = light.color.to_srgba();
    assert!(
        (color.red - 1.0).abs() < 1e-3 && color.blue.abs() < 1e-3,
        "the color survives the reload: {color:?}"
    );
    assert_eq!(light.illuminance, 2000.0, "the illuminance survives too");
}

#[test]
fn a_point_light_range_edit_reaches_everywhere() {
    let (mut app, _tmp, scene) = editor_on(
        "#lamp\n\
         bevy_transform::components::transform::Transform\n\
         bevy_light::point_light::PointLight\n",
    );
    let lamp = named(&mut app, "lamp");
    select(&mut app, lamp);
    let row = field(&mut app, POINT, "range");

    commit_f64(&mut app, row, 7.5);

    assert_eq!(
        app.world().get::<PointLight>(lamp).unwrap().range,
        7.5,
        "the ECS moves with the edit"
    );
    assert_eq!(
        authored_number(&app, lamp, POINT, "range"),
        Some(7.5),
        "the document holds the edit"
    );

    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    reopen(&mut app, &scene);
    let lamp = named(&mut app, "lamp");
    assert_eq!(
        app.world().get::<PointLight>(lamp).unwrap().range,
        7.5,
        "the edit survives the reload"
    );
}

#[test]
fn a_camera_field_edit_survives_save_and_reopen() {
    let (mut app, _tmp, scene) = editor_on(
        "#cam\n\
         bevy_transform::components::transform::Transform\n\
         bevy_camera::components::Camera3d\n",
    );
    let cam = named(&mut app, "cam");
    select(&mut app, cam);
    // The camera body cards (`Camera`, `Projection`, `Exposure`) are required
    // companions the panel does not card; the `Camera3d` component's own
    // numeric field carries the camera cell instead.
    let row = field(&mut app, CAMERA_3D, "depth_texture_usages.0");

    app.world_mut().trigger(ValueChange {
        source: row,
        value: 17_i64,
        is_final: true,
    });
    app.update();
    settle(&mut app);

    assert_eq!(
        app.world()
            .get::<Camera3d>(cam)
            .unwrap()
            .depth_texture_usages
            .0,
        17,
        "the ECS moves with the edit"
    );
    assert_eq!(
        authored_number(&app, cam, CAMERA_3D, "depth_texture_usages.0"),
        Some(17.0),
        "the document holds the edit"
    );

    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    reopen(&mut app, &scene);
    let cam = named(&mut app, "cam");
    assert_eq!(
        app.world()
            .get::<Camera3d>(cam)
            .unwrap()
            .depth_texture_usages
            .0,
        17,
        "the edit survives the reload"
    );
}
