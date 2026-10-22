//! The dock layout's maximize mode: what a toggle hides and restores,
//! how the state survives the tree changing underneath it, what it
//! leaves in a saved layout, and the chord that drives it. Each module
//! below was its own test binary; merged, the editor links once.

#[path = "../util/mod.rs"]
mod util;

mod keybind;
mod maximize_toggle;
mod persistence_roundtrip;
mod reconcile;

use bevy::prelude::*;
use jackdaw::AppState;
use jackdaw::prelude::*;
use jackdaw_panels::area::DockArea;
use jackdaw_panels::reconcile::NodeBinding;
use jackdaw_panels::tree::DockTree;

use util::OperatorResultExt;

/// The window whose leaf the tests maximize: the right sidebar, which
/// sits deepest in the default tree so two splits have to hide a
/// sibling for it to fill the layout.
pub(crate) const INSPECTOR: &str = "jackdaw.inspector.components";

/// The editor in the editor state with its default tree materialized.
pub(crate) fn editor_app() -> App {
    let mut app = util::editor_test_app();
    app.world_mut()
        .resource_mut::<NextState<AppState>>()
        .set(AppState::Editor);
    for _ in 0..4 {
        app.update();
    }
    app
}

/// Dispatch `panel.toggle_maximize` for `window_id`. Headless tests
/// have no cursor, so the focus chain answers through its last-pressed
/// fallback: name the window there first, which is also what the
/// availability gate reads.
pub(crate) fn toggle(app: &mut App, window_id: &str) {
    app.world_mut()
        .insert_resource(jackdaw::panel_focus::LastPressedPanel(Some(
            window_id.to_string(),
        )));
    app.world_mut()
        .operator("panel.toggle_maximize")
        .param("window_id", window_id.to_string())
        .call()
        .expect("panel.toggle_maximize dispatch resolves")
        .assert_finished();
    settle(app);
}

/// Run frames until the reconciler and the split-size recalculation
/// have caught up with the latest tree / maximize change.
pub(crate) fn settle(app: &mut App) {
    for _ in 0..4 {
        app.update();
    }
}

/// Every split's id and fraction, in a stable order. The untouched
/// fractions are the restore guarantee, so tests compare these exactly.
pub(crate) fn fractions(world: &World) -> Vec<(u64, f32)> {
    let tree = world.resource::<DockTree>();
    let mut out: Vec<(u64, f32)> = tree
        .nodes
        .iter()
        .filter_map(|(id, n)| n.as_split().map(|s| (id.0, s.fraction)))
        .collect();
    out.sort_by_key(|(id, _)| *id);
    out
}

/// Every materialized leaf host's area id and whether the leaf is
/// effectively visible: its own display plus every ancestor's. Maximize
/// hides the *host* carrying a sibling subtree, so a leaf deep inside a
/// hidden subtree keeps its own `Display::Flex` while being unreachable
/// in the layout — this walks up to report what the user actually sees.
pub(crate) fn leaf_displays(world: &mut World) -> Vec<(String, bool)> {
    let mut leaves = world.query::<(Entity, &NodeBinding, &DockArea)>();
    let entries: Vec<(Entity, String)> = leaves
        .iter(world)
        .map(|(entity, binding, area)| (entity, format!("{}#{}", area.id, binding.0.0)))
        .collect();

    let mut out = Vec::with_capacity(entries.len());
    for (entity, key) in entries {
        let mut visible = true;
        let mut current = entity;
        loop {
            let entity_ref = world.entity(current);
            if let Some(node) = entity_ref.get::<Node>()
                && node.display == Display::None
            {
                visible = false;
                break;
            }
            match entity_ref.get::<ChildOf>() {
                Some(child_of) => current = child_of.parent(),
                None => break,
            }
        }
        out.push((key, visible));
    }
    out.sort_by_key(|(key, _)| key.clone());
    out
}
