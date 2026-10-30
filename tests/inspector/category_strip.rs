//! The category strip's discoverability surfaces: tab hover tooltips with
//! descriptions, and the always-on category header above the card list.

use bevy::prelude::*;
use jackdaw::selection::Selection;
use jackdaw_api::prelude::*;
use jackdaw_api_internal::operator::{CallOperatorSettings, ExecutionContext};

use crate::util;

fn settle(app: &mut App) {
    for _ in 0..6 {
        app.update();
    }
}

fn show_category(app: &mut App, category: &'static str) {
    let result = app
        .world_mut()
        .operator("inspector.category")
        .settings(CallOperatorSettings {
            execution_context: ExecutionContext::Invoke,
            creates_history_entry: false,
        })
        .param(
            "category",
            jackdaw_scene_types::PropertyValue::from(category),
        )
        .call()
        .expect("the operator dispatched");
    assert_eq!(result, OperatorResult::Finished, "the category is shown");
    settle(app);
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

/// An editor with an inspector panel: the default dock tree opens the
/// inspector window (whose content carries the strip mount and the header
/// node), so no content is spawned manually here.
fn app_with_panel() -> App {
    let mut app = util::editor_test_app();
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    app
}

/// Every seeded tab carries a tooltip whose title is the category label and
/// whose description is the registry's one-liner, so a long hover over the
/// 30px icon strip answers "what lives behind this tab".
#[test]
fn category_tabs_carry_title_and_description_tooltips() {
    let mut app = app_with_panel();
    settle(&mut app);

    let mut tooltips = jackdaw::inspector::category_tab_tooltips(app.world_mut());
    tooltips.sort();
    let mut expected: Vec<(String, String)> = [
        (
            "Object",
            "Identity, transform and visibility: what this entity is.",
        ),
        ("Mesh", "Brush geometry for this entity."),
        ("Modifiers", "Geometry modifiers applied to the brush."),
        (
            "Material",
            "The material assets this entity's surfaces wear.",
        ),
        ("Physics", "Colliders and rigid bodies."),
        // The audio tab (T16): the strip spawns a tab per registered
        // category, and audio registered its own alongside the six seeds.
        (
            "Audio",
            "How this entity sounds: playback, bus and listening.",
        ),
        (
            "Components",
            "Every other component on this entity. Add one here.",
        ),
    ]
    .into_iter()
    .map(|(title, description)| (title.into(), description.into()))
    .collect();
    expected.sort();
    assert_eq!(tooltips, expected, "one described tooltip per seeded tab");
}

/// The header above the card list names the category being viewed: it
/// follows tab clicks, and it follows the sticky resolution a selection
/// switch triggers (a Transform-only entity has no Components card, so the
/// stale Components tab resolves back to Object).
#[test]
fn active_category_label_follows_tabs_and_selection_switches() {
    let mut app = app_with_panel();

    let entity = app
        .world_mut()
        .spawn((Name::new("cube"), Transform::from_xyz(0.0, 0.0, 0.0)))
        .id();
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), entity);
    settle(&mut app);

    // Default category: object.
    select(&mut app, entity);
    assert_eq!(
        jackdaw::inspector::active_category_label(app.world_mut()).as_deref(),
        Some("Object"),
        "the header starts on the default category"
    );

    // Manual tab click writes the resource; the header follows.
    show_category(&mut app, "components");
    assert_eq!(
        jackdaw::inspector::active_category_label(app.world_mut()).as_deref(),
        Some("Components"),
        "the header follows a manual tab switch"
    );

    // Re-selecting the same Transform-only entity rebuilds the cards; the
    // sticky resolver leaves the card-less Components tab and the header
    // shows the resolved category.
    select(&mut app, entity);
    assert_eq!(
        jackdaw::inspector::active_category_label(app.world_mut()).as_deref(),
        Some("Object"),
        "the header follows the sticky resolution across a selection switch"
    );

    show_category(&mut app, "object");
    assert_eq!(
        jackdaw::inspector::active_category_label(app.world_mut()).as_deref(),
        Some("Object")
    );
}
