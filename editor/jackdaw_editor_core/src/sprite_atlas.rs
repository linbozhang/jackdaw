//! Authoring the grid cut of a Sprite Atlas. The layout asset a sprite sheet
//! names is a list of rectangles; the grid operator recomputes that list from
//! a tile size and a column and row count, so an evenly cut sheet splits
//! without hand-editing each rectangle. Free-form rectangles stay available
//! through the card's own rows.

use bevy::ecs::reflect::AppTypeRegistry;
use bevy::ecs::system::In;
use bevy::math::UVec2;
use bevy::prelude::*;
use jackdaw_api::prelude::*;

use crate::definition_assets::commit_whole_definition;

pub(crate) fn add_to_extension(ctx: &mut jackdaw_api::prelude::ExtensionContext) {
    ctx.register_operator::<SpriteAtlasGridOp>();
}

/// Cut the open Sprite Atlas into a grid: every tile `tile_size` wide and
/// tall, `columns` across and `rows` down, with a padding between cells and
/// an offset for the whole grid, in pixels. The frames index left to right,
/// top to bottom, which is the order a sprite's `texture_atlas` index reads.
#[operator(
    id = "sprite.atlas.grid",
    label = "Cut Atlas Grid",
    description = "Cut the open Sprite Atlas into a grid of tiles.",
    allows_undo = false,
    params(
        tile_size(String, doc = "Tile size in pixels, as '64' or '64,64'."),
        columns(i64, doc = "Grid columns. At least one."),
        rows(i64, doc = "Grid rows. At least one."),
        padding(
            String,
            doc = "Pixels between cells, as '8' or '8,8'. None when left out."
        ),
        offset(
            String,
            doc = "Pixels the whole grid starts at, as '8' or '8,8'. None when left out."
        ),
    )
)]
pub(crate) fn sprite_atlas_grid(
    params: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    let tile_size = params.as_str("tile_size").and_then(parse_uvec2);
    let columns = params
        .as_int("columns")
        .filter(|n| *n > 0)
        .map(|n| n as u32);
    let rows = params.as_int("rows").filter(|n| *n > 0).map(|n| n as u32);
    let padding = params.as_str("padding").and_then(parse_uvec2);
    let offset = params.as_str("offset").and_then(parse_uvec2);
    let (Some(tile_size), Some(columns), Some(rows)) = (tile_size, columns, rows) else {
        commands.queue(|world: &mut World| {
            jackdaw_api_internal::operator::warn_caller(
                world,
                "sprite.atlas.grid: tile_size, columns and rows are required, as in \
                 tile_size=64 columns=8 rows=4; columns and rows count from one",
            );
        });
        return OperatorResult::Cancelled;
    };
    commands.queue(move |world: &mut World| {
        let registry = world.resource::<AppTypeRegistry>().clone();
        let json = {
            let registry = registry.read();
            let layout = bevy::image::TextureAtlasLayout::from_grid(
                tile_size, columns, rows, padding, offset,
            );
            crate::inspector::reflect_fields::reflect_to_json(&layout, &registry)
        };
        let type_path =
            <bevy::image::TextureAtlasLayout as bevy::reflect::TypePath>::type_path().to_string();
        let outcome = commit_whole_definition(world, &type_path, |_| json);
        match outcome {
            Ok(()) => {
                let frames = columns as usize * rows as usize;
                jackdaw_api_internal::operator::report_to_caller(
                    world,
                    format!("Cut the atlas into {columns} by {rows}, {frames} frames"),
                );
            }
            Err(refusal) => {
                jackdaw_api_internal::operator::warn_caller(
                    world,
                    format!("sprite.atlas.grid: {refusal}"),
                );
            }
        }
    });
    OperatorResult::Finished
}

/// Read a size a caller spelled as '64' or '64,64'. `None` when it is empty
/// or no two non-negative numbers.
fn parse_uvec2(spelled: &str) -> Option<UVec2> {
    let spelled = spelled.trim();
    let (wide, high) = match spelled.split_once(',') {
        Some((wide, high)) => (wide.trim(), Some(high.trim())),
        None => (spelled, None),
    };
    let wide: u32 = wide.parse().ok()?;
    let high: u32 = match high {
        Some(high) => high.parse().ok()?,
        None => wide,
    };
    Some(UVec2::new(wide, high))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_size_spells_as_one_number_or_a_pair() {
        assert_eq!(parse_uvec2("64"), Some(UVec2::new(64, 64)));
        assert_eq!(parse_uvec2("64, 32"), Some(UVec2::new(64, 32)));
        assert_eq!(parse_uvec2(" 8 ,8 "), Some(UVec2::new(8, 8)));
        assert_eq!(parse_uvec2(""), None);
        assert_eq!(parse_uvec2("64,"), None);
        assert_eq!(parse_uvec2("six"), None);
        assert_eq!(parse_uvec2("-4"), None);
    }

    #[test]
    fn a_grid_lays_frames_left_to_right_and_top_to_bottom() {
        let layout =
            bevy::image::TextureAtlasLayout::from_grid(UVec2::new(32, 32), 2, 2, None, None);
        assert_eq!(layout.textures.len(), 4);
        assert_eq!(layout.textures[0].min, UVec2::ZERO);
        assert_eq!(
            layout.textures[1].min,
            UVec2::new(32, 0),
            "second frame is right of the first"
        );
        assert_eq!(
            layout.textures[2].min,
            UVec2::new(0, 32),
            "third frame is below the first"
        );
        assert_eq!(layout.size, UVec2::new(64, 64));
    }

    #[test]
    fn undo_json_puts_the_layout_it_came_from_back() {
        // The card's write path serializes the new value and undoes by
        // applying the old JSON back over it. The pair has to round-trip.
        let mut registry = bevy::reflect::TypeRegistry::default();
        registry.register::<bevy::image::TextureAtlasLayout>();
        let default = bevy::image::TextureAtlasLayout::default();
        let old_json = crate::inspector::reflect_fields::reflect_to_json(&default, &registry)
            .expect("the default serializes");
        let cut = bevy::image::TextureAtlasLayout::from_grid(UVec2::new(32, 16), 2, 3, None, None);
        // The card's whole-value write replaces by deserializing each side
        // and swapping the asset, so both spellings have to deserialize or
        // undo would be a no-op.
        let new_json = crate::inspector::reflect_fields::reflect_to_json(&cut, &registry)
            .expect("the cut serializes");
        for (name, json) in [("old", &old_json), ("new", &new_json)] {
            use serde::de::DeserializeSeed as _;
            let registration = registry
                .get(std::any::TypeId::of::<bevy::image::TextureAtlasLayout>())
                .expect("the layout is registered");
            let deserializer =
                bevy::reflect::serde::TypedReflectDeserializer::new(registration, &registry);
            assert!(
                deserializer.deserialize(json).is_ok(),
                "{name} JSON deserializes: {json}"
            );
        }
    }
}
