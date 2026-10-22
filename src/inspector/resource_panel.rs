//! The Resources panel: the world's `Resource` values as a searchable,
//! grouped list, and the reflected fields of the one selected.
//!
//! Listing reads bevy main's resource model directly: every resource lives
//! as a component on its own entity, and `World::resource_entities` maps
//! each `ComponentId` to that entity. The selected resource's card reuses
//! the inspector's generic field rows (`spawn_reflected_fields`) with the
//! resource entity as the source, so struct/enum/list/color rows all
//! render unchanged.
//!
//! Field widgets on the selected resource's card commit through the
//! resource write path (`crate::inspector::resource_commands`): the world's
//! ECS only, one undo entry per gesture, and never the scene document,
//! which holds no patch for a resource entity. Edits are therefore
//! editor-session state, not part of the saved scene. The panel's Add
//! button opens a picker of constructible resource types; the card's
//! Remove button takes the resource back out. Both land on the same undo
//! stack.

use std::collections::HashSet;

use bevy::ecs::change_detection::Tick;
use bevy::ecs::reflect::{AppTypeRegistry, ReflectComponent, ReflectResource};
use bevy::ecs::system::SystemState;
use bevy::ecs::world::EntityRef;
use bevy::feathers::controls::FeathersTextInputContainer;
use bevy::input_focus::InputFocus;
use bevy::prelude::*;
use bevy::text::{EditableText, TextEdit};
use bevy::ui::Checked;
use bevy::ui_widgets::Checkbox;
use jackdaw_api::prelude::*;
use jackdaw_feathers::button::{ButtonClickEvent, ButtonProps, button};
use jackdaw_feathers::icons::{EditorFont, Icon, IconFont};
use jackdaw_feathers::number_input::{
    ScrubNumberInput, ScrubNumberInputValue, is_scrubbing_or_focused,
};
use jackdaw_feathers::panel_card::{PanelCardCollapseState, PanelCardProps, spawn_panel_card};
use jackdaw_feathers::picker::{
    Category, Matchable, PickerItems, PickerProps, SelectInput, SpawnItemInput, match_text,
    picker_item,
};
use jackdaw_feathers::text_edit::{TextEditProps, TextEditValue, text_edit};
use jackdaw_feathers::tokens;
use jackdaw_feathers::tooltip::Tooltip;
use jackdaw_localization::LocalizedText;

use super::{FieldBinding, reflect_fields};

/// Engine resource types the panel always offers, as reflect type paths.
///
/// Only types whose `Reflect` registration this build carries are listed;
/// an entry whose type never appears in the world simply never matches.
/// `Time<Virtual>` / `Time<Fixed>` are registered by `TimePlugin`; the
/// panel registers the rest itself (see [`plugin`]). `AmbientLight`
/// itself is a camera component on bevy main, not a resource; the global
/// ambient light is `GlobalAmbientLight`.
pub const ENGINE_RESOURCE_ALLOWLIST: &[&str] = &[
    "bevy_light::ambient_light::GlobalAmbientLight",
    "bevy_camera::clear_color::ClearColor",
    "bevy_gizmos::config::GizmoConfigStore",
    "bevy_time::time::Time<bevy_time::virt::Virtual>",
    "bevy_time::time::Time<bevy_time::fixed::Fixed>",
    // Physics modules register this when a game carries them; never
    // enumerated, never harmful, otherwise.
    "avian3d::math::Gravity",
];

/// Prefixes the default visibility denies, so a broad future allow cannot
/// flood the panel with engine bookkeeping. A deny outranks every allow.
const DEFAULT_DENY_PREFIXES: &[&str] = &[
    // `Assets<T>` storages.
    "bevy_asset::assets",
    // Schedule and registry internals.
    "bevy_ecs::",
    // Render-pipeline state.
    "bevy_render::",
    // Window bookkeeping.
    "bevy_window::",
    // The editor's own state; a specific allow cannot rescue it while the
    // deny stands, which is the intent.
    "jackdaw",
];

/// Type-path filter the Resources panel consults: a resource is listed
/// when no deny suppresses it and one of game type, an allow, or
/// [`ENGINE_RESOURCE_ALLOWLIST`] admits it. Populated with the editor's
/// defaults at startup; extensions and games can extend it at runtime
/// through the `allow_*` / `deny_*` builders.
#[derive(Resource, Default)]
pub struct ResourcePanelVisibility {
    allow_paths: HashSet<&'static str>,
    allow_prefixes: Vec<&'static str>,
    deny_paths: HashSet<&'static str>,
    deny_prefixes: Vec<&'static str>,
}

impl ResourcePanelVisibility {
    /// Admit a single fully-qualified type path.
    pub fn allow_path(&mut self, path: &'static str) -> &mut Self {
        self.allow_paths.insert(path);
        self
    }

    /// Admit every type whose full path starts with `prefix`.
    pub fn allow_prefix(&mut self, prefix: &'static str) -> &mut Self {
        self.allow_prefixes.push(prefix);
        self
    }

    /// Suppress a single fully-qualified type path, outranking any allow.
    pub fn deny_path(&mut self, path: &'static str) -> &mut Self {
        self.deny_paths.insert(path);
        self
    }

    /// Suppress every type whose full path starts with `prefix`,
    /// outranking any allow.
    pub fn deny_prefix(&mut self, prefix: &'static str) -> &mut Self {
        self.deny_prefixes.push(prefix);
        self
    }

    /// True when an allow admits `type_path`.
    pub fn allowed(&self, type_path: &str) -> bool {
        self.allow_paths.contains(type_path)
            || self.allow_prefixes.iter().any(|p| type_path.starts_with(p))
    }

    /// True when a deny suppresses `type_path`.
    pub fn denied(&self, type_path: &str) -> bool {
        self.deny_paths.contains(type_path)
            || self.deny_prefixes.iter().any(|p| type_path.starts_with(p))
    }

    /// Whether the panel lists a resource of this type path: deny first,
    /// then game types (zero-config for a game's own resources), then
    /// allows and the engine allowlist.
    pub fn visible(&self, type_path: &str) -> bool {
        !self.denied(type_path)
            && (crate::type_metadata::is_game_type(type_path)
                || self.allowed(type_path)
                || ENGINE_RESOURCE_ALLOWLIST.contains(&type_path))
    }
}

/// The panel's default visibility: the default denies above over the
/// engine allowlist of [`ResourcePanelVisibility::visible`].
pub fn default_resource_panel_visibility() -> ResourcePanelVisibility {
    let mut visibility = ResourcePanelVisibility::default();
    for prefix in DEFAULT_DENY_PREFIXES {
        visibility.deny_prefix(prefix);
    }
    visibility
}

/// One resource the panel would list.
#[derive(Clone, Debug)]
pub struct ResourceRow {
    /// The reflect type path, which identifies the resource.
    pub type_path: String,
    /// The last path segment, which the row shows.
    pub short_name: String,
    /// The grouping key: `""` is the Game section, otherwise a crate or
    /// authored group name.
    pub group: String,
    /// The entity the resource lives on as a component, which the card
    /// reads its fields from.
    pub entity: Entity,
}

/// Every resource the panel lists, in display order: game groups first,
/// then by group name, then alphabetical by short name.
///
/// Enumerates what the world has instantiated (bevy's resource-entity
/// cache); types that are registered but not yet inserted appear once
/// they exist.
pub fn enumerate_visible_resources(
    world: &World,
    registry: &bevy::reflect::TypeRegistry,
    visibility: &ResourcePanelVisibility,
) -> Vec<ResourceRow> {
    let mut rows = Vec::new();
    for (component_id, entity) in world.resource_entities().iter() {
        let Some(info) = world.components().get_info(component_id) else {
            continue;
        };
        let Some(type_id) = info.type_id() else {
            continue;
        };
        let Some(registration) = registry.get(type_id) else {
            continue;
        };
        let table = registration.type_info().type_path_table();
        let type_path = table.path();
        if !visibility.visible(type_path) {
            continue;
        }
        rows.push(ResourceRow {
            type_path: type_path.to_string(),
            short_name: table.short_path().to_string(),
            group: crate::type_metadata::TypeChrome::default().group(type_path),
            entity,
        });
    }
    rows.sort_by(|a, b| {
        crate::type_metadata::group_order(&b.type_path, "")
            .cmp(&crate::type_metadata::group_order(&a.type_path, ""))
            .then_with(|| a.group.cmp(&b.group))
            .then_with(|| {
                a.short_name
                    .to_lowercase()
                    .cmp(&b.short_name.to_lowercase())
            })
    });
    rows
}

/// Which resource the panel shows a card for, as its type path. `None`
/// shows the select-something hint instead of a card.
#[derive(Resource, Default)]
pub struct ResourcePanelSelection(pub Option<String>);

/// Marker on the panel's root, inside the `jackdaw.inspector.resources`
/// window.
#[derive(Component)]
pub struct ResourcePanelRoot;

/// Marker on the panel's search input.
#[derive(Component)]
pub struct ResourcePanelSearch;

/// Marker on the panel's scrollable body, under the search input.
#[derive(Component)]
pub struct ResourcePanelBody;

/// Marker on the mount whose children are the group headers and resource
/// rows; rebuilt whenever the listed set or the filter changes.
#[derive(Component)]
pub struct ResourceListMount;

/// Marker on the slot the selected resource's card attaches to (and the
/// no-selection hint when nothing is selected).
#[derive(Component)]
pub struct ResourceCardSlot;

/// A resource row's button, carrying what the row names.
#[derive(Component)]
pub struct ResourceRowButton {
    pub type_path: String,
    pub short_name: String,
}

/// The selected resource's card, carrying the type it names and the
/// entity the value lives on.
#[derive(Component, Clone)]
pub struct ResourceCard {
    pub type_path: String,
    pub entity: Entity,
}

/// Marker on the hint shown while no resource is selected.
#[derive(Component)]
pub struct ResourceCardEmpty;

/// Marker on the notice shown while the list holds nothing.
#[derive(Component)]
pub struct ResourceListEmpty;

/// Marker on a field widget that belongs to a resource card rather than a
/// scene entity's inspector, carrying the resource's type path. The field
/// commit path routes resource-entity writes at the resource itself; this
/// marker stays on the widgets so the panel's own refresh can tell its
/// widgets from the inspector's.
#[derive(Component)]
pub struct ResourceFieldTarget {
    pub type_path: String,
}

/// Marker on the panel's "Add Resource" button, which opens the resource
/// type picker.
#[derive(Component)]
pub struct AddResourceButton;

/// Marker on the open resource type picker, so a second Add click closes
/// it rather than stacking another.
#[derive(Component)]
pub struct ResourcePicker;

/// Set by the resource write path after a commit or an insert/remove, so
/// the panel rebuilds the open card: a write can change a list's length or
/// an enum's variant shape, which value sync alone cannot reflow.
#[derive(Resource, Default)]
pub(crate) struct ResourceCardDirty;

/// Build the Resources panel: a filter input and an Add button over a
/// scrollable body. The body holds the list mount and the card slot; both
/// start empty and [`refresh_resource_panel`] fills them.
pub fn resource_panel_content() -> impl Bundle {
    (
        ResourcePanelRoot,
        Node {
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            flex_direction: FlexDirection::Column,
            ..default()
        },
        children![
            (
                Node {
                    padding: UiRect::all(Val::Px(tokens::SPACING_SM)),
                    column_gap: Val::Px(tokens::SPACING_SM),
                    flex_shrink: 0.0,
                    ..default()
                },
                children![
                    (
                        Node {
                            flex_grow: 1.0,
                            min_width: Val::Px(0.0),
                            ..default()
                        },
                        children![(
                            ResourcePanelSearch,
                            text_edit(
                                TextEditProps::default()
                                    .with_placeholder("Filter...")
                                    .allow_empty()
                            )
                        )],
                    ),
                    (
                        AddResourceButton,
                        button(ButtonProps::new("Add Resource").with_left_icon(Icon::Plus)),
                    ),
                ],
            ),
            (
                ResourcePanelBody,
                Node {
                    width: Val::Percent(100.0),
                    flex_grow: 1.0,
                    min_height: Val::Px(0.0),
                    flex_direction: FlexDirection::Column,
                    overflow: Overflow::scroll_y(),
                    padding: UiRect::all(Val::Px(tokens::SPACING_SM)),
                    row_gap: Val::Px(tokens::SPACING_SM),
                    ..default()
                },
                ScrollPosition::default(),
                children![
                    (ResourceListMount, Node::default()),
                    (ResourceCardSlot, Node::default()),
                ],
            ),
        ],
    )
}

/// Select the clicked row's resource. The card swap happens on the next
/// [`refresh_resource_panel`] pass, not in the click.
pub(crate) fn on_resource_row_click(
    event: On<ButtonClickEvent>,
    rows: Query<&ResourceRowButton>,
    mut selection: ResMut<ResourcePanelSelection>,
) {
    let Ok(row) = rows.get(event.entity) else {
        return;
    };
    selection.0 = Some(row.type_path.clone());
}

/// One resource type the Add picker offers.
struct ResourcePickInfo {
    short_name: String,
    group: String,
    type_path: String,
}

impl Matchable for ResourcePickInfo {
    fn haystack(&self) -> String {
        self.short_name.clone()
    }

    fn category(&self) -> Category {
        let name = if self.group.is_empty() {
            "Game".to_string()
        } else {
            self.group.clone()
        };
        Category {
            name: Some(name),
            order: crate::type_metadata::group_order(&self.type_path, ""),
        }
    }
}

/// Resource types the Add picker offers: registered as resources
/// (`ReflectResource`), default-constructible, admitted by the visibility
/// filter, and not already instantiated.
fn enumerate_insertable_resources(
    world: &World,
    registry: &bevy::reflect::TypeRegistry,
    visibility: &ResourcePanelVisibility,
) -> Vec<ResourcePickInfo> {
    let existing: HashSet<String> = world
        .resource_entities()
        .iter()
        .filter_map(|(component_id, _)| {
            let info = world.components().get_info(component_id)?;
            let registration = registry.get(info.type_id()?)?;
            Some(
                registration
                    .type_info()
                    .type_path_table()
                    .path()
                    .to_string(),
            )
        })
        .collect();

    let mut out = Vec::new();
    for registration in registry.iter() {
        if registration.data::<ReflectResource>().is_none() {
            continue;
        }
        if crate::reflect_default::build_reflective_default(registration.type_id(), registry)
            .is_none()
        {
            continue;
        }
        let table = registration.type_info().type_path_table();
        let type_path = table.path();
        if existing.contains(type_path) {
            continue;
        }
        if !visibility.visible(type_path) {
            continue;
        }
        out.push(ResourcePickInfo {
            short_name: table.short_path().to_string(),
            group: crate::type_metadata::TypeChrome::default().group(type_path),
            type_path: type_path.to_string(),
        });
    }
    out
}

/// Handle the "Add Resource" button: toggle the resource type picker, laid
/// out like the inspector's component picker.
pub(crate) fn on_add_resource_button_click(
    event: On<ButtonClickEvent>,
    add_buttons: Query<(), With<AddResourceButton>>,
    existing_pickers: Query<Entity, With<ResourcePicker>>,
    mut commands: Commands,
) {
    if add_buttons.get(event.entity).is_err() {
        return;
    }
    if let Some(picker) = existing_pickers.iter().next() {
        commands.entity(picker).despawn();
        return;
    }
    commands.queue(move |world: &mut World| {
        let registry = world.resource::<AppTypeRegistry>().clone();
        let visibility = world.resource::<ResourcePanelVisibility>();
        let items = {
            let registry = registry.read();
            enumerate_insertable_resources(world, &registry, visibility)
        };
        let picker = PickerProps::new(spawn_resource_picker_item, on_resource_picker_select)
            .items(items)
            .title("Add Resource")
            .placeholder(Some("Search Resources.."));
        world.spawn((
            picker,
            ResourcePicker,
            crate::EditorEntity,
            crate::BlocksCameraInput,
        ));
    });
}

/// One row of the resource picker: the matched name, with the full type
/// path as the tooltip.
fn spawn_resource_picker_item(
    In(SpawnItemInput { matched, entities }): In<SpawnItemInput>,
    items: Query<&PickerItems<ResourcePickInfo>>,
    mut commands: Commands,
) -> Result {
    let info = items.get(entities.picker)?.at(matched.index)?;
    commands.spawn((
        picker_item(matched.index),
        ChildOf(entities.list),
        Tooltip::title(matched.haystack).with_description(info.type_path.clone()),
        children![match_text(matched.segments)],
    ));
    Ok(())
}

/// Insert the picked resource type through the Add Resource operator, and
/// make the panel show its card right away.
fn on_resource_picker_select(
    input: In<SelectInput>,
    items: Query<&PickerItems<ResourcePickInfo>>,
    mut commands: Commands,
) -> Result {
    let info = items.get(input.entities.picker)?.at(input.index)?;
    commands
        .operator(crate::inspector::resource_ops::ResourceInsertOp::ID)
        .param("type_path", info.type_path.clone())
        .call();
    commands.entity(input.entities.picker).try_despawn();
    Ok(())
}

/// Keep the Resources panel in step with the world: rebuild the list when
/// the visible set or the filter changes, swap the card when the
/// selection moves or its entity goes away, and sync the card's field
/// widgets with the resource's current value.
pub(crate) fn refresh_resource_panel(
    world: &mut World,
    mut last_run: Local<Option<Tick>>,
    mut last_filter: Local<String>,
) {
    let this_run = world.read_change_tick();
    let prev_run = last_run.replace(this_run);

    let filter = {
        let mut search = world.query_filtered::<&TextEditValue, With<ResourcePanelSearch>>();
        search
            .iter(world)
            .next()
            .map(|value| value.0.trim().to_lowercase())
            .unwrap_or_default()
    };

    let rows = {
        let type_registry = world.resource::<AppTypeRegistry>().clone();
        let registry = type_registry.read();
        let visibility = world.resource::<ResourcePanelVisibility>();
        enumerate_visible_resources(world, &registry, visibility)
    };

    let (mount, card_slot) = {
        let mut body = world.query_filtered::<&Children, With<ResourcePanelBody>>();
        let Some(children) = body
            .iter(world)
            .next()
            .map(|c| c.iter().collect::<Vec<Entity>>())
        else {
            return;
        };
        let mount = children
            .iter()
            .copied()
            .find(|child| world.get::<ResourceListMount>(*child).is_some());
        let slot = children
            .iter()
            .copied()
            .find(|child| world.get::<ResourceCardSlot>(*child).is_some());
        (mount, slot)
    };
    let (Some(mount), Some(card_slot)) = (mount, card_slot) else {
        return;
    };

    // Rebuild the list when the visible set or the filter changed. The
    // search input sits outside the mount, so typing keeps the focus. The
    // comparison reads only this mount's rows, so another panel instance
    // (a test-spawned one beside the window's) never forces a rebuild.
    let mut shown: Vec<String> = {
        let mut buttons = world.query::<&ResourceRowButton>();
        world
            .get::<Children>(mount)
            .map(|children| {
                children
                    .iter()
                    .filter_map(|child| buttons.get(world, child).ok())
                    .map(|button| button.type_path.clone())
                    .collect()
            })
            .unwrap_or_default()
    };
    shown.sort();
    let mut wanted: Vec<String> = rows.iter().map(|row| row.type_path.clone()).collect();
    wanted.sort();
    if shown != wanted || filter != *last_filter {
        rebuild_resource_list(world, mount, &rows, &filter);
        *last_filter = filter;
    }

    // Keep a card on a live selection. A card whose resource entity went
    // away (the resource removed, or re-inserted on a fresh entity) is
    // rebuilt too; a selection naming a resource that is no longer listed
    // is dropped.
    let selection = world.resource::<ResourcePanelSelection>().0.clone();
    let selected_row = selection
        .as_ref()
        .and_then(|type_path| rows.iter().find(|row| &row.type_path == type_path));
    let card = {
        let mut cards = world.query::<&ResourceCard>();
        cards.iter(world).next().cloned()
    };
    let card = card.filter(|card| world.get_entity(card.entity).is_ok());
    // A committed write asked for a rebuild: the card's shape may have
    // changed (a list's length, an enum's variant) even though the
    // selection did not move.
    let card_dirty = world.remove_resource::<ResourceCardDirty>().is_some();

    match (selected_row, card) {
        (None, Some(_)) => {
            despawn_resource_card(world);
            spawn_resource_card_hint(world, card_slot);
        }
        (None, None) => spawn_resource_card_hint(world, card_slot),
        (Some(row), Some(card)) if card_dirty || card.type_path != row.type_path => {
            despawn_resource_card(world);
            fill_resource_card(world, card_slot, row);
        }
        (Some(row), None) => {
            despawn_resource_card(world);
            fill_resource_card(world, card_slot, row);
        }
        (Some(_), Some(card)) => {
            let Some(prev) = prev_run else {
                return;
            };
            let changed = world.get_entity(card.entity).is_ok_and(|entity_ref| {
                reflect_fields::entity_components_changed(entity_ref, prev, this_run)
            });
            if changed {
                sync_resource_field_widgets(world, card.entity, &card.type_path);
            }
        }
    }
}

/// Rebuild the list under `mount`: a header per group (Game first) and a
/// button per resource, or the empty notice when nothing matches.
fn rebuild_resource_list(world: &mut World, mount: Entity, rows: &[ResourceRow], filter: &str) {
    despawn_descendants(world, mount);

    let mut commands = world.commands();
    let matching: Vec<&ResourceRow> = rows
        .iter()
        .filter(|row| filter.is_empty() || row.short_name.to_lowercase().contains(filter))
        .collect();
    if matching.is_empty() {
        commands.spawn((
            ResourceListEmpty,
            LocalizedText::new("resources-empty"),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..default()
            },
            TextColor(tokens::TEXT_SECONDARY),
            ChildOf(mount),
        ));
        world.flush();
        return;
    }

    let mut current_group: Option<&str> = None;
    for row in matching {
        if current_group != Some(row.group.as_str()) {
            current_group = Some(row.group.as_str());
            let label = if row.group.is_empty() {
                "Game".to_string()
            } else {
                row.group.clone()
            };
            commands.spawn((
                Text::new(label),
                TextFont {
                    font_size: tokens::TEXT_SIZE_SM,
                    weight: FontWeight::MEDIUM,
                    ..default()
                },
                TextColor(tokens::TEXT_SECONDARY),
                ChildOf(mount),
            ));
        }
        commands.spawn((
            ResourceRowButton {
                type_path: row.type_path.clone(),
                short_name: row.short_name.clone(),
            },
            button(ButtonProps::new(row.short_name.clone()).align_left()),
            Tooltip::title(row.type_path.clone()),
            ChildOf(mount),
        ));
    }
    world.flush();
}

/// Spawn the selected resource's card: a titled, collapsible panel card
/// whose body is the resource's reflected fields, read live off the
/// resource entity through one system-state borrow.
fn fill_resource_card(world: &mut World, card_slot: Entity, row: &ResourceRow) {
    despawn_card_hint(world);

    let icon_font = world.resource::<IconFont>().0.clone();
    let editor_font = world.resource::<EditorFont>().0.clone();
    let props = PanelCardProps::new(row.short_name.clone())
        .with_icon(Icon::Database)
        .remembered_as(format!("resource:{}", row.type_path));
    let section = {
        let mut state: SystemState<(
            Commands,
            Query<&Name>,
            Query<EntityRef>,
            Res<AppTypeRegistry>,
            Res<PanelCardCollapseState>,
        )> = SystemState::new(world);
        let Ok((mut commands, names, entity_refs, type_registry, collapse)) = state.get_mut(world)
        else {
            return;
        };
        let registry = type_registry.read();
        let reflected = entity_refs.get(row.entity).ok().and_then(|entity_ref| {
            let registration = registry.get_with_type_path(&row.type_path)?;
            registration
                .data::<ReflectComponent>()
                .and_then(|reflect_component| reflect_component.reflect(entity_ref))
        });
        let card = spawn_panel_card(&mut commands, card_slot, props, &icon_font, &collapse);
        commands.entity(card.section).insert(ResourceCard {
            type_path: row.type_path.clone(),
            entity: row.entity,
        });
        // The card's own action: take the resource back out. The operator
        // acts on the panel's selection, which is this card's resource.
        commands.spawn((
            button(ButtonProps::from_operator::<
                crate::inspector::resource_ops::ResourceRemoveOp,
            >()),
            ChildOf(card.body),
        ));
        match reflected {
            Some(reflected) => {
                reflect_fields::spawn_reflected_fields(
                    &mut commands,
                    card.body,
                    reflected,
                    0,
                    String::new(),
                    row.entity,
                    &row.type_path,
                    &names,
                    &type_registry,
                    &editor_font,
                    &icon_font,
                );
            }
            // The registry knows the type but carries no component data
            // for it, so there is nothing to reflect over: say so.
            None => {
                commands.spawn((
                    LocalizedText::new("read-only"),
                    TextFont {
                        font_size: tokens::TEXT_SIZE_SM,
                        ..default()
                    },
                    TextColor(tokens::TEXT_SECONDARY),
                    ChildOf(card.body),
                ));
            }
        }
        drop(registry);
        let section = card.section;
        state.apply(world);
        section
    };

    stamp_resource_field_targets(world, section, &row.type_path);
}

/// Mark every field widget under the card as writing a resource, so the
/// commit path can route writes at the resource rather than the document.
fn stamp_resource_field_targets(world: &mut World, card: Entity, type_path: &str) {
    let mut stack = vec![card];
    let mut targets: Vec<Entity> = Vec::new();
    while let Some(entity) = stack.pop() {
        if world.get::<FieldBinding>(entity).is_some()
            && world.get::<ResourceFieldTarget>(entity).is_none()
        {
            targets.push(entity);
        }
        if let Some(children) = world.get::<Children>(entity) {
            stack.extend(children.iter());
        }
    }
    for target in targets {
        world.entity_mut(target).insert(ResourceFieldTarget {
            type_path: type_path.to_string(),
        });
    }
}

/// Pull the card's field widgets back in line with the resource's current
/// value: numbers, checkboxes and text inputs. Skips widgets someone is
/// scrubbing or typing in, like the inspector's own refresh. Enum hosts
/// are not rebuilt here; their fields refresh, the variant follows on the
/// next card rebuild.
fn sync_resource_field_widgets(world: &mut World, resource_entity: Entity, type_path: &str) {
    // Every query is built and drained before the resource entity is
    // borrowed, so the world is free while the lookups are collected.
    let scrub_lookups: Vec<(Entity, String, ScrubNumberInputValue)> = {
        let mut scrub_query = world.query_filtered::<
            (Entity, &FieldBinding, &ScrubNumberInputValue),
            (With<ScrubNumberInput>, With<ResourceFieldTarget>),
        >();
        scrub_query
            .iter(world)
            .filter(|(_, binding, _)| binding.source_entity == resource_entity)
            .map(|(entity, binding, value)| (entity, binding.field_path.clone(), *value))
            .collect()
    };

    let bool_lookups: Vec<(Entity, String, bool)> = {
        let mut bool_query = world.query_filtered::<
            (Entity, &FieldBinding, Has<Checked>),
            (With<Checkbox>, With<ResourceFieldTarget>),
        >();
        bool_query
            .iter(world)
            .filter(|(_, binding, _)| binding.source_entity == resource_entity)
            .map(|(entity, binding, checked)| (entity, binding.field_path.clone(), checked))
            .collect()
    };

    let text_lookups: Vec<(Entity, String, String)> = {
        let mut text_query = world.query_filtered::<
            (Entity, &FieldBinding),
            (With<FeathersTextInputContainer>, With<ResourceFieldTarget>),
        >();
        let mut editables = world.query::<&EditableText>();
        let containers: Vec<(Entity, String)> = text_query
            .iter(world)
            .filter(|(_, binding)| binding.source_entity == resource_entity)
            .map(|(entity, binding)| (entity, binding.field_path.clone()))
            .collect();
        let mut lookups = Vec::new();
        for (container, field_path) in containers {
            let mut stack = vec![container];
            let mut text_entity = None;
            while let Some(entity) = stack.pop() {
                if entity != container && editables.get(world, entity).is_ok() {
                    text_entity = Some(entity);
                    break;
                }
                if let Some(children) = world.get::<Children>(entity) {
                    stack.extend(children.iter());
                }
            }
            let Some(text_entity) = text_entity else {
                continue;
            };
            let shown = editables
                .get(world, text_entity)
                .map(|editable| editable.value().to_string())
                .unwrap_or_default();
            lookups.push((text_entity, field_path, shown));
        }
        lookups
    };

    if scrub_lookups.is_empty() && bool_lookups.is_empty() && text_lookups.is_empty() {
        return;
    }

    let type_registry = world.resource::<AppTypeRegistry>().clone();
    let registry = type_registry.read();
    let Ok(entity_ref) = world.get_entity(resource_entity) else {
        return;
    };
    let read = |field_path: &str| -> Option<&dyn bevy::reflect::PartialReflect> {
        let registration = registry.get_with_type_path(type_path)?;
        let reflected = registration
            .data::<ReflectComponent>()?
            .reflect(entity_ref)?;
        crate::commands::read_field_path(reflected.as_partial_reflect(), field_path)
    };

    let mut scrub_updates: Vec<(Entity, ScrubNumberInputValue)> = Vec::new();
    for (widget, field_path, current) in &scrub_lookups {
        let Some(field) = read(field_path) else {
            continue;
        };
        let Some(value) = reflect_fields::reflect_field_to_f64(field) else {
            continue;
        };
        let update = match current {
            ScrubNumberInputValue::I64(current) => {
                let new = value.round() as i64;
                (new != *current).then_some(ScrubNumberInputValue::I64(new))
            }
            _ => {
                let new = reflect_fields::round_numeric_display(value);
                ((new - reflect_fields::scrub_value_as_f64(current)).abs() > 0.005)
                    .then_some(ScrubNumberInputValue::F64(new))
            }
        };
        if let Some(update) = update {
            scrub_updates.push((*widget, update));
        }
    }

    let mut bool_updates: Vec<(Entity, bool)> = Vec::new();
    for (widget, field_path, current) in &bool_lookups {
        let Some(field) = read(field_path) else {
            continue;
        };
        if let Some(&value) = field.try_downcast_ref::<bool>()
            && value != *current
        {
            bool_updates.push((*widget, value));
        }
    }

    let mut text_updates: Vec<(Entity, String)> = Vec::new();
    for (widget, field_path, shown) in &text_lookups {
        let Some(field) = read(field_path) else {
            continue;
        };
        if let Some(text) = field.try_downcast_ref::<String>()
            && text != shown
        {
            text_updates.push((*widget, text.clone()));
        }
    }

    drop(registry);

    let input_focus = world.resource::<InputFocus>().get();

    // A string field shows what the resource now holds, unless someone is
    // typing in it.
    for (widget, text) in text_updates {
        if input_focus == Some(widget) {
            continue;
        }
        if let Some(mut editable) = world.get_mut::<EditableText>(widget) {
            editable.queue_edit(TextEdit::SelectAll);
            editable.queue_edit(TextEdit::Insert(text.clone().into()));
        }
        world
            .entity_mut(widget)
            .insert(reflect_fields::ShownFieldText(text));
    }

    // Number fields re-insert their value; the widget's own insert
    // observer repaints the text. Skipped mid-scrub or mid-typing so a
    // gesture is never clobbered.
    for (widget, value) in scrub_updates {
        if is_scrubbing_or_focused(world, widget, input_focus) {
            continue;
        }
        world.entity_mut(widget).insert(value);
    }

    // Checkboxes render off `Checked`, so an external change (there is no
    // in-panel edit yet) lands as the marker.
    for (widget, value) in bool_updates {
        let Ok(mut entity) = world.get_entity_mut(widget) else {
            continue;
        };
        if value {
            entity.insert(Checked);
        } else {
            entity.remove::<Checked>();
        }
    }
}

/// Register the Resources panel with the inspector: the engine types the
/// allowlist names (so the registry can resolve them), the visibility and
/// selection state, the row-click observer, and the refresh pass.
pub(crate) fn plugin(app: &mut App) {
    // The allowlist names engine types nothing else registers; their
    // `#[reflect(Resource)]` data comes with the derive.
    app.register_type::<bevy::light::GlobalAmbientLight>()
        .register_type::<bevy::camera::ClearColor>()
        .register_type::<bevy::gizmos::config::GizmoConfigStore>()
        .insert_resource(default_resource_panel_visibility())
        .init_resource::<ResourcePanelSelection>()
        .init_resource::<super::resource_commands::ResourceFieldEditSessions>()
        .add_observer(on_resource_row_click)
        .add_observer(on_add_resource_button_click)
        .add_systems(
            Update,
            refresh_resource_panel.run_if(in_state(crate::AppState::Editor)),
        );
}

fn despawn_resource_card(world: &mut World) {
    let mut cards = world.query_filtered::<Entity, With<ResourceCard>>();
    for card in cards.iter(world).collect::<Vec<_>>() {
        if let Ok(entity) = world.get_entity_mut(card) {
            entity.despawn();
        }
    }
}

fn spawn_resource_card_hint(world: &mut World, card_slot: Entity) {
    let mut hints = world.query_filtered::<Entity, With<ResourceCardEmpty>>();
    if hints.iter(world).next().is_some() {
        return;
    }
    let mut commands = world.commands();
    commands.spawn((
        ResourceCardEmpty,
        LocalizedText::new("resources-none-selected"),
        TextFont {
            font_size: tokens::TEXT_SIZE_SM,
            ..default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        ChildOf(card_slot),
    ));
    world.flush();
}

fn despawn_card_hint(world: &mut World) {
    let mut hints = world.query_filtered::<Entity, With<ResourceCardEmpty>>();
    for hint in hints.iter(world).collect::<Vec<_>>() {
        if let Ok(entity) = world.get_entity_mut(hint) {
            entity.despawn();
        }
    }
}

fn despawn_descendants(world: &mut World, parent: Entity) {
    let Some(children) = world.get::<Children>(parent) else {
        return;
    };
    let children: Vec<Entity> = children.iter().collect();
    for child in children {
        if let Ok(entity) = world.get_entity_mut(child) {
            entity.despawn();
        }
    }
}
