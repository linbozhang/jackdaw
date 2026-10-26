//! The dirty-flag matrix: fourteen operation sequences, each asserting that
//! `tab.dirty`, `scene_io::is_scene_dirty` and (for close prompts) the flag
//! the window-close dialog reads agree with what the sequence left on disk.
//!
//! Edits go through `prefab.spawn_instance`, the one authoring op that is a
//! single framework-snapshot entry today, so the matrix measures dirty-flag
//! semantics rather than the double-record fixes that land beside them.
//!
//! Case 9 (a full scrub gesture is one entry and lights the tab) lives beside
//! the gesture-session tests in `src/commands.rs`, where the field-edit
//! session machinery is reachable.

use bevy::prelude::*;
use bevy::reflect::TypePath;
use jackdaw::boot_ops::{run_op_clause, run_op_clause_as_user};
use jackdaw::numeric_transform::{NumericTransformState, run_numeric_transform_input};
use jackdaw::scenes::{SceneTab, Scenes};
use jackdaw_api::prelude::*;
use jackdaw_commands::CommandHistory;

use super::batch_undo::{depth, scene_text};
use crate::util::{self, OperatorResultExt as _};

const ZONE_SCENE: &str = "#Zone\nbevy_transform::components::transform::Transform\n";

/// An editor on a project holding a saved scene (open in front) and a
/// one-entry prefab the edits place instances of.
fn editor() -> (App, tempfile::TempDir) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-dirty-matrix-")
        .tempdir()
        .expect("temp dir");
    std::fs::create_dir_all(tmp.path().join("assets/prefabs")).expect("asset folders");
    std::fs::write(
        tmp.path().join("assets/prefabs/rock.bsn"),
        "#Rock\nbevy_transform::components::transform::Transform\n",
    )
    .expect("the prefab");
    std::fs::write(tmp.path().join("assets/zone.bsn"), ZONE_SCENE).expect("the scene");

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
    (app, tmp)
}

/// One user edit: place a rock instance, a single snapshot entry.
fn place_rock(app: &mut App, x: f64) {
    run_op_clause_as_user(
        app.world_mut(),
        &format!("prefab.spawn_instance path=prefabs/rock.bsn pos_x={x} pos_y=0 pos_z=0"),
    )
    .expect("the placement dispatched")
    .assert_finished();
    app.update();
}

/// The Zone scene entity, selected so duplicates and drags have a target.
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

fn undo(app: &mut App) {
    super::batch_undo::history(app, "history.undo");
}

fn redo(app: &mut App) {
    super::batch_undo::history(app, "history.redo");
}

fn save(app: &mut App) {
    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );
    app.update();
}

/// The active tab's own dirty flag, the one the tab strip and the
/// close-tab prompt read.
fn tab_dirty(app: &App) -> bool {
    let scenes = app.world().resource::<Scenes>();
    scenes.tabs[scenes.active].dirty
}

/// The unified scene-dirty query, the one the asset migration guard reads.
fn scene_dirty(app: &App) -> bool {
    jackdaw::scene_io::is_scene_dirty(app.world())
}

// ---------------------------------------------------------------- case 1-8 --

/// Case 1: open a scene, do nothing: clean everywhere.
#[test]
fn open_then_nothing_is_clean() {
    let (mut app, _tmp) = editor();
    app.update();
    assert!(!tab_dirty(&app), "the tab reads clean");
    assert!(!scene_dirty(&app), "is_scene_dirty reads clean");
}

/// Case 2: one edit: dirty everywhere.
#[test]
fn one_edit_is_dirty() {
    let (mut app, _tmp) = editor();
    let before = depth(&app);
    place_rock(&mut app, 1.0);
    assert_eq!(depth(&app), before + 1, "the edit is one entry");
    assert!(tab_dirty(&app), "the tab reads dirty");
    assert!(scene_dirty(&app), "is_scene_dirty reads dirty");
}

/// Case 3: edit then undo, back to the saved content: clean again.
#[test]
fn edit_then_undo_back_to_saved_is_clean() {
    let (mut app, _tmp) = editor();
    place_rock(&mut app, 1.0);
    undo(&mut app);
    app.update();
    assert!(!tab_dirty(&app), "the tab is clean again after the undo");
    assert!(!scene_dirty(&app), "is_scene_dirty agrees");
}

/// Case 4: edit, undo, redo: dirty again.
#[test]
fn edit_undo_redo_is_dirty() {
    let (mut app, _tmp) = editor();
    place_rock(&mut app, 1.0);
    undo(&mut app);
    redo(&mut app);
    assert!(tab_dirty(&app), "the redo re-dirties the tab");
    assert!(scene_dirty(&app), "is_scene_dirty agrees");
}

/// Case 5, the highest-stakes one: save, then undo. The tab must read dirty
/// so closing it still prompts; the changes since the save would otherwise
/// be lost silently.
#[test]
fn save_then_undo_is_dirty_and_would_prompt() {
    let (mut app, _tmp) = editor();
    place_rock(&mut app, 1.0);
    save(&mut app);
    assert!(!tab_dirty(&app), "saved: clean");
    undo(&mut app);
    app.update();
    assert!(
        tab_dirty(&app),
        "undo past a save re-dirties the tab: closing it must prompt"
    );
    assert!(scene_dirty(&app), "is_scene_dirty agrees");
}

/// Case 6: save, undo, redo: back to the saved content, clean.
#[test]
fn save_undo_redo_is_clean() {
    let (mut app, _tmp) = editor();
    place_rock(&mut app, 1.0);
    save(&mut app);
    undo(&mut app);
    redo(&mut app);
    app.update();
    assert!(!tab_dirty(&app), "redo lands back on the saved content");
    assert!(!scene_dirty(&app), "is_scene_dirty agrees");
}

/// Case 7: edit A, save, undo, edit B. The stack is exactly as deep as it
/// was at the save, but the content differs: dirty, not a false negative.
#[test]
fn save_undo_then_a_different_edit_is_dirty() {
    let (mut app, _tmp) = editor();
    place_rock(&mut app, 1.0);
    save(&mut app);
    let saved_depth = depth(&app);
    undo(&mut app);
    app.update();
    assert!(tab_dirty(&app), "the undo left unsaved content");
    place_rock(&mut app, 2.0);
    assert_eq!(
        depth(&app),
        saved_depth,
        "the stack is exactly as deep as at the save"
    );
    assert!(tab_dirty(&app), "the tab reads dirty: content differs");
    assert!(
        scene_dirty(&app),
        "is_scene_dirty reads dirty: content differs, whatever the stack depth"
    );
}

/// Case 8: edit then save: clean.
#[test]
fn edit_then_save_is_clean() {
    let (mut app, _tmp) = editor();
    place_rock(&mut app, 1.0);
    save(&mut app);
    assert!(!tab_dirty(&app), "the tab reads saved");
    assert!(!scene_dirty(&app), "is_scene_dirty reads saved");
}

// --------------------------------------------------------------- case 10 --

/// Case 10: a modal gesture cancelled with Escape leaves the stack, the
/// dirty flag and the document exactly as they were. The modal below is the
/// framework contract in miniature: a history-creating dispatch of an
/// `allows_undo` modal captures a before-snapshot, the drag mutates a
/// transform while running, and the cancel handler puts the transform back
/// the way `cancel_gizmo_drag` does. Cancelling must throw the snapshot away
/// rather than push it.
mod modal_cancel {
    use super::*;

    #[derive(Resource, Default)]
    struct DraggedTransform {
        entity: Option<Entity>,
        start: Option<Transform>,
    }

    #[derive(Default)]
    struct CancelContractExtension;

    impl JackdawExtension for CancelContractExtension {
        fn id(&self) -> String {
            "test.dirty_cancel".to_string()
        }

        fn register(&self, ctx: &mut ExtensionRegistrar<'_>) {
            ctx.init_resource::<DraggedTransform>();
            ctx.register_operator::<DragOp>();
        }
    }

    #[operator(id = "test.dirty_drag", label = "Drag", modal = true, cancel = cancel_drag)]
    fn drag(
        _: In<OperatorParameters>,
        mut dragged: ResMut<DraggedTransform>,
        mut transforms: Query<&mut Transform>,
        active: ActiveModalQuery,
    ) -> OperatorResult {
        if !active.is_modal_running() {
            let entity = dragged.entity.expect("the test armed the target");
            dragged.start = transforms.get(entity).ok().copied();
            return OperatorResult::Running;
        }
        // The drag itself: move the target every tick, as a gizmo drag does.
        if let Some(entity) = dragged.entity
            && let Ok(mut transform) = transforms.get_mut(entity)
        {
            transform.translation.x += 1.0;
        }
        OperatorResult::Running
    }

    /// The cancel handler, the way a gizmo drag restores its start state.
    fn cancel_drag(world: &mut World) {
        let (entity, start) = {
            let dragged = world.resource::<DraggedTransform>();
            (dragged.entity, dragged.start)
        };
        if let (Some(entity), Some(start)) = (entity, start)
            && let Some(mut transform) = world.get_mut::<Transform>(entity)
        {
            *transform = start;
        }
    }

    #[test]
    fn an_escaped_modal_gesture_leaves_no_entry_no_dirty_no_change() {
        let (mut app, _tmp) = super::editor();
        util::register_and_enable_extension::<CancelContractExtension>(&mut app);
        let zone = super::zone_selected(&mut app);
        app.world_mut().resource_mut::<DraggedTransform>().entity = Some(zone);

        let before = super::depth(&app);
        let before_text = super::scene_text(&mut app);

        // Start the modal the way a toolbar button does: it captures a
        // before-snapshot because the op allows undo.
        app.world_mut()
            .operator(DragOp::ID)
            .settings(jackdaw_api_internal::operator::CallOperatorSettings {
                execution_context: jackdaw_api_internal::operator::ExecutionContext::Invoke,
                creates_history_entry: true,
            })
            .call()
            .expect("the drag starts")
            .assert_running();
        app.update();
        assert!(
            app.world()
                .get::<Transform>(zone)
                .expect("the zone")
                .translation
                .x
                > 0.0,
            "the modal moved the target while running"
        );

        // Escape: the modal-cancel chain, which discards the snapshot.
        app.world_mut()
            .cancel_active_modal()
            .expect("the modal cancels");
        app.update();

        assert_eq!(
            super::depth(&app),
            before,
            "a cancelled gesture leaves no history entry"
        );
        assert!(
            !super::tab_dirty(&app),
            "a cancelled gesture leaves the tab clean"
        );
        assert_eq!(
            super::scene_text(&mut app),
            before_text,
            "the document is back where it started"
        );
    }
}

/// Case 11: X + number + Escape leaves nothing behind: no record, no dirty.
#[test]
fn numeric_entry_cancelled_with_escape_leaves_nothing() {
    use bevy::input_focus::InputFocus;

    let (mut app, _tmp) = editor();
    app.world_mut().resource_mut::<InputFocus>().clear();
    zone_selected(&mut app);
    let before = depth(&app);
    let before_text = scene_text(&mut app);

    let key = |app: &mut App, code: KeyCode| {
        app.world_mut()
            .resource_mut::<ButtonInput<KeyCode>>()
            .press(code);
        run_numeric_transform_input(app.world_mut());
        app.world_mut()
            .resource_mut::<ButtonInput<KeyCode>>()
            .clear();
        run_numeric_transform_input(app.world_mut());
    };

    key(&mut app, KeyCode::KeyX);
    key(&mut app, KeyCode::Digit1);
    assert!(
        app.world()
            .resource::<NumericTransformState>()
            .axis
            .is_some(),
        "the entry is armed"
    );
    key(&mut app, KeyCode::Escape);

    let state = app.world().resource::<NumericTransformState>();
    assert!(state.axis.is_none(), "the entry is cancelled");
    let _ = state;
    assert_eq!(depth(&app), before, "no history entry was made");
    assert!(!tab_dirty(&app), "nothing is dirty");
    assert_eq!(scene_text(&mut app), before_text, "the document is intact");
}

// ------------------------------------------------------------- case 12-14 --

/// Case 12: a duplicate (the operator the right-click entry dispatches)
/// undone takes the copy away and the dirty flag falls with it.
#[test]
fn duplicate_undone_takes_the_copy_and_the_dirty_flag() {
    let (mut app, _tmp) = editor();
    zone_selected(&mut app);
    let before = depth(&app);
    let before_text = scene_text(&mut app);

    super::batch_undo::menu(&mut app, "entity.duplicate", true);
    let duplicated = scene_text(&mut app);
    assert_ne!(duplicated, before_text, "the copy is in the document");
    assert_eq!(depth(&app), before + 1, "the duplicate is one entry");
    assert!(tab_dirty(&app), "the edit dirties the tab");

    undo(&mut app);
    app.update();
    assert_eq!(
        scene_text(&mut app),
        before_text,
        "the copy is gone after one undo"
    );
    assert!(!tab_dirty(&app), "the dirty flag fell back with the undo");
}

/// Case 13: dirty baselines are per tab. A dirty tab keeps its flag across a
/// switch, a clean tab reads clean while another tab holds unsaved edits,
/// and `is_scene_dirty` never compares one tab's stack against another tab's
/// save point.
#[test]
fn dirty_state_survives_tab_switches_per_tab() {
    let (mut app, _tmp) = editor();
    // Tab A (the zone) gets an edit and a save, so its save point is set.
    place_rock(&mut app, 1.0);
    save(&mut app);
    assert!(!tab_dirty(&app), "tab A reads saved");

    // A dirty variant: another edit on A before switching away.
    place_rock(&mut app, 2.0);
    assert!(tab_dirty(&app), "tab A is dirty again");

    // Tab B: a fresh untitled scene, clean by definition.
    run_op_clause(app.world_mut(), "scene.new")
        .expect("a new scene opens")
        .assert_finished();
    app.update();
    assert!(!tab_dirty(&app), "tab B reads clean");
    assert!(
        !scene_dirty(&app),
        "is_scene_dirty reads tab B, not tab A's save point"
    );

    // Back to tab A: its dirty flag is where it was.
    jackdaw::scenes::swap::swap_active_tab(app.world_mut(), 0);
    app.update();
    assert!(tab_dirty(&app), "tab A kept its dirty flag");
    assert!(scene_dirty(&app), "is_scene_dirty reads tab A");
}

/// Case 14: a Resources-panel field edit is one undo entry whose undo
/// rolls the value back. Since the T08-T2 scene-document filter
/// (decision 4-A) a resource edit is editor-session state: it takes an
/// undo slot but does not dirty the scene tab, and undoing it rolls
/// the value back with the tab never having left clean. (The earlier
/// "ruling 3" expectation — the edit dirties the tab — was the very
/// coupling decision 4-A removed; it survived the first T2 pass only
/// because the saved-baseline watcher arm still flipped dirty on any
/// depth change, the QA-1 defect this rework closes.)
#[test]
fn resource_field_edit_undone_rolls_back_and_settles_clean() {
    #[derive(Resource, Reflect, Default, Debug)]
    #[reflect(Resource, Default)]
    struct TestScore {
        points: u32,
    }

    let (mut app, _tmp) = editor();
    app.register_type::<TestScore>()
        .insert_resource(TestScore { points: 7 });
    app.update();
    app.world_mut()
        .insert_resource(jackdaw::inspector::resource_panel::ResourcePanelSelection(
            Some(TestScore::type_path().to_string()),
        ));
    app.update();

    let before = depth(&app);
    app.world_mut()
        .operator("resource.set_field")
        .settings(jackdaw_api_internal::operator::CallOperatorSettings {
            execution_context: jackdaw_api_internal::operator::ExecutionContext::Invoke,
            creates_history_entry: true,
        })
        .param("type_path", TestScore::type_path().to_string())
        .param("field", "points")
        .param("value", "42".to_string())
        .call()
        .expect("resource.set_field dispatch resolves")
        .assert_finished();
    app.update();

    assert_eq!(depth(&app), before + 1, "the edit is one entry");
    assert!(
        app.world().resource::<TestScore>().points == 42,
        "the edit landed"
    );
    assert!(
        !tab_dirty(&app),
        "a session-resource edit shares the history without dirtying the scene tab"
    );

    undo(&mut app);
    app.update();
    assert!(
        app.world().resource::<TestScore>().points == 7,
        "undo rolls the value back"
    );
    assert!(
        !tab_dirty(&app),
        "the document never changed, so the tab is clean throughout"
    );
    assert!(!scene_dirty(&app), "is_scene_dirty agrees");
}

/// A fresh untitled tab starts clean with an empty stack.
#[test]
fn a_fresh_untitled_tab_starts_clean() {
    let mut app = util::editor_test_app();
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    run_op_clause(app.world_mut(), "scene.new")
        .expect("a new scene opens")
        .assert_finished();
    app.update();
    let scenes = app.world().resource::<Scenes>();
    let tab: &SceneTab = &scenes.tabs[scenes.active];
    assert!(!tab.dirty);
    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        0,
        "a new scene has an empty stack"
    );
}
