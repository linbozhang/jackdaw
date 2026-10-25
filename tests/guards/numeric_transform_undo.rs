//! `transform.numeric_apply` (X + number + Enter): one gesture, one
//! framework-snapshot entry, on both branches of the operator — the object
//! selection and the brush-edit sub-elements — with the document, the dirty
//! flag and the file all in agreement (R2).

use bevy::prelude::*;
use jackdaw::boot_ops::{run_op_clause, run_op_clause_as_user};
use jackdaw::gizmos::GizmoAxis;
use jackdaw::numeric_transform::NumericTransformState;
use jackdaw::scenes::Scenes;
use jackdaw_api::prelude::*;

use super::batch_undo::{depth, scene_text};
use crate::util::{self, OperatorResultExt as _};

const ZONE_SCENE: &str = "#Zone\nbevy_transform::components::transform::Transform\n";

/// An editor on a project whose saved zone scene is open in front.
fn editor() -> (App, tempfile::TempDir, std::path::PathBuf) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-numeric-undo-")
        .tempdir()
        .expect("temp dir");
    std::fs::create_dir_all(tmp.path().join("assets")).expect("assets folder");
    let scene = tmp.path().join("assets/zone.bsn");
    std::fs::write(&scene, ZONE_SCENE).expect("scene written");

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
    run_op_clause(app.world_mut(), "scene.open path=assets/zone.bsn")
        .expect("the scene opens")
        .assert_finished();
    util::settle_scene_load(&mut app);
    (app, tmp, scene)
}

/// The Zone entity, selected.
fn zone_selected(app: &mut App) -> Entity {
    let zone = app
        .world_mut()
        .query::<(Entity, &Name)>()
        .iter(app.world())
        .find(|(_, name)| name.as_str() == "Zone")
        .map(|(entity, _)| entity)
        .expect("the Zone entity");
    jackdaw::selection::select_only(app.world_mut(), zone);
    app.update();
    zone
}

/// Arm X + `input` and dispatch the apply the way the Enter keypress does.
fn apply_numeric(app: &mut App, input: &str) {
    app.world_mut().insert_resource(NumericTransformState {
        axis: Some(GizmoAxis::X),
        input: input.to_string(),
    });
    app.world_mut()
        .operator("transform.numeric_apply")
        .settings(jackdaw_api_internal::operator::CallOperatorSettings {
            execution_context: jackdaw_api_internal::operator::ExecutionContext::Invoke,
            creates_history_entry: true,
        })
        .call()
        .expect("the apply dispatches")
        .assert_finished();
    app.update();
}

fn tab_dirty(app: &App) -> bool {
    let scenes = app.world().resource::<Scenes>();
    scenes.tabs[scenes.active].dirty
}

fn undo(app: &mut App) {
    super::batch_undo::history(app, "history.undo");
}

/// The Zone entity by name; a document respawn re-mints entity ids, so
/// look it up each time it is needed.
fn zone_entity(app: &mut App) -> Entity {
    app.world_mut()
        .query::<(Entity, &Name)>()
        .iter(app.world())
        .find(|(_, name)| name.as_str() == "Zone")
        .map(|(entity, _)| entity)
        .expect("the Zone entity")
}

/// The three symptoms of the defect, one after the other: the apply is
/// exactly one entry (not zero), undo puts the transform back, and the
/// document (what a save writes) holds the move.
#[test]
fn a_numeric_move_is_one_entry_undoes_and_reaches_the_document() {
    let (mut app, _tmp, _scene) = editor();
    zone_selected(&mut app);
    let before = depth(&app);
    let before_text = scene_text(&mut app);

    apply_numeric(&mut app, "1");

    assert_eq!(
        depth(&app),
        before + 1,
        "X + number + Enter is one entry: the framework snapshot, nothing else"
    );
    let moved = zone_entity(&mut app);
    assert_eq!(
        app.world().get::<Transform>(moved).unwrap().translation.x,
        1.0,
        "the move landed on the entity"
    );
    let moved_text = scene_text(&mut app);
    assert_ne!(
        moved_text, before_text,
        "the document holds the move, so a save keeps it"
    );
    assert!(tab_dirty(&app), "the move dirties the tab");

    undo(&mut app);
    app.update();
    let restored = zone_entity(&mut app);
    assert_eq!(
        app.world()
            .get::<Transform>(restored)
            .unwrap()
            .translation
            .x,
        0.0,
        "one undo puts the transform back"
    );
    assert_eq!(
        scene_text(&mut app),
        before_text,
        "the document is back where it started"
    );
}

/// The saved file itself: the move a save writes survives a reload, the
/// concrete shape of "Ctrl+Z 撤错 + 保存丢移动".
#[test]
fn a_numeric_move_survives_save_and_reload() {
    let (mut app, _tmp, scene) = editor();
    zone_selected(&mut app);
    apply_numeric(&mut app, "1");

    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    let saved = std::fs::read_to_string(&scene).expect("the saved file");
    let parsed = jackdaw_bsn::parse_bsn_text(&saved).expect("the saved file parses");
    let root = *parsed.roots.first().expect("a root node");
    let x = jackdaw_bsn::get_bsn_field(
        &parsed,
        root,
        "bevy_transform::components::transform::Transform",
        "translation.x",
    );
    assert!(
        matches!(x, Some(jackdaw_bsn::BsnValue::Float(v)) if (v - 1.0).abs() < 1e-6),
        "the file on disk holds the move: {saved}"
    );

    // Reload it and the entity comes back where the move left it.
    run_op_clause(
        app.world_mut(),
        "scene.open path=assets/zone.bsn reload=true",
    )
    .expect("the reload opens")
    .assert_finished();
    util::settle_scene_load(&mut app);
    let zone = app
        .world_mut()
        .query::<(Entity, &Name)>()
        .iter(app.world())
        .find(|(_, name)| name.as_str() == "Zone")
        .map(|(entity, _)| entity)
        .expect("the Zone entity, back from the file");
    assert_eq!(
        app.world().get::<Transform>(zone).unwrap().translation.x,
        1.0,
        "the move survives the round trip"
    );
}

/// A multi-selection is still one gesture, one entry.
#[test]
fn a_numeric_move_over_a_multi_selection_is_one_entry() {
    let (mut app, _tmp, _scene) = editor();
    zone_selected(&mut app);
    run_op_clause_as_user(app.world_mut(), "entity.add.cube")
        .expect("the cube dispatches")
        .assert_finished();
    app.update();
    let cube = app
        .world_mut()
        .query::<(Entity, &Name)>()
        .iter(app.world())
        .find(|(_, name)| name.as_str() == "Cube")
        .map(|(entity, _)| entity)
        .expect("the cube entity");
    let zone = app
        .world_mut()
        .query::<(Entity, &Name)>()
        .iter(app.world())
        .find(|(_, name)| name.as_str() == "Zone")
        .map(|(entity, _)| entity)
        .expect("the zone entity");
    let selection = vec![zone, cube];
    app.world_mut()
        .resource_mut::<jackdaw::selection::Selection>()
        .entities = selection.clone();
    for &entity in &selection {
        if let Ok(mut ec) = app.world_mut().get_entity_mut(entity) {
            ec.insert(jackdaw::selection::Selected);
        }
    }
    app.update();

    let before = depth(&app);
    apply_numeric(&mut app, "2");
    assert_eq!(
        depth(&app),
        before + 1,
        "both targets move as one gesture, one entry"
    );
    assert_eq!(
        app.world().get::<Transform>(zone).unwrap().translation.x,
        2.0
    );
    assert_eq!(
        app.world().get::<Transform>(cube).unwrap().translation.x,
        2.0
    );
}

/// The brush-edit branch (N2): the same entry, via the inline brush AST sync.
#[test]
fn a_numeric_move_of_brush_sub_elements_is_one_entry() {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-numeric-brush-")
        .tempdir()
        .expect("temp dir");
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
    run_op_clause(app.world_mut(), "scene.new")
        .expect("a scene opens")
        .assert_finished();
    app.update();

    let brush = app
        .world_mut()
        .spawn((
            Name::new("TestBrush"),
            jackdaw_scene_types::Brush::cuboid(0.5, 0.5, 0.5),
            Transform::default(),
            Visibility::default(),
        ))
        .id();
    for _ in 0..6 {
        app.update();
    }
    assert!(
        app.world()
            .get::<jackdaw::brush::BrushMeshCache>(brush)
            .is_some(),
        "the brush meshed"
    );
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), brush);
    app.update();

    *app.world_mut().resource_mut::<jackdaw::brush::EditMode>() =
        jackdaw::brush::EditMode::BrushEdit(jackdaw::brush::BrushEditMode::Face);
    {
        let mut brush_selection = app
            .world_mut()
            .resource_mut::<jackdaw::brush::BrushSelection>();
        brush_selection.active_brush = Some(brush);
        brush_selection.sub_mut(brush).faces = vec![0];
    }
    app.update();

    let before = depth(&app);
    let before_text = scene_text(&mut app);
    apply_numeric(&mut app, "1");

    assert_eq!(
        depth(&app),
        before + 1,
        "the brush-edit apply is one entry, not zero"
    );
    assert_ne!(
        scene_text(&mut app),
        before_text,
        "the document holds the edited brush"
    );
    assert!(tab_dirty(&app), "the brush edit dirties the tab");

    undo(&mut app);
    app.update();
    assert_eq!(
        scene_text(&mut app),
        before_text,
        "one undo puts the brush back"
    );
}
