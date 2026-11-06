//! Operators for the panel docking system.

use bevy::picking::pointer::PointerButton;
use bevy::prelude::*;
use jackdaw_api::prelude::*;
use jackdaw_api_internal::keymap::PresetInput;
use jackdaw_panels::PanelGroup;
use jackdaw_panels::area::{DockTab, DockTabCloseButton};
use jackdaw_panels::maximize::MaximizedLeaf;
use jackdaw_panels::reconcile::NodeBinding;
use jackdaw_panels::tabs::DockTabMaximizeButton;
use jackdaw_panels::tree::{DockNode, DockTree, NodeId, SplitAxis, TabId};

use crate::core_extension::CoreExtensionInputContext;
use crate::panel_focus::PanelFocus;

pub struct DockOpsPlugin;

impl Plugin for DockOpsPlugin {
    fn build(&self, app: &mut App) {
        app.add_observer(on_close_button_click)
            .add_observer(on_tab_middle_click)
            .add_observer(on_maximize_button_click);
    }
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<DockCloseTabOp>();
    ctx.register_operator::<WindowResizePanelOp>();
    ctx.register_operator::<PanelToggleMaximizeOp>();
    // Shift+Space: bare Space activates a focused tree row and
    // Ctrl+Space opens the command palette, so the maximize chord takes
    // the one modifier neither claims.
    ctx.bind_operator::<CoreExtensionInputContext, PanelToggleMaximizeOp>([PresetInput::key(
        "Space",
    )
    .shift()]);
}

#[operator(
    id = "dock.close_tab",
    label = "Close Tab",
    description = "Close the specified docked tab.",
    allows_undo = false,
    params(tab_id(i64, doc = "TabId of the tab to close."))
)]
pub(crate) fn dock_close_tab(
    In(params): In<OperatorParameters>,
    mut tree: ResMut<DockTree>,
) -> OperatorResult {
    let Some(tab_id) = params.as_int("tab_id") else {
        warn!("dock.close_tab: missing 'tab_id' parameter");
        return OperatorResult::Cancelled;
    };
    tree.remove_tab(TabId(tab_id as u64));
    OperatorResult::Finished
}

/// The smallest share of a split either side keeps, matching the clamp
/// `DockTree::set_fraction` applies.
const MIN_SHARE: f32 = 0.05;

/// Whether the focused panel can be maximized (or already maximized, so
/// it can be restored): a focusable window in a leaf with a sibling to
/// hide. A single-leaf root layout has nothing to maximize over.
fn can_toggle_maximize(
    focus: PanelFocus,
    tree: Res<DockTree>,
    maximized: Res<MaximizedLeaf>,
) -> bool {
    if maximized.0.is_some() {
        return true;
    }
    let Some(window_id) = focus.focused_panel() else {
        return false;
    };
    tree.find_leaf_with_window(&window_id)
        .is_some_and(|leaf| tree.parent_of(leaf).is_some())
}

#[operator(
    id = "panel.toggle_maximize",
    label = "Toggle Panel Maximize",
    description = "Expand the panel under the cursor to fill the layout, or restore it.",
    allows_undo = false,
    is_available = can_toggle_maximize,
    params(window_id(
        String,
        default = "",
        doc = "Window the panel holds, such as \"jackdaw.inspector.components\". \
               Empty means the panel under the cursor."
    ))
)]
pub(crate) fn panel_toggle_maximize(
    In(params): In<OperatorParameters>,
    focus: PanelFocus,
    mut tree: ResMut<DockTree>,
    mut maximized: ResMut<MaximizedLeaf>,
) -> OperatorResult {
    // Toggle's other half: already maximized means restore, whatever
    // the parameters say.
    if maximized.0.is_some() {
        maximized.0 = None;
        return OperatorResult::Finished;
    }

    let Some(window_id) = params
        .as_str("window_id")
        .filter(|id| !id.is_empty())
        .map(ToString::to_string)
        .or_else(|| focus.focused_panel())
    else {
        warn!("panel.toggle_maximize: no panel under the cursor and no 'window_id' given");
        return OperatorResult::Cancelled;
    };
    let Some(leaf) = tree.find_leaf_with_window(&window_id) else {
        warn!("panel.toggle_maximize: no dock panel holds '{window_id}'");
        return OperatorResult::Cancelled;
    };
    if tree.parent_of(leaf).is_none() {
        warn!("panel.toggle_maximize: '{window_id}' fills the layout; nothing to maximize over");
        return OperatorResult::Cancelled;
    }
    // Bring the window's tab to the front before expanding, so the
    // maximized view is the panel the user was looking at.
    let tab = tree
        .get(leaf)
        .and_then(|n| n.as_leaf())
        .and_then(|l| l.windows.iter().find(|t| t.window_id == window_id))
        .map(|t| t.id);
    if let Some(tab) = tab {
        tree.set_active(leaf, tab);
    }
    // The reconciler does the rest: it hides the sibling subtree at
    // every split along the path, and the tree (fractions included)
    // stays exactly as it was for saving.
    maximized.0 = Some(leaf);
    OperatorResult::Finished
}

#[operator(
    id = "window.resize_panel",
    label = "Resize Panel",
    description = "Size the dock panel a window sits in, in logical pixels.",
    allows_undo = false,
    params(
        window_id(
            String,
            doc = "Window the panel holds, such as \"jackdaw.inspector.components\", \
                   or the dock area it sits in, such as \"right_sidebar\"."
        ),
        width(
            f64,
            doc = "Width in logical pixels, for a panel beside its neighbour."
        ),
        height(
            f64,
            doc = "Height in logical pixels, for a panel above or below its neighbour."
        ),
    )
)]
pub(crate) fn window_resize_panel(
    In(params): In<OperatorParameters>,
    mut tree: ResMut<DockTree>,
    groups: Query<(&NodeBinding, &ComputedNode), With<PanelGroup>>,
    windows: Query<&Window, With<bevy::window::PrimaryWindow>>,
    mut commands: Commands,
) -> OperatorResult {
    let Some(window_id) = params.as_str("window_id") else {
        refuse(&mut commands, "missing 'window_id' parameter".to_string());
        return OperatorResult::Cancelled;
    };
    let Some(leaf) = tree
        .find_leaf_with_window(window_id)
        .or_else(|| tree.find_by_area_id(window_id))
    else {
        refuse(
            &mut commands,
            format!(
                "no dock panel holds '{window_id}'; this layout has {:?}",
                panels_on_offer(&tree)
            ),
        );
        return OperatorResult::Cancelled;
    };
    let Some(split_id) = tree.parent_of(leaf) else {
        refuse(
            &mut commands,
            format!("'{window_id}' fills the layout and has nothing to share with"),
        );
        return OperatorResult::Cancelled;
    };
    let Some(split) = tree.get(split_id).and_then(DockNode::as_split) else {
        return OperatorResult::Cancelled;
    };
    let axis = split.axis;
    let leads = split.a == leaf;

    let wanted = match axis {
        SplitAxis::Horizontal => params.as_float("width"),
        SplitAxis::Vertical => params.as_float("height"),
    };
    let Some(wanted) = wanted.filter(|size| *size > 0.0) else {
        let asked = match axis {
            SplitAxis::Horizontal => "width",
            SplitAxis::Vertical => "height",
        };
        refuse(
            &mut commands,
            format!("'{window_id}' is sized by its {asked}"),
        );
        return OperatorResult::Cancelled;
    };

    let total = split_extent(split_id, axis, &groups, &windows);
    if total <= 0.0 {
        refuse(
            &mut commands,
            "the layout has no size to divide yet".to_string(),
        );
        return OperatorResult::Cancelled;
    }
    let share = (wanted as f32 / total).clamp(MIN_SHARE, 1.0 - MIN_SHARE);
    tree.set_fraction(split_id, if leads { share } else { 1.0 - share });
    OperatorResult::Finished
}

/// Tell the caller why the panel was not sized, which a caller with no log to
/// read has no other way of learning.
fn refuse(commands: &mut Commands, reason: String) {
    commands.queue(move |world: &mut World| {
        warn_caller(world, format!("window.resize_panel: {reason}"));
    });
}

/// Every panel a caller could have named: each dock area and the windows in it.
fn panels_on_offer(tree: &DockTree) -> Vec<String> {
    tree.leaves()
        .map(|(_, leaf)| {
            let windows: Vec<&str> = leaf.tabs().map(|(window_id, _)| window_id).collect();
            format!("{} {windows:?}", leaf.area_id)
        })
        .collect()
}

/// How many logical pixels a split has to divide: what the laid-out container
/// measures, and the window it lives in before the first layout pass.
fn split_extent(
    split: NodeId,
    axis: SplitAxis,
    groups: &Query<(&NodeBinding, &ComputedNode), With<PanelGroup>>,
    windows: &Query<&Window, With<bevy::window::PrimaryWindow>>,
) -> f32 {
    let along = |size: Vec2| match axis {
        SplitAxis::Horizontal => size.x,
        SplitAxis::Vertical => size.y,
    };
    groups
        .iter()
        .find(|(binding, _)| binding.0 == split)
        .map(|(_, computed)| along(computed.size() * computed.inverse_scale_factor()))
        .filter(|extent| *extent > 0.0)
        .or_else(|| {
            windows
                .single()
                .ok()
                .map(|window| along(Vec2::new(window.width(), window.height())))
        })
        .unwrap_or_default()
}

fn on_close_button_click(
    trigger: On<PointerClick>,
    close_buttons: Query<&DockTabCloseButton>,
    mut commands: Commands,
) {
    let Ok(close_btn) = close_buttons.get(trigger.event_target()) else {
        return;
    };
    commands
        .operator(DockCloseTabOp::ID)
        .param("tab_id", close_btn.tab_id.0 as i64)
        .call();
}

/// The tab-bar maximize button: maximize (or restore) the leaf whose
/// bar was clicked, naming its active window so the operator works
/// headless without the cursor's focus chain. An empty name falls
/// back to the operator's own focus resolution.
fn on_maximize_button_click(
    trigger: On<PointerClick>,
    buttons: Query<&DockTabMaximizeButton>,
    bindings: Query<&NodeBinding>,
    tree: Res<DockTree>,
    mut commands: Commands,
) {
    let Ok(button) = buttons.get(trigger.event_target()) else {
        return;
    };
    let Ok(NodeBinding(leaf)) = bindings.get(button.area_entity) else {
        return;
    };
    let active_window = tree.get(*leaf).and_then(|n| n.as_leaf()).and_then(|l| {
        l.windows
            .iter()
            .find(|tab| Some(tab.id) == l.active)
            .map(|tab| tab.window_id.clone())
    });
    commands
        .operator(PanelToggleMaximizeOp::ID)
        .param("window_id", active_window.unwrap_or_default())
        .call();
}

fn on_tab_middle_click(trigger: On<PointerClick>, tabs: Query<&DockTab>, mut commands: Commands) {
    if trigger.event().button != PointerButton::Middle {
        return;
    }
    let Ok(tab) = tabs.get(trigger.event_target()) else {
        return;
    };
    commands
        .operator(DockCloseTabOp::ID)
        .param("tab_id", tab.tab_id.0 as i64)
        .call();
}
