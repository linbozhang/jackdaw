//! `ActiveTool` resource: which top-level tool the user has active.
//!
//! Drives gizmo rendering and the toolbar active-state highlight.
//! `Select` hides any manipulator; the other variants render their
//! respective gizmo when something is selected.

use bevy::prelude::*;

/// `Reflect` (and the `register_type` in `commands::plugin`) so remote
/// tooling can read the active tool over BRP (`world.get_resource`), which
/// needs the type registered with `ReflectResource` data. Not serialized
/// into scenes: it is an editor-session resource.
#[derive(Resource, Default, PartialEq, Eq, Clone, Copy, Debug, Reflect)]
#[reflect(Resource)]
pub enum ActiveTool {
    #[default]
    Select,
    Translate,
    Rotate,
    Scale,
    /// Tile-grid authoring (T22): pointer strokes paint, erase and fill
    /// cells of the active tilemap layer; the palette panel rides along.
    /// The manipulator gizmos stand down, the way they do for `Select`.
    Tilemap,
}

impl ActiveTool {
    /// Whether the tool drives the transform gizmos. `Select` manipulates
    /// nothing and `Tilemap` paints cells; everything else shows its
    /// gizmo on a selection.
    #[must_use]
    pub fn is_manipulator(self) -> bool {
        !matches!(self, Self::Select | Self::Tilemap)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_is_select() {
        assert_eq!(ActiveTool::default(), ActiveTool::Select);
    }
}
