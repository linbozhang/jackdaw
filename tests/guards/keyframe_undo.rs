//! Keyframe delete / paste / toggle and the document: a deleted keyframe
//! leaves the AST (no ghost revival through a document respawn), an undone
//! delete restores exactly one keyframe (no duplicate registration), and a
//! toggled keyframe carries its own undo entry (R1).

use bevy::input_focus::InputFocus;
use bevy::prelude::*;
use jackdaw::boot_ops::{run_op_clause, run_op_clause_as_user};
use jackdaw::panel_focus::LastPressedPanel;
use jackdaw_animation::Vec3Keyframe;
use jackdaw_api::prelude::*;

use super::batch_undo::{depth, scene_text};
use crate::util::{self, OperatorResultExt as _};

const TRANSFORM: &str = "bevy_transform::components::transform::Transform";

/// An editor in the editor state with an untitled scene, the timeline
/// focused the way the panel-focus chain would have it.
fn editor() -> App {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-keyframe-undo-")
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
    app
}

/// A named, registered, selected entity with a translation key at t=0.
fn entity_with_key(app: &mut App) -> (Entity, Entity) {
    let target = app
        .world_mut()
        .spawn((Name::new("Cube"), Transform::default()))
        .id();
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), target);
    jackdaw::selection::select_only(app.world_mut(), target);
    app.update();

    app.world_mut()
        .operator("animation.toggle_keyframe")
        .param("entity", target)
        .param("component_type_path", TRANSFORM)
        .param("field_path", "translation")
        .call()
        .expect("the toggle dispatches")
        .assert_finished();
    app.update();
    app.update();

    let keyframe = app
        .world_mut()
        .query::<(Entity, &Vec3Keyframe)>()
        .iter(app.world())
        .map(|(entity, _)| entity)
        .next()
        .expect("the keyframe exists");
    (target, keyframe)
}

/// Focus the timeline panel, the way a press inside it would have, with the
/// keyboard free (a text field holding it would stand the gate down).
fn focus_timeline(app: &mut App) {
    app.world_mut().resource_mut::<LastPressedPanel>().0 = Some("jackdaw.timeline".to_string());
    app.world_mut().resource_mut::<InputFocus>().clear();
    app.update();
}

fn select(app: &mut App, entity: Entity) {
    jackdaw::selection::select_only(app.world_mut(), entity);
    if let Ok(mut ec) = app.world_mut().get_entity_mut(entity) {
        ec.insert(jackdaw::selection::Selected);
    }
    app.update();
}

/// How many keyframes the document holds: the count of `Vec3Keyframe`
/// patches the emitted text carries (the type path names each patch once).
fn keyframe_count(app: &mut App) -> usize {
    scene_text(app).matches("Vec3Keyframe").count()
}

fn live_keyframes(app: &mut App) -> usize {
    app.world_mut()
        .query::<&Vec3Keyframe>()
        .iter(app.world())
        .count()
}

/// Delete the selected keyframe through the timeline op.
fn delete_selected(app: &mut App) {
    focus_timeline(app);
    app.world_mut()
        .operator("clip.delete_keyframes")
        .call()
        .expect("the delete dispatches")
        .assert_finished();
    app.update();
    app.update();
}

fn undo(app: &mut App) {
    super::batch_undo::history(app, "history.undo");
    app.update();
    app.update();
}

/// Symptom 1: delete, undo, and the timeline (and the document) hold exactly
/// the one keyframe that was there before, not a duplicate node beside the
/// restored one.
#[test]
fn delete_then_undo_restores_exactly_one_keyframe() {
    let mut app = editor();
    let (_target, keyframe) = entity_with_key(&mut app);
    assert_eq!(keyframe_count(&mut app), 1, "one keyframe to start");
    let before = depth(&app);

    select(&mut app, keyframe);
    delete_selected(&mut app);
    assert_eq!(live_keyframes(&mut app), 0, "the keyframe is gone");
    assert_eq!(keyframe_count(&mut app), 0, "and out of the document");
    assert_eq!(depth(&app), before + 1, "the delete is one entry");

    undo(&mut app);
    assert_eq!(
        live_keyframes(&mut app),
        1,
        "the undo restores the keyframe entity"
    );
    assert_eq!(
        keyframe_count(&mut app),
        1,
        "exactly one keyframe node: no watcher-registered duplicate"
    );
}

/// Symptom 2: a deleted keyframe stays dead through a document-respawn undo.
/// With the AST left behind by the delete, the next snapshot entry's undo
/// would resurrect the keyframe from the stale document.
#[test]
fn a_deleted_keyframe_stays_dead_through_a_document_undo() {
    let mut app = editor();
    let (_target, keyframe) = entity_with_key(&mut app);

    select(&mut app, keyframe);
    delete_selected(&mut app);
    assert_eq!(keyframe_count(&mut app), 0, "the keyframe is out");

    // A snapshot entry above the delete, then undo it: the document
    // respawns from its before-snapshot, which must not contain the
    // deleted keyframe.
    run_op_clause_as_user(app.world_mut(), "entity.add.cube")
        .expect("the cube dispatches")
        .assert_finished();
    app.update();
    undo(&mut app);

    assert_eq!(
        live_keyframes(&mut app),
        0,
        "the deleted keyframe is not resurrected by the respawn"
    );
    assert_eq!(keyframe_count(&mut app), 0, "nor by the document");
}

/// N3: a toggled keyframe is its own undo entry when dispatched the way a
/// user-facing entry point does, and the undo takes it back out of the
/// document cleanly.
#[test]
fn toggle_keyframe_is_one_entry_and_undoes() {
    let mut app = editor();
    let target = app
        .world_mut()
        .spawn((Name::new("Cube"), Transform::default()))
        .id();
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), target);
    jackdaw::selection::select_only(app.world_mut(), target);
    app.update();
    let before = depth(&app);

    app.world_mut()
        .operator("animation.toggle_keyframe")
        .settings(jackdaw_api_internal::operator::CallOperatorSettings {
            execution_context: jackdaw_api_internal::operator::ExecutionContext::Invoke,
            creates_history_entry: true,
        })
        .param("entity", target)
        .param("component_type_path", TRANSFORM)
        .param("field_path", "translation")
        .call()
        .expect("the toggle dispatches")
        .assert_finished();
    app.update();

    assert_eq!(
        depth(&app),
        before + 1,
        "the toggle carries its own undo entry, not silence until the next edit"
    );
    assert_eq!(live_keyframes(&mut app), 1);
    assert_eq!(keyframe_count(&mut app), 1);

    undo(&mut app);
    assert_eq!(
        live_keyframes(&mut app),
        0,
        "one undo takes the keyframe away"
    );
    assert_eq!(keyframe_count(&mut app), 0, "and out of the document");
}

/// The delete through the timeline needs the timeline focused; the focus
/// wiring above must satisfy the availability gate.
#[test]
fn the_delete_gate_accepts_a_focused_timeline() {
    let mut app = editor();
    let (_target, keyframe) = entity_with_key(&mut app);
    select(&mut app, keyframe);
    focus_timeline(&mut app);
    assert!(
        app.world_mut()
            .operator("clip.delete_keyframes")
            .is_available()
            .expect("the gate runs"),
        "a focused timeline with a selected keyframe makes the delete available"
    );
}

// ------------------------------------------------------- keybind paths ---

/// Dispatch the way the Delete/Backspace and Ctrl+V keybinds do (the F3
/// palette and command entries take the same road): `Invoke` with
/// `creates_history_entry: true`, the setting a self-pushing operator must
/// stay single-record under.
fn keybind(app: &mut App, id: &'static str) {
    app.world_mut()
        .operator(id)
        .settings(jackdaw_api_internal::operator::CallOperatorSettings {
            execution_context: jackdaw_api_internal::operator::ExecutionContext::Invoke,
            creates_history_entry: true,
        })
        .call()
        .unwrap_or_else(|err| panic!("{id}: {err}"))
        .assert_finished();
    app.update();
    app.update();
}

/// The Delete keybind is one entry, and undoing everything it left behind
/// restores exactly the one keyframe that was there. A second record (a
/// framework snapshot beside the operator's own command group) would undo
/// into a duplicate keyframe — the R1 symptom on a real user path.
#[test]
fn the_delete_keybind_is_one_entry_and_undoes_to_one_keyframe() {
    let mut app = editor();
    let (_target, keyframe) = entity_with_key(&mut app);
    select(&mut app, keyframe);
    focus_timeline(&mut app);
    let before = depth(&app);

    keybind(&mut app, "clip.delete_keyframes");
    assert_eq!(live_keyframes(&mut app), 0, "the keyframe is deleted");
    assert_eq!(
        depth(&app),
        before + 1,
        "the keybind delete is ONE entry: the operator pushes its own group, \
         and the framework must not snapshot the same change beside it"
    );

    // Undo every entry the delete left. Two entries restore the keyframe
    // twice (the snapshot respawns the document copy while the command
    // group respawns its own), which is the duplicate the QA probe saw.
    while depth(&app) > before {
        undo(&mut app);
    }
    assert_eq!(
        live_keyframes(&mut app),
        1,
        "undoing the whole delete leaves exactly the one keyframe"
    );
    assert_eq!(keyframe_count(&mut app), 1, "and one document node");
}

/// The Ctrl+V keybind pastes the clipboard as one entry whose single undo
/// takes the pasted keyframe back out.
#[test]
fn the_paste_keybind_is_one_entry_and_undoes_cleanly() {
    let mut app = editor();
    let (_target, keyframe) = entity_with_key(&mut app);
    select(&mut app, keyframe);
    focus_timeline(&mut app);
    keybind(&mut app, "clip.copy_keyframes");
    assert_eq!(depth(&app), 0, "the copy records nothing");
    let before = depth(&app);

    keybind(&mut app, "clip.paste_keyframes");
    assert_eq!(
        live_keyframes(&mut app),
        2,
        "the pasted keyframe exists beside the original"
    );
    assert_eq!(
        depth(&app),
        before + 1,
        "the keybind paste is ONE entry: the operator pushes its own group"
    );

    undo(&mut app);
    assert_eq!(
        live_keyframes(&mut app),
        1,
        "one undo takes only the pasted keyframe away"
    );
    assert_eq!(
        keyframe_count(&mut app),
        1,
        "and the document holds one node"
    );
}
