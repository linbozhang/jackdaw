//! A resource field edit is one undo entry that restores the value. The
//! document snapshot covers no resource state, so the resource command the
//! operator pushes is the whole entry: the stack growing by exactly one
//! also proves no empty snapshot entry appeared.

use bevy::prelude::*;
use bevy::reflect::TypePath;
use jackdaw::AppState;
use jackdaw::inspector::resource_card_text;
use jackdaw::inspector::resource_panel::{ResourceFieldTarget, ResourcePanelSelection};
use jackdaw::prelude::*;
use jackdaw_api_internal::operator::{CallOperatorSettings, ExecutionContext};
use jackdaw_commands::CommandHistory;

use crate::util;
use crate::util::OperatorResultExt;

/// A game's own resource, as a dylib extension would register one.
#[derive(Resource, Reflect, Default, Debug)]
#[reflect(Resource, Default)]
struct TestScore {
    points: u32,
}

/// The editor over a world holding `TestScore`, in the editor state, with
/// the Resources panel's window built and the resource selected in it (the
/// window's own panel is the single instance; spawning a second by hand
/// would only race the refresh pass for which one it maintains).
fn editor_app() -> App {
    let mut app = util::editor_test_app();
    app.register_type::<TestScore>()
        .insert_resource(TestScore { points: 7 });
    app.world_mut()
        .resource_mut::<NextState<AppState>>()
        .set(AppState::Editor);
    for _ in 0..4 {
        app.update();
    }
    // The set-field operator's availability gate reads the panel's
    // selection, so name the resource there before dispatching.
    app.world_mut().insert_resource(ResourcePanelSelection(Some(
        TestScore::type_path().to_string(),
    )));
    app.update();
    app
}

/// Dispatch `resource.set_field` the way a user-facing entry point would.
fn set_points(app: &mut App, value: &str) {
    app.world_mut()
        .operator("resource.set_field")
        .settings(CallOperatorSettings {
            execution_context: ExecutionContext::Invoke,
            creates_history_entry: true,
        })
        .param("type_path", TestScore::type_path().to_string())
        .param("field", "points")
        .param("value", value.to_string())
        .call()
        .expect("resource.set_field dispatch resolves")
        .assert_finished();
}

#[test]
fn a_field_edit_round_trips_through_undo() {
    let mut app = editor_app();
    let stack_before = app.world().resource::<CommandHistory>().undo_stack.len();

    set_points(&mut app, "42");
    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        stack_before + 1,
        "the edit is exactly one entry: the resource command, with no empty document snapshot beside it"
    );
    assert_eq!(
        app.world().resource::<TestScore>().points,
        42,
        "the edit landed on the resource"
    );

    app.world_mut()
        .resource_scope(|world, mut history: Mut<CommandHistory>| history.undo(world));
    assert_eq!(
        app.world().resource::<TestScore>().points,
        7,
        "undo restores the pre-edit value"
    );

    app.world_mut()
        .resource_scope(|world, mut history: Mut<CommandHistory>| history.redo(world));
    assert_eq!(
        app.world().resource::<TestScore>().points,
        42,
        "redo replays the edit"
    );
}

/// A commit that leaves the value as it was pushes nothing, the same rule
/// the document field commit follows.
#[test]
fn a_no_op_edit_pushes_nothing() {
    let mut app = editor_app();
    let stack_before = app.world().resource::<CommandHistory>().undo_stack.len();

    set_points(&mut app, "7");

    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        stack_before,
        "an edit that changes nothing must not bury the stack"
    );
}

/// The panel's card follows a committed edit: it rebuilds and its number
/// widget holds the new value without the row being reselected.
#[test]
fn the_card_shows_the_committed_value() {
    use jackdaw_feathers::number_input::ScrubNumberInputValue;

    let mut app = editor_app();
    let path = TestScore::type_path().to_string();
    for _ in 0..2 {
        app.update();
    }

    set_points(&mut app, "42");
    for _ in 0..8 {
        app.update();
    }

    // The card is up, carrying the resource's fields.
    let text = resource_card_text(app.world_mut(), &path);
    assert!(
        text.iter().any(|line| line.contains("points")),
        "the card names the fields: {text:?}"
    );
    // The number widget for `points` holds the committed value; the text
    // the feathers widget paints follows the same value.
    let mut widgets = app
        .world_mut()
        .query_filtered::<&ScrubNumberInputValue, With<ResourceFieldTarget>>();
    let values: Vec<ScrubNumberInputValue> = widgets.iter(app.world()).cloned().collect();
    assert_eq!(
        values,
        vec![ScrubNumberInputValue::I64(42)],
        "the card's number widget holds the committed value"
    );
}

/// A selected scene entity carrying the same component must not receive a
/// resource card's edit. The write path addresses the resource entity
/// alone and never consults the selection.
#[test]
fn an_edit_never_writes_a_selected_entity_with_the_same_component() {
    let mut app = editor_app();

    let scene = app
        .world_mut()
        .spawn((Name::new("Scene"), TestScore { points: 100 }))
        .id();
    app.world_mut()
        .resource_mut::<jackdaw::selection::Selection>()
        .entities = vec![scene];
    // Let bevy's resource uniqueness settle whatever it does to the
    // duplicate on the scene entity.
    app.update();

    set_points(&mut app, "42");
    assert_eq!(
        app.world().resource::<TestScore>().points,
        42,
        "the edit landed on the resource"
    );
    match app.world().get::<TestScore>(scene) {
        None => {}
        Some(score) => assert_eq!(
            score.points, 100,
            "the selected scene entity keeps its own value"
        ),
    }
}
