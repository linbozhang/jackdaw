//! The `Anchor` component's 3×3 pivot preset grid (T21-SP9, decision 3-B).
//!
//! A bare offset `Vec2` tells an author little — the mainstream instinct is a
//! 3×3 arrangement of named pivots. The grid writes the same field the raw
//! offset row edits (`Anchor.0`, the nine `bevy_sprite::Anchor` constants),
//! so the two stay one truth and free-form offsets keep their row.

use bevy::prelude::*;
use bevy::sprite::Anchor;
use bevy::ui::Checked;
use bevy::ui_widgets::{RadioGroup, ValueChange};
use jackdaw_feathers::{segmented, tokens, tooltip::Tooltip};

use super::reflect_fields;

/// The nine presets, row-major from the top left, with the offset each writes.
/// The values are `bevy_sprite::Anchor`'s constants (y up); a test pins the
/// table to them.
const ANCHOR_PRESETS: [(&str, f32, f32); 9] = [
    ("Top Left", -0.5, 0.5),
    ("Top Center", 0.0, 0.5),
    ("Top Right", 0.5, 0.5),
    ("Center Left", -0.5, 0.0),
    ("Center", 0.0, 0.0),
    ("Center Right", 0.5, 0.0),
    ("Bottom Left", -0.5, -0.5),
    ("Bottom Center", 0.0, -0.5),
    ("Bottom Right", 0.5, -0.5),
];

/// One clickable cell of the preset grid: what entity's `Anchor` it edits,
/// which field path carries the offset, and the offset it writes.
#[derive(Component)]
pub(crate) struct AnchorPresetCell {
    source: Entity,
    field_path: String,
    type_path: String,
    value: Vec2,
}

/// Spawn the preset grid as the first rows of an `Anchor` card: a "Pivot"
/// label over a 3×3 arrangement of segments, the active one lit. `base_path`
/// is the offset field's parent path (empty on the component root), so a
/// nested `Anchor` field gets the grid too.
pub(crate) fn spawn_preset_grid(
    commands: &mut Commands,
    parent: Entity,
    source_entity: Entity,
    current: Vec2,
    base_path: &str,
    type_path: &str,
) {
    let field_path = if base_path.is_empty() {
        ".0".to_string()
    } else {
        format!("{base_path}.0")
    };

    let col = commands
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                row_gap: px(tokens::SPACING_XS),
                width: Val::Percent(100.0),
                ..Default::default()
            },
            ChildOf(parent),
        ))
        .id();
    commands.spawn((
        Text::new("Pivot"),
        TextFont {
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(tokens::TEXT_TERTIARY),
        ChildOf(col),
    ));

    // The 3×3 arrangement: the radio group on the container, three rows of
    // three segments under it. Clicking a segment rides the group's
    // `ValueChange<Entity>` to [`on_anchor_preset_change`].
    let group = commands
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                row_gap: px(2.0),
                align_self: AlignSelf::Start,
                ..Default::default()
            },
            RadioGroup,
            ChildOf(col),
        ))
        .observe(on_anchor_preset_change)
        .id();

    for row in ANCHOR_PRESETS.as_chunks::<3>().0 {
        let row_entity = commands
            .spawn((
                Node {
                    flex_direction: FlexDirection::Row,
                    column_gap: px(2.0),
                    ..Default::default()
                },
                ChildOf(group),
            ))
            .id();
        for (name, x, y) in row {
            let value = Vec2::new(*x, *y);
            let mut segment = commands.spawn((
                AnchorPresetCell {
                    source: source_entity,
                    field_path: field_path.clone(),
                    type_path: type_path.to_string(),
                    value,
                },
                Tooltip::title(format!("{name} ({x}, {y})")),
                segmented::segment_node(),
                segmented::segment_chrome(),
                ChildOf(row_entity),
                children![segmented::segment_label("•")],
            ));
            let active = anchor_matches(current, value);
            segment.insert(BackgroundColor(segmented::segment_background(active)));
            if active {
                segment.insert(Checked);
            }
        }
    }
}

/// Whether `current` names the same pivot `preset` does, within rounding
/// noise from the f32 offsets a save round-trip carries.
fn anchor_matches(current: Vec2, preset: Vec2) -> bool {
    (current - preset).abs().cmple(Vec2::splat(1e-5)).all()
}

/// Write path for a preset pick: the same undo-backed field commit the raw
/// offset row's axis inputs mint, one entry per pick. The cell carries the
/// whole `Vec2`, so the two axes move together.
pub(crate) fn on_anchor_preset_change(
    change: On<ValueChange<Entity>>,
    cells: Query<&AnchorPresetCell>,
    remote_proxies: Query<(), With<crate::remote::entity_browser::RemoteEntityProxy>>,
    mut commands: Commands,
) {
    let Ok(cell) = cells.get(change.value) else {
        return;
    };
    if remote_proxies.contains(cell.source) {
        return;
    }
    let source = cell.source;
    let field_path = cell.field_path.clone();
    let type_path = cell.type_path.clone();
    let value = cell.value;
    commands.queue(move |world: &mut World| {
        // A `Vec2` reflects through glam's serde as a two-number sequence
        // (`[x, y]`), which is the JSON the field commit's deserializer
        // reads; a test pins the shape.
        reflect_fields::apply_field_json_with_undo(
            world,
            source,
            &type_path,
            &field_path,
            serde_json::json!([value.x, value.y]),
        );
    });
}

/// Keep the grid showing what the component holds: the cell matching the
/// live `Anchor.0` lights, the rest clear. Undo and axis-input edits land
/// through this, the same pass `node_card::paint_node_segments` rides.
pub(crate) fn paint_anchor_presets(
    anchors: Query<&Anchor>,
    mut cells: Query<(
        Entity,
        &AnchorPresetCell,
        &mut BackgroundColor,
        Has<Checked>,
    )>,
    mut commands: Commands,
) {
    for (entity, cell, mut background, checked) in &mut cells {
        let active = anchors
            .get(cell.source)
            .map(|anchor| anchor_matches(anchor.as_vec(), cell.value))
            .unwrap_or(false);
        let color = segmented::segment_background(active);
        if background.0 != color {
            background.0 = color;
        }
        if checked != active {
            segmented::set_segment_checked(&mut commands, entity, active);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_preset_table_is_the_nine_anchor_constants() {
        let expected = [
            Anchor::TOP_LEFT,
            Anchor::TOP_CENTER,
            Anchor::TOP_RIGHT,
            Anchor::CENTER_LEFT,
            Anchor::CENTER,
            Anchor::CENTER_RIGHT,
            Anchor::BOTTOM_LEFT,
            Anchor::BOTTOM_CENTER,
            Anchor::BOTTOM_RIGHT,
        ];
        for ((name, x, y), anchor) in ANCHOR_PRESETS.iter().zip(expected) {
            assert_eq!(
                Vec2::new(*x, *y),
                anchor.as_vec(),
                "{name} must write the constant it names"
            );
        }
        assert_eq!(ANCHOR_PRESETS.len(), 9, "three by three");
    }

    #[test]
    fn a_preset_json_lands_where_the_offset_row_reads() {
        // The write contract the grid shares with the raw offset row: the
        // preset JSON at the `.0` field path lands in `Anchor.0` when applied
        // through the same applier the field commit uses
        // (`commands::json_field_edit_to_bsn_value` reaches the live field and
        // calls `apply_json_to_reflect`). This fork's `Vec2` reflects through
        // glam's serde, a two-number sequence rather than an `{x, y}` map.
        // The registry mirrors the app's, where the inventory auto-register
        // has every `impl_reflect!` type, `Vec2` included.
        let (_, x, y) = ANCHOR_PRESETS[8]; // Bottom Right
        let preset = serde_json::json!([x, y]);

        let mut registry = bevy::reflect::TypeRegistry::default();
        registry.register::<Vec2>();
        registry.register::<Anchor>();

        let mut anchor = Anchor::CENTER;
        let field = anchor.reflect_path_mut(".0").expect("the offset is at .0");
        crate::commands::apply_json_to_reflect(field, &preset, &registry);
        assert_eq!(anchor.as_vec(), Vec2::new(x, y), "the preset landed");

        // And the wrong shape does not silently pass as the same value.
        let mut anchor = Anchor::CENTER;
        let field = anchor.reflect_path_mut(".0").expect("the offset is at .0");
        crate::commands::apply_json_to_reflect(
            field,
            &serde_json::json!({ "x": x, "y": y }),
            &registry,
        );
        assert_ne!(
            anchor.as_vec(),
            Vec2::new(x, y),
            "the map shape is not the contract; keep the sequence"
        );
    }

    #[test]
    fn a_free_form_offset_off_by_noise_still_lights_its_cell() {
        // A save round-trip can carry f32 widening noise; the active-cell
        // match must absorb it, and must not confuse neighbouring cells.
        assert!(anchor_matches(Vec2::new(0.5, 0.5), Vec2::new(0.5, 0.5)));
        assert!(anchor_matches(
            Vec2::new(0.5 + f32::EPSILON, -0.5),
            Vec2::new(0.5, -0.5),
        ));
        assert!(!anchor_matches(Vec2::new(0.4, 0.5), Vec2::new(0.5, 0.5)));
    }
}
