use bevy::prelude::*;
use jackdaw_api_internal::inspector::{InspectorRegistry, resolve_active_category};
use jackdaw_feathers::{tokens, tooltip::Tooltip};
use std::borrow::Cow;

/// The inspector category whose cards are currently shown. Defaults to "object".
#[derive(Resource)]
pub(crate) struct ActiveInspectorCategory(pub(crate) Cow<'static, str>);

impl Default for ActiveInspectorCategory {
    fn default() -> Self {
        Self(Cow::Borrowed("object"))
    }
}

/// Category ids (in strip order) that have at least one card present for the
/// current entity. Used to dim absent tabs and to drive sticky/fallback.
pub(crate) fn applicable_categories<'a>(
    registry: &'a InspectorRegistry,
    present_type_paths: impl Iterator<Item = &'a str>,
) -> Vec<&'a str> {
    let present: std::collections::HashSet<&str> = present_type_paths
        .map(|tp| registry.category_for(tp))
        .collect();
    registry
        .categories_sorted()
        .into_iter()
        .map(|c| c.id.as_ref())
        .filter(|id| present.contains(id))
        .collect()
}

/// Category ids (in strip order) that are SHOWN for the current selection.
///
/// "object" and "components" are always shown: every entity can receive a
/// component, so the Components tab must stay reachable even before the entity
/// has any generic component. "mesh" is shown only when a Brush card is
/// present. "modifiers", "material", and any category an extension
/// registered header chips for are shown when a Brush is present OR when the
/// category already has a card. Other ids are shown only when they have a
/// card.
///
/// This is the canonical visibility rule shared by both the strip paint system
/// and the sticky-category resolver so the two cannot drift apart.
pub(super) fn shown_categories<'a>(
    registry: &'a InspectorRegistry,
    applicable: &[&'a str],
    chip_categories: &[&str],
) -> Vec<&'a str> {
    let brush_present = applicable.contains(&"mesh");
    registry
        .categories_sorted()
        .into_iter()
        .map(|c| c.id.as_ref())
        .filter(|id| match *id {
            "object" | "components" => true,
            "mesh" => brush_present,
            "modifiers" | "material" => brush_present || applicable.contains(id),
            id if chip_categories.contains(&id) => brush_present || applicable.contains(&id),
            _ => applicable.contains(id),
        })
        .collect()
}

/// Marker placed on the panel host entity. An observer fires on `Add` and
/// spawns the real strip rail as a sibling-via-child.
#[derive(Component)]
pub(crate) struct InspectorCategoryStripMount;

/// Marker on the text node at the top of the inspector content column that
/// always names the category being viewed (e.g. "Object"). The strip tells
/// *which* category is active with a left accent, but a 30px icon carries no
/// words; this header makes the current page legible without hovering.
/// [`update_active_category_label`] writes the text.
#[derive(Component)]
pub(crate) struct ActiveCategoryLabel;

/// Write the active category's label into every [`ActiveCategoryLabel`] text
/// node. Deliberately NOT part of `rebuild_add_header`: that respawns the whole
/// add-UI per category change, while this only rewrites one string, and the
/// two share the same trigger (`ActiveInspectorCategory` changing).
pub(super) fn update_active_category_label(
    registry: Res<InspectorRegistry>,
    active: Res<ActiveInspectorCategory>,
    added_labels: Query<(), Added<ActiveCategoryLabel>>,
    mut labels: Query<&mut Text, With<ActiveCategoryLabel>>,
) {
    if !active.is_changed() && !registry.is_changed() && added_labels.is_empty() {
        return;
    }
    let Some(cat) = registry
        .categories_sorted()
        .into_iter()
        .find(|c| c.id == active.0.as_ref())
    else {
        return;
    };
    let label = cat.label.clone();
    for mut text in &mut labels {
        if text.0.as_str() != label.as_ref() {
            text.0 = label.to_string();
        }
    }
}

/// Marker on the strip rail container (the vertical icon column).
#[derive(Component)]
pub(super) struct InspectorCategoryStrip;

/// Marker on one tab button, carrying its category id.
#[derive(Component, Clone)]
pub(super) struct InspectorCategoryTab(pub(super) Cow<'static, str>);

/// The icon glyph child of an `InspectorCategoryTab`. Kept as a component
/// so the paint system can find it without querying all `Text` nodes.
#[derive(Component)]
pub(super) struct InspectorCategoryTabIcon;

/// Spawn the rail and one icon button per registered category under `parent`.
pub(super) fn spawn_category_strip(
    commands: &mut Commands,
    parent: Entity,
    registry: &InspectorRegistry,
    icon_font: &Handle<Font>,
) {
    // The rail is the mount entity itself. Inserting the layout here (rather
    // than spawning a child rail) keeps it a real flex item in the
    // [strip | content] row: a Node whose parent has no Node detaches from
    // layout, so the mount must carry the rail's Node directly.
    commands.entity(parent).insert((
        InspectorCategoryStrip,
        Node {
            width: Val::Px(tokens::SIDEBAR_WIDTH),
            height: Val::Percent(100.0),
            flex_direction: FlexDirection::Column,
            align_items: AlignItems::Center,
            padding: UiRect::vertical(Val::Px(tokens::SPACING_SM)),
            row_gap: Val::Px(tokens::SPACING_XS),
            flex_shrink: 0.0,
            ..default()
        },
        BackgroundColor(tokens::PANEL_HEADER_BG),
    ));
    let rail = parent;

    for cat in registry.categories_sorted() {
        let cat_id = cat.id.clone();
        let label = cat.label.clone();

        let cell = commands
            .spawn((
                InspectorCategoryTab(cat_id.clone()),
                Tooltip::title(label.as_ref()).with_description(cat.description.as_ref()),
                bevy::picking::hover::Hovered::default(),
                Node {
                    width: Val::Px(tokens::SIDEBAR_WIDTH),
                    height: Val::Px(tokens::SIDEBAR_WIDTH),
                    justify_content: JustifyContent::Center,
                    align_items: AlignItems::Center,
                    border: UiRect::left(Val::Px(3.0)),
                    ..default()
                },
                BackgroundColor(Color::NONE),
                BorderColor::all(Color::NONE),
                ChildOf(rail),
            ))
            .id();

        commands.spawn((
            InspectorCategoryTabIcon,
            Text::new(String::from(cat.icon.unicode())),
            TextFont {
                font: icon_font.clone().into(),
                font_size: tokens::ICON_MD,
                ..default()
            },
            TextColor(tokens::TEXT_SECONDARY),
            ChildOf(cell),
        ));

        let click_id = cat_id.clone();
        commands.entity(cell).observe(
            move |_: On<PointerClick>, mut active: ResMut<ActiveInspectorCategory>| {
                active.0 = click_id.clone();
            },
        );
    }
}

/// Each frame: for every tab cell, show or hide the cell and set
/// background / left-border / icon color for shown cells.
///
/// Tabs that are not relevant to the current selection are hidden
/// (`Display::None`). No greyed-out state exists.
///
/// Visibility rules (see [`shown_categories`], the canonical rule):
/// - `object` and `components`: always shown — every entity can receive a
///   component, so the Components tab must stay reachable even when empty.
/// - `mesh`: shown only when a Brush card is present.
/// - `modifiers`, `material` and categories with header chips: shown when a
///   Brush is present OR when the category already has a card.
/// - Extension categories: shown only when applicable.
///
/// Skips the repaint when neither the active category nor the displayed card
/// set has changed since the last run.
pub(super) fn paint_category_tabs(
    registry: Res<InspectorRegistry>,
    active: Res<ActiveInspectorCategory>,
    type_paths: Query<
        &super::ComponentDisplayTypePath,
        Without<super::definition_card::DefinitionCard>,
    >,
    added_paths: Query<(), Added<super::ComponentDisplayTypePath>>,
    removed_paths: RemovedComponents<super::ComponentDisplayTypePath>,
    tabs: Query<(Entity, &InspectorCategoryTab, &Children)>,
    mut node_query: Query<&mut Node>,
    mut bg_query: Query<&mut BackgroundColor>,
    mut border_query: Query<&mut BorderColor>,
    mut icon_query: Query<&mut TextColor, With<InspectorCategoryTabIcon>>,
    chips: Query<&jackdaw_api_internal::inspector::InspectorChip>,
) {
    // Skip repaint when neither the active category nor the displayed card
    // set has changed this frame.
    if !active.is_changed() && added_paths.is_empty() && removed_paths.is_empty() {
        return;
    }

    let present_paths: Vec<&str> = type_paths.iter().map(|p| p.0.as_str()).collect();
    let applicable = applicable_categories(&registry, present_paths.into_iter());
    let chip_categories: Vec<&str> = chips.iter().map(|chip| chip.category.as_ref()).collect();
    let shown_set = shown_categories(&registry, &applicable, &chip_categories);

    for (cell, tab, children) in &tabs {
        let id = tab.0.as_ref();
        let shown = shown_set.contains(&id);

        // Show or hide the cell.
        if let Ok(mut node) = node_query.get_mut(cell) {
            node.display = if shown { Display::Flex } else { Display::None };
        }

        if !shown {
            continue;
        }

        let is_active = id == active.0.as_ref();

        // Cell background and left-border accent.
        if let Ok(mut bg) = bg_query.get_mut(cell) {
            bg.0 = if is_active {
                tokens::PANEL_BG
            } else {
                Color::NONE
            };
        }
        if let Ok(mut border) = border_query.get_mut(cell) {
            *border = BorderColor::all(if is_active {
                tokens::ACCENT_BLUE
            } else {
                Color::NONE
            });
        }

        // Icon color.
        let icon_color = if is_active {
            tokens::TEXT_PRIMARY
        } else {
            tokens::TEXT_SECONDARY
        };

        for child in children.iter() {
            if let Ok(mut tc) = icon_query.get_mut(child) {
                tc.0 = icon_color;
            }
        }
    }
}

/// After the inspector rebuilds, resolve the active category against the
/// categories that HAVE cards (`applicable`), not merely the shown ones:
/// a selection switch auto-leaves a category whose tab would be empty, so
/// the panel lands on content instead of a bare filter row. The current
/// category stays sticky whenever it still has a card, and manually
/// clicking an empty tab (e.g. Components to add a component) still works —
/// clicks write the resource directly and do not trigger a rebuild. Writing
/// the resource unconditionally also re-triggers the category filter for
/// the new cards by marking it changed.
pub(super) fn resolve_active_on_rebuild(
    registry: Res<InspectorRegistry>,
    cards: Query<
        &super::ComponentDisplayTypePath,
        (
            With<super::ComponentDisplay>,
            Without<super::definition_card::DefinitionCard>,
        ),
    >,
    added: Query<(), Added<super::ComponentDisplay>>,
    mut removed: RemovedComponents<super::ComponentDisplay>,
    mut active: ResMut<ActiveInspectorCategory>,
) {
    let changed = !added.is_empty() || removed.read().next().is_some();
    if !changed {
        return;
    }
    let applicable = applicable_categories(&registry, cards.iter().map(|t| t.0.as_str()));
    let chip_categories: Vec<&str> = chips.iter().map(|chip| chip.category.as_ref()).collect();
    let shown = shown_categories(&registry, &applicable, &chip_categories);
    let resolved = resolve_active_category(active.0.as_ref(), &shown);
    if resolved != active.0.as_ref() {
        active.0 = std::borrow::Cow::Owned(resolved.to_string());
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use jackdaw_api_internal::inspector::{InspectorRegistry, seed_default_categories};

    #[test]
    fn applicable_categories_from_present_paths_in_order() {
        let mut r = InspectorRegistry::default();
        seed_default_categories(&mut r);
        // A brush entity: Brush + Transform + a custom component.
        let present = [
            "jackdaw_scene_types::types::Brush",
            "bevy_transform::components::transform::Transform",
            "my_game::Health",
        ];
        let got = applicable_categories(&r, present.iter().copied());
        // Strip order: object before mesh before components; only present ones returned.
        assert_eq!(got, ["object", "mesh", "components"]);
    }

    #[test]
    fn rebuild_resolution_leaves_card_less_category() {
        // The sticky resolver now feeds `applicable` (categories with cards),
        // not `shown` (which always contains object/components): a Transform-
        // only entity auto-leaves a stale "components" active category.
        let mut r = InspectorRegistry::default();
        seed_default_categories(&mut r);
        let applicable = applicable_categories(
            &r,
            ["bevy_transform::components::transform::Transform"].into_iter(),
        );
        assert_eq!(applicable, ["object"]);
        assert_eq!(resolve_active_category("components", &applicable), "object");
    }

    #[test]
    fn rebuild_resolution_stays_sticky_when_cards_exist() {
        // The Components tab has a card (a generic component), so the active
        // category stays sticky across the rebuild.
        let mut r = InspectorRegistry::default();
        seed_default_categories(&mut r);
        let present = [
            "bevy_transform::components::transform::Transform",
            "my_game::Health",
        ];
        let applicable = applicable_categories(&r, present.iter().copied());
        assert_eq!(applicable, ["object", "components"]);
        assert_eq!(
            resolve_active_category("components", &applicable),
            "components"
        );
    }

    #[test]
    fn rebuild_resolution_empty_applicable_keeps_current() {
        // No cards at all: nothing to fall back to, keep the current tab (the
        // strip still paints object/components, so manual clicks still land).
        assert_eq!(resolve_active_category("components", &[]), "components");
    }
}
