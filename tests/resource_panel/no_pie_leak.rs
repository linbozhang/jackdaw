//! A resource edit never leaks into the PIE live stream: even in Live
//! mode, with a projection that (however wrongly) names the resource
//! entity, the write belongs to the editor's own session state alone.

use bevy::prelude::*;
use bevy::reflect::TypePath;
use jackdaw::AppState;
use jackdaw::inspector::resource_panel::ResourcePanelSelection;
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

#[test]
fn resource_edits_do_not_stream_to_pie_in_live_mode() {
    let mut app = editor_app();

    // Live mode, with a hostile projection: the resource entity mapped to
    // game-side bits, the way a projected preview entity would be.
    *app.world_mut()
        .resource_mut::<jackdaw::pie_mirror::PieViewMode>() =
        jackdaw::pie_mirror::PieViewMode::Live;
    let resource_entity = {
        let component_id = app
            .world_mut()
            .components()
            .get_id(std::any::TypeId::of::<TestScore>())
            .expect("TestScore is registered with the world");
        app.world()
            .resource_entities()
            .get(component_id)
            .expect("the resource is instantiated")
    };
    app.world_mut()
        .resource_mut::<jackdaw::pie_projection::PieProjection>()
        .by_bits
        .insert(1, resource_entity);

    let stack_before = app.world().resource::<CommandHistory>().undo_stack.len();
    app.world_mut()
        .operator("resource.set_field")
        .settings(CallOperatorSettings {
            execution_context: ExecutionContext::Invoke,
            creates_history_entry: true,
        })
        .param("type_path", TestScore::type_path().to_string())
        .param("field", "points")
        .param("value", "42")
        .call()
        .expect("resource.set_field dispatch resolves")
        .assert_finished();

    assert_eq!(
        app.world().resource::<TestScore>().points,
        42,
        "the edit still lands on the editor's own resource"
    );
    assert_eq!(
        app.world().resource::<CommandHistory>().undo_stack.len(),
        stack_before + 1,
        "the edit is one resource entry"
    );
    assert!(
        app.world()
            .resource::<jackdaw::live_edits::LiveEditLog>()
            .entries
            .is_empty(),
        "no live edit was recorded or streamed: a resource edit is editor-session state"
    );
}
