//! An edit in flight when the selection moves must land on the entity it was
//! aimed at -- or be dropped loudly -- never on the entity the user moved to.
//!
//! The commit chain resolves its write targets from the selection *at commit
//! time*, while each field control is bound to the entity it was built for.
//! Between a selection change and the rebuild that despawns the old card,
//! those two disagree: the race this file pins down.

use std::sync::{Arc, Mutex};

use bevy::prelude::*;
use bevy::ui_widgets::ValueChange;
use jackdaw::commands::{CommandHistory, STALE_FIELD_EDIT_DROPPED};
use jackdaw::selection::{Selected, Selection};
use tracing::Subscriber;
use tracing::field::Visit;
use tracing_subscriber::layer::Layer;
use tracing_subscriber::prelude::*;

use crate::util;

const TRANSFORM: &str = "bevy_transform::components::transform::Transform";

fn settle(app: &mut App) {
    for _ in 0..6 {
        app.update();
    }
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

/// Move the selection without settling first: the change shares the frame
/// that follows, exactly like an outliner click landing in the same frame as
/// a field commit. Writes the immediate half of `select_single` (the ordered
/// list) directly -- `resource_scope` would take the resource out and its
/// first queued command would run the pending edit against a selection-less
/// world.
fn select_in_the_same_frame(world: &mut World, entity: Entity) {
    let previous: Vec<Entity> = world.resource::<Selection>().entities.clone();
    // `Commands` is not `Drop`: the queued markers wait for the next flush,
    // which is exactly the split a real click has inside one frame.
    {
        let mut commands = world.commands();
        for prior in previous {
            if prior != entity
                && let Ok(mut ec) = commands.get_entity(prior)
            {
                ec.remove::<Selected>();
            }
        }
        if let Ok(mut ec) = commands.get_entity(entity) {
            ec.insert(Selected);
        }
    }
    let mut selection = world.resource_mut::<Selection>();
    selection.entities.clear();
    selection.entities.push(entity);
}

/// Bring `entity` into the selection, leaving the current primary in place.
fn extend_selection(app: &mut App, entity: Entity) {
    let world = app.world_mut();
    world.resource_scope(|world, mut selection: Mut<Selection>| {
        let mut commands = world.commands();
        selection.extend(&mut commands, entity);
    });
    world.flush();
    settle(app);
}

/// An editor with an inspector panel and two document entities, the first
/// selected.
fn app_with_two_entities() -> (App, Entity, Entity) {
    let mut app = util::editor_test_app();
    app.world_mut()
        .spawn(jackdaw::layout::inspector_components_content(default()));
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    let spawn = |app: &mut App, name: &str, y: f32| {
        let entity = app
            .world_mut()
            .spawn((
                Name::new(name.to_string()),
                Transform::from_xyz(0.0, y, 0.0),
            ))
            .id();
        jackdaw::scene_io::register_entity_in_ast(app.world_mut(), entity);
        entity
    };
    let first = spawn(&mut app, "first", 1.0);
    let second = spawn(&mut app, "second", 2.0);
    select(&mut app, first);
    (app, first, second)
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

fn height(app: &App, entity: Entity) -> f32 {
    app.world()
        .get::<Transform>(entity)
        .expect("transform")
        .translation
        .y
}

fn undo_depth(app: &App) -> usize {
    app.world().resource::<CommandHistory>().undo_stack.len()
}

/// Commit `value` on `row`, then move the selection to `next` before the
/// frame runs -- the race window, in one frame.
fn commit_then_switch(app: &mut App, row: Entity, value: f64, next: Entity) {
    app.world_mut().trigger(ValueChange {
        source: row,
        value,
        is_final: true,
    });
    select_in_the_same_frame(app.world_mut(), next);
    app.update();
    settle(app);
}

#[test]
fn an_edit_committed_as_the_selection_moves_writes_neither_entity() {
    let (mut app, first, second) = app_with_two_entities();
    let row = field(&mut app, TRANSFORM, "translation.y");
    let before = undo_depth(&app);

    commit_then_switch(&mut app, row, 4.0, second);

    assert_eq!(
        height(&app, second),
        2.0,
        "the entity the user moved to was not written"
    );
    assert_eq!(
        height(&app, first),
        1.0,
        "the stale edit was dropped, not written to the old target"
    );
    assert_eq!(
        undo_depth(&app),
        before,
        "the dropped edit left no undo entry"
    );
}

/// Multi-edit is the standing behavior: with both entities selected, one
/// commit from the primary's card writes the group.
#[test]
fn an_edit_while_two_entities_are_selected_still_writes_both() {
    let (mut app, first, second) = app_with_two_entities();
    extend_selection(&mut app, second);

    let row = field(&mut app, TRANSFORM, "translation.y");
    app.world_mut().trigger(ValueChange {
        source: row,
        value: 4.0,
        is_final: true,
    });
    app.update();
    settle(&mut app);

    assert_eq!(height(&app, first), 4.0, "the write reaches the group");
    assert_eq!(height(&app, second), 4.0, "the write reaches the primary");
}

/// After the same-frame switch settles, no field control may still be bound
/// to an entity the user has left.
#[test]
fn after_the_same_frame_switch_no_binding_outlives_the_selection() {
    let (mut app, _first, second) = app_with_two_entities();
    let row = field(&mut app, TRANSFORM, "translation.y");

    commit_then_switch(&mut app, row, 4.0, second);

    let selection = app.world().resource::<Selection>().entities.clone();
    let mut widgets = app.world_mut().query::<Entity>();
    let stale: Vec<Entity> = widgets
        .iter(app.world())
        .filter(|widget| {
            jackdaw::inspector::field_binding_entity(app.world(), *widget)
                .is_some_and(|bound| !selection.contains(&bound))
        })
        .collect();
    assert!(
        stale.is_empty(),
        "every live field binding names a selected entity, but {stale:?} do not"
    );
}

/// A thread-local tracing layer that keeps every event's message.
struct Messages(Arc<Mutex<Vec<String>>>);

impl<S: Subscriber> Layer<S> for Messages {
    fn on_event(
        &self,
        event: &tracing::Event<'_>,
        _ctx: tracing_subscriber::layer::Context<'_, S>,
    ) {
        let mut message = String::new();
        event.record(&mut Collector(&mut message));
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .push(message);
    }
}

/// Collects the formatted `message` field of one event.
struct Collector<'a>(&'a mut String);

impl Visit for Collector<'_> {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        if field.name() == "message" {
            self.0.push_str(&format!("{value:?}"));
        }
    }
}

/// The drop the race test asserts by value must also be audible: the log
/// carries the const string QA greps for. Recorded through a thread-local
/// subscriber, which sees everything the app logs on this thread regardless
/// of which test built the process-global one.
#[test]
fn the_dropped_edit_says_so_in_the_log() {
    let (mut app, _first, second) = app_with_two_entities();
    let row = field(&mut app, TRANSFORM, "translation.y");
    let sink = Arc::new(Mutex::new(Vec::new()));
    let subscriber = tracing_subscriber::registry().with(Messages(Arc::clone(&sink)));

    tracing::subscriber::with_default(subscriber, || {
        commit_then_switch(&mut app, row, 4.0, second);
    });

    let messages = sink
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .join("\n");
    assert!(
        messages.contains(STALE_FIELD_EDIT_DROPPED),
        "the drop is audible, but the log said:\n{messages}"
    );
}
