//! Adding and removing a resource through the panel's operators: the
//! world's resource-entity cache closes the loop (the panel lists what the
//! cache knows), and both directions survive undo and redo.

use bevy::prelude::*;
use bevy::reflect::TypePath;
use jackdaw::AppState;
use jackdaw::inspector::resource_panel::ResourcePanelSelection;
use jackdaw::inspector::resource_panel_rows;
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

/// The editor with `TestScore` registered but not instantiated, in the
/// editor state with the Resources panel's window built.
fn editor_app() -> App {
    let mut app = util::editor_test_app();
    app.register_type::<TestScore>();
    app.world_mut()
        .resource_mut::<NextState<AppState>>()
        .set(AppState::Editor);
    for _ in 0..4 {
        app.update();
    }
    app
}

/// Dispatch an operator the way a user-facing entry point would.
fn dispatch(app: &mut App, id: &'static str, type_path: &str) {
    app.world_mut()
        .operator(id)
        .settings(CallOperatorSettings {
            execution_context: ExecutionContext::Invoke,
            creates_history_entry: true,
        })
        .param("type_path", type_path.to_string())
        .call()
        .unwrap_or_else(|err| panic!("{id}: dispatch errored: {err}"))
        .assert_finished();
}

/// The `ComponentId` the world knows `TestScore` by, once anything has
/// registered it.
fn component_id(app: &mut App) -> bevy::ecs::component::ComponentId {
    app.world_mut()
        .components()
        .get_id(std::any::TypeId::of::<TestScore>())
        .expect("TestScore is registered with the world")
}

#[test]
fn insert_round_trips_through_undo() {
    let mut app = editor_app();
    let type_path = TestScore::type_path().to_string();
    let stack_before = app.world().resource::<CommandHistory>().undo_stack.len();

    assert!(
        app.world().get_resource::<TestScore>().is_none(),
        "the resource starts out absent"
    );

    dispatch(&mut app, "resource.insert", &type_path);
    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        stack_before + 1,
        "the insert is one entry, with no empty document snapshot beside it"
    );
    assert_eq!(
        app.world().resource::<TestScore>().points,
        0,
        "the inserted resource is the type's default"
    );
    let score_id = component_id(&mut app);
    assert!(
        app.world().resource_entities().get(score_id).is_some(),
        "the world's resource-entity cache knows the inserted resource"
    );

    // The panel lists it, and the operator's auto-selection opens its card.
    for _ in 0..4 {
        app.update();
    }
    let rows = resource_panel_rows(app.world_mut());
    assert!(
        rows.iter().any(|name| name == "TestScore"),
        "the panel lists the inserted resource: {rows:?}"
    );

    // Undo takes it back out; the cache and the panel follow.
    app.world_mut()
        .resource_scope(|world, mut history: Mut<CommandHistory>| history.undo(world));
    assert!(
        app.world().get_resource::<TestScore>().is_none(),
        "undo removes the inserted resource"
    );
    let phantom = app
        .world()
        .resource_entities()
        .get(score_id)
        .filter(|&entity| app.world().get_entity(entity).is_ok());
    assert!(
        phantom.is_none(),
        "the cache names no phantom after the undo"
    );
    for _ in 0..4 {
        app.update();
    }
    let rows = resource_panel_rows(app.world_mut());
    assert!(
        !rows.iter().any(|name| name == "TestScore"),
        "the panel drops the removed row: {rows:?}"
    );

    // Redo brings it back.
    app.world_mut()
        .resource_scope(|world, mut history: Mut<CommandHistory>| history.redo(world));
    assert_eq!(
        app.world().resource::<TestScore>().points,
        0,
        "redo re-inserts the resource"
    );
}

#[test]
fn remove_round_trips_and_restores_the_value() {
    let mut app = editor_app();
    let type_path = TestScore::type_path().to_string();
    // A resource the game itself holds, with a non-default value.
    app.insert_resource(TestScore { points: 5 });
    for _ in 0..4 {
        app.update();
    }
    // The remove operator's availability gate reads the panel's selection.
    app.world_mut()
        .insert_resource(ResourcePanelSelection(Some(type_path.clone())));
    app.update();

    dispatch(&mut app, "resource.remove", &type_path);
    assert!(
        app.world().get_resource::<TestScore>().is_none(),
        "the resource is gone"
    );
    for _ in 0..4 {
        app.update();
    }
    let rows = resource_panel_rows(app.world_mut());
    assert!(
        !rows.iter().any(|name| name == "TestScore"),
        "the panel drops the row: {rows:?}"
    );

    app.world_mut()
        .resource_scope(|world, mut history: Mut<CommandHistory>| history.undo(world));
    assert_eq!(
        app.world().resource::<TestScore>().points,
        5,
        "undo restores the resource with the value it had"
    );
}

/// Inserting a type that is not a resource, or not constructible, pushes
/// nothing and changes nothing.
#[test]
fn an_unconstructible_type_inserts_nothing() {
    let mut app = editor_app();
    let stack_before = app.world().resource::<CommandHistory>().undo_stack.len();

    dispatch(&mut app, "resource.insert", "bevy_ecs::entity::Entity");
    // `Name` is a plain component: not a resource, so not insertable.
    dispatch(&mut app, "resource.insert", "bevy_ecs::name::Name");

    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        stack_before,
        "neither call left an entry"
    );
}
