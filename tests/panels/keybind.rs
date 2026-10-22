//! The maximize chord: Shift+Space belongs to the toggle alone in the
//! preset, and a focused tree row no longer eats the Shift-held press
//! as a bare-Space activation.

use bevy::ecs::system::RunSystemOnce;
use bevy::prelude::*;
use jackdaw_api_internal::keymap::{DefaultKeymap, PresetInput, find_conflicts};
use jackdaw_feathers::tree_view::tree_keyboard_navigation;
use jackdaw_widgets::tree_view::{
    TreeFocused, TreeNode, TreeNodeExpanded, TreeRoot, TreeRowClicked, TreeRowContent,
};

use crate::util;

/// The recorded default chord is the operator's alone, and nothing in
/// the preset collides on Space (the command palette's Ctrl+Space
/// differs in modifiers, not key).
#[test]
fn shift_space_is_toggle_maximize_alone() {
    let mut app = util::editor_test_app();
    let defaults = app
        .world_mut()
        .get_resource_or_init::<DefaultKeymap>()
        .to_classic_preset();

    let chord = PresetInput::key("Space").shift();
    let owners: Vec<&str> = defaults
        .bindings
        .iter()
        .filter(|b| b.input == chord)
        .map(|b| b.operator.as_str())
        .collect();
    assert_eq!(
        owners,
        vec!["panel.toggle_maximize"],
        "the chord belongs to the maximize toggle and nothing else"
    );

    let conflicts = find_conflicts(&defaults);
    assert!(
        !conflicts.iter().any(|line| line.contains("Space")),
        "no preset conflict touches Space: {conflicts:?}"
    );
}

/// Clicks the navigation system fired, counted by an observer so the
/// test reads what a consumer of `TreeRowClicked` would see.
#[derive(Resource, Default)]
struct RowClicks(usize);

fn count_row_clicks(_: On<TreeRowClicked>, mut clicks: ResMut<RowClicks>) {
    clicks.0 += 1;
}

/// A focused tree row activates on Enter or bare Space, but a held
/// Shift hands Space to the keymap (the maximize chord), so the row
/// stays put: no `TreeRowClicked` fires.
#[test]
fn shift_space_does_not_activate_a_focused_tree_row() {
    for (shift_held, expected_clicks) in [(false, 1), (true, 0)] {
        let mut world = World::new();
        world.init_resource::<ButtonInput<KeyCode>>();
        world.insert_resource(bevy::input_focus::InputFocus::default());
        world.insert_resource(RowClicks(0));
        world.add_observer(count_row_clicks);

        // `TreeNode` is a relationship: its target needs to exist for
        // the on-insert hook that links the source back.
        let source = world.spawn_empty().id();
        let row = world
            .spawn((TreeNode(source), TreeNodeExpanded(true)))
            .with_children(|parent| {
                parent.spawn(TreeRowContent);
            })
            .id();
        world.spawn(TreeRoot).add_child(row);

        let mut keyboard = world.resource_mut::<ButtonInput<KeyCode>>();
        if shift_held {
            keyboard.press(KeyCode::ShiftLeft);
        }
        keyboard.press(KeyCode::Space);

        world.insert_resource(TreeFocused(Some(row)));
        world
            .run_system_once(tree_keyboard_navigation)
            .expect("the navigation system runs on a minimal world");

        assert_eq!(
            world.resource::<RowClicks>().0,
            expected_clicks,
            "clicks with Shift held: {shift_held}"
        );
    }
}
