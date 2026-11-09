//! The Sprite Atlas: a compiled kind the New Asset list offers, its card, and
//! the grid operator that cuts the open layout into frames.

use crate::util;

use bevy::prelude::*;
use jackdaw::definition_assets::{DefinitionAssetEdit, OpenDefinition};
use jackdaw_api::prelude::*;
use jackdaw_api_internal::operator::{CallOperatorSettings, ExecutionContext};

/// An editor with a project of its own. The sprite plugins are in, so the
/// atlas layout type is registered the way a session has it.
fn editor_with_project() -> (App, tempfile::TempDir) {
    let tmp = tempfile::tempdir().expect("tempdir");
    std::fs::create_dir_all(tmp.path().join("assets/content")).expect("a content folder");
    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    app.world_mut()
        .spawn(jackdaw::layout::inspector_components_content());
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    for _ in 0..8 {
        app.update();
    }
    (app, tmp)
}

fn call(app: &mut App, id: &'static str, params: &[(&'static str, String)]) {
    let mut call = app.world_mut().operator(id).settings(CallOperatorSettings {
        execution_context: ExecutionContext::Invoke,
        creates_history_entry: false,
    });
    for (key, value) in params {
        call = call.param(*key, value.clone());
    }
    let result = call.call().expect("the operator dispatched");
    assert_eq!(result, OperatorResult::Finished, "{id} finished");
    for _ in 0..8 {
        app.update();
    }
}

#[test]
fn a_sprite_atlas_is_creatable_and_the_grid_cuts_it_into_frames() {
    let (mut app, tmp) = editor_with_project();

    call(
        &mut app,
        "asset.new",
        &[
            ("type", "sprite_atlas".to_string()),
            ("name", "sheet".to_string()),
            ("path", "content".to_string()),
        ],
    );

    let file = tmp.path().join("assets/content/sheet.bsn");
    assert!(
        file.is_file(),
        "the atlas file was written: {:?}",
        std::fs::read_dir(tmp.path().join("assets/content")).map(|entries| entries
            .filter_map(Result::ok)
            .map(|entry| entry.file_name())
            .collect::<Vec<_>>())
    );
    let open = app
        .world()
        .resource::<OpenDefinition>()
        .0
        .expect("the new atlas is open in the inspector");
    let edit = app
        .world()
        .get::<DefinitionAssetEdit>(open)
        .expect("the card stands for the file just written");
    assert_eq!(edit.name, "sheet");

    call(
        &mut app,
        "sprite.atlas.grid",
        &[
            ("tile_size", "32,16".to_string()),
            ("columns", "2".to_string()),
            ("rows", "3".to_string()),
        ],
    );

    let layout = app
        .world()
        .resource::<Assets<bevy::image::TextureAtlasLayout>>()
        .iter()
        .next()
        .map(|(_, layout)| layout.clone())
        .expect("the editor holds the layout the card edits");
    assert_eq!(layout.textures.len(), 6, "two columns by three rows");
    assert_eq!(layout.size, bevy::math::UVec2::new(64, 48));
    assert_eq!(
        layout.textures[1].min,
        bevy::math::UVec2::new(32, 0),
        "frames index left to right"
    );
    assert_eq!(
        layout.textures[2].min,
        bevy::math::UVec2::new(0, 16),
        "and top to bottom"
    );

    // The whole-value write went through the undo history, so one undo puts
    // the empty default layout back.
    let before = app
        .world()
        .resource::<jackdaw_commands::CommandHistory>()
        .undo_stack
        .len();
    assert!(before > 0, "the grid cut is one undo entry");
    let _ = app
        .world_mut()
        .operator("history.undo")
        .call()
        .expect("undo dispatched");
    for _ in 0..8 {
        app.update();
    }
    assert_eq!(
        app.world()
            .resource::<jackdaw_commands::CommandHistory>()
            .undo_stack
            .len(),
        before - 1,
        "undo took the grid cut back"
    );
    let layout = app
        .world()
        .resource::<Assets<bevy::image::TextureAtlasLayout>>()
        .iter()
        .next()
        .map(|(_, layout)| layout.clone())
        .expect("the layout stays after undo");
    assert_eq!(
        layout.textures.len(),
        0,
        "undo put back the default the file was created with"
    );
}

#[test]
fn the_grid_refuses_to_run_without_a_tile_size() {
    let (mut app, _tmp) = editor_with_project();
    call(
        &mut app,
        "asset.new",
        &[("type", "sprite_atlas".to_string())],
    );
    let result = app
        .world_mut()
        .operator("sprite.atlas.grid")
        .settings(CallOperatorSettings {
            execution_context: ExecutionContext::Invoke,
            creates_history_entry: false,
        })
        .param("columns", 2i64)
        .param("rows", 2i64)
        .call()
        .expect("the operator dispatched");
    assert_eq!(result, OperatorResult::Cancelled);
    for _ in 0..8 {
        app.update();
    }
    let frames = app
        .world()
        .resource::<Assets<bevy::image::TextureAtlasLayout>>()
        .iter()
        .next()
        .map(|(_, layout)| layout.textures.len())
        .unwrap_or_default();
    assert_eq!(frames, 0, "nothing was cut");
}
