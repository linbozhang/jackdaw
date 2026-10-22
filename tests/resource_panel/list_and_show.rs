//! The Resources panel in the editor: rows for what the world holds, a
//! card for the one selected, and the hints when there is nothing to
//! show.

use bevy::prelude::*;
use bevy::reflect::TypePath;
use jackdaw::AppState;
use jackdaw::inspector::resource_panel::{
    ResourceCardEmpty, ResourcePanelSelection, ResourceRowButton, resource_panel_content,
};
use jackdaw::inspector::{resource_card_text, resource_panel_rows};

use crate::util;

/// A game's own resource, as a dylib extension would register one.
#[derive(Resource, Reflect, Default, Debug)]
#[reflect(Resource, Default)]
struct TestScore {
    points: u32,
}

/// The editor over a world holding `TestScore`, with the panel's content
/// spawned and the editor state entered, so the panel's Update pass has
/// run.
fn editor_app() -> App {
    let mut app = util::editor_test_app();
    app.register_type::<TestScore>()
        .insert_resource(TestScore { points: 7 });
    app.world_mut().spawn(resource_panel_content());
    app.world_mut()
        .resource_mut::<NextState<AppState>>()
        .set(AppState::Editor);
    for _ in 0..4 {
        app.update();
    }
    app
}

#[test]
fn rows_cover_game_and_engine_resources_but_not_denied_ones() {
    let mut app = editor_app();

    let rows = resource_panel_rows(app.world_mut());
    assert!(
        rows.iter().any(|name| name == "TestScore"),
        "the game resource is listed: {rows:?}"
    );
    assert!(
        rows.iter().any(|name| name.contains("AmbientLight")),
        "the global ambient light is listed: {rows:?}"
    );
    assert!(
        !rows.iter().any(|name| name.contains("Assets")),
        "asset storages are denied: {rows:?}"
    );
    assert!(
        !rows.iter().any(|name| name.contains("Real")),
        "the real clock stays hidden: {rows:?}"
    );

    // The allowlist's spelling of the generic clocks matches what the
    // registry reports, which is the one thing a string allowlist can
    // silently get wrong.
    let mut buttons = app.world_mut().query::<&ResourceRowButton>();
    let paths: Vec<String> = buttons
        .iter(app.world())
        .map(|button| button.type_path.clone())
        .collect();
    assert!(
        paths
            .iter()
            .any(|path| path == "bevy_time::time::Time<bevy_time::virt::Virtual>"),
        "Time<Virtual> is listed by its registry path: {paths:?}"
    );
}

#[test]
fn selecting_a_resource_shows_its_fields() {
    let mut app = editor_app();
    let path = TestScore::type_path().to_string();
    app.world_mut()
        .insert_resource(ResourcePanelSelection(Some(path.clone())));
    for _ in 0..4 {
        app.update();
    }

    let text = resource_card_text(app.world_mut(), &path);
    assert!(
        text.iter().any(|line| line.contains("points")),
        "the card names the fields: {text:?}"
    );
    assert!(
        text.iter().any(|line| line.contains("TestScore")),
        "the card names the resource: {text:?}"
    );
}

#[test]
fn without_a_selection_the_panel_says_so() {
    let mut app = editor_app();

    let mut hints = app
        .world_mut()
        .query_filtered::<&Text, With<ResourceCardEmpty>>();
    let hint = hints
        .iter(app.world())
        .next()
        .expect("the no-selection hint is up");
    assert_eq!(
        hint.0, "Select a resource to inspect its fields.",
        "the hint carries its localized text, not its key"
    );
}
