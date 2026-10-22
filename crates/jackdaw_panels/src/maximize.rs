//! View-layer panel maximize.
//!
//! Maximizing a panel is *not* a tree change: `DockTree` keeps every
//! leaf, split and fraction exactly as it was. Instead this resource
//! names the leaf that fills the layout, and the reconciler hides the
//! sibling subtree at each split along the root-to-leaf path (see
//! [`crate::reconcile`]). `recalculate_group` then gives the visible
//! subtree the whole group, and restoring is a matter of clearing the
//! resource: the next reconcile pass re-materializes the tree with
//! every sibling visible and each `fraction` untouched.
//!
//! Because a stored [`NodeId`] only means anything inside the tree it
//! was allocated from, **any path that replaces the whole `DockTree`
//! resource (workspace switch, layout init/reset) must call
//! [`exit_maximize`]**. `NodeId` counters overlap between trees, so a
//! stale id can collide with an unrelated node that no validation can
//! tell apart. The reconciler's [`validate`] self-heal is the backstop
//! for leaves that vanish from the *live* tree (last tab closed,
//! extension removed), not for tree swaps.

use bevy::prelude::*;

use crate::tree::{DockNode, DockTree, NodeId};

/// The leaf currently filling the layout, if any. Pure view state: the
/// tree below is untouched while this is set, so saving the layout at
/// any moment stores the un-maximized arrangement, and a reload starts
/// un-maximized.
#[derive(Resource, Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct MaximizedLeaf(pub Option<NodeId>);

/// Clear the maximize state, whatever it points at. The reconciler
/// re-materializes the tree next frame with every sibling visible
/// again. Tree-replacement paths (workspace switch, layout init/reset)
/// must call this; see the module docs.
pub fn exit_maximize(world: &mut World) {
    // Bare worlds (tree-only unit tests) never carry the resource;
    // nothing maximized means nothing to clear.
    if world
        .get_resource::<MaximizedLeaf>()
        .is_some_and(|m| m.0.is_some())
    {
        world.resource_mut::<MaximizedLeaf>().0 = None;
    }
}

/// Restore the layout when a window is about to open in a leaf the user
/// can't see because maximize hid it. A landing equal to the maximized
/// leaf is fine: adding a tab inside the maximized view should not kick
/// the user out of it.
pub fn exit_maximize_for_leaf(world: &mut World, landing: NodeId) {
    if world
        .get_resource::<MaximizedLeaf>()
        .is_some_and(|m| m.0.is_some_and(|leaf| leaf != landing))
    {
        world.resource_mut::<MaximizedLeaf>().0 = None;
    }
}

/// Whether `candidate` still names a maximizable leaf of `tree`: the
/// node exists, is a leaf, and is reachable from the root. The
/// reconciler reads the stored id through this on every materialization
/// and treats a failure as "not maximized".
pub fn validate(tree: &DockTree, candidate: Option<NodeId>) -> Option<NodeId> {
    candidate.filter(|id| {
        tree.root.is_some_and(|root| {
            matches!(tree.get(*id), Some(DockNode::Leaf(_))) && tree.subtree_contains(root, *id)
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::area::DockAreaStyle;
    use crate::tree::{DockLeaf, Edge};

    fn leaf(area_id: &str, windows: &[&str]) -> DockLeaf {
        DockLeaf::new(area_id, DockAreaStyle::TabBar)
            .with_windows(windows.iter().map(ToString::to_string).collect())
    }

    fn two_leaf_tree() -> (DockTree, NodeId, NodeId) {
        let mut t = DockTree::new();
        let a = t.set_root_leaf(leaf("a", &["a"]));
        let (b, _) = t.split(a, Edge::Right, "b".into()).unwrap();
        (t, a, b)
    }

    #[test]
    fn a_live_leaf_validates() {
        let (t, a, _) = two_leaf_tree();
        assert_eq!(validate(&t, Some(a)), Some(a));
    }

    #[test]
    fn none_stays_none() {
        let (t, _, _) = two_leaf_tree();
        assert_eq!(validate(&t, None), None);
    }

    #[test]
    fn a_missing_node_is_rejected() {
        let (t, _, _) = two_leaf_tree();
        assert_eq!(validate(&t, Some(NodeId(9999))), None);
    }

    #[test]
    fn a_split_node_is_rejected() {
        let (t, _, _) = two_leaf_tree();
        let root = t.root.unwrap();
        assert!(t.get(root).unwrap().as_split().is_some());
        assert_eq!(validate(&t, Some(root)), None);
    }

    #[test]
    fn a_detached_leaf_is_rejected() {
        // `simplify` drops the split when one side empties; a stale id
        // pointing at the removed leaf must not survive validation.
        let mut t = DockTree::new();
        let a = t.set_root_leaf(leaf("a", &["a"]));
        let (b, _) = t.split(a, Edge::Right, "b".into()).unwrap();
        let tab_b = t.get(b).unwrap().as_leaf().unwrap().windows[0].id;
        t.move_tab(tab_b, a);
        assert!(t.get(b).is_none(), "precondition: the leaf is gone");
        assert_eq!(validate(&t, Some(b)), None);
    }

    #[test]
    fn a_rootless_tree_rejects_everything() {
        let t = DockTree::new();
        assert_eq!(validate(&t, Some(NodeId(0))), None);
    }
}
