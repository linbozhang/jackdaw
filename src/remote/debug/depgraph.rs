//! System dependency graph panel: one schedule's systems as a layered node
//! graph, drawn via `graph::spawn_graph`, with dependency-ordering edges and
//! scheduler ambiguities. Reads the same polled `SchedulesReply` the
//! Schedules panel reads (`schedules.rs`); no separate poll.
//!
//! On top of the plain graph, the panel filters and colors nodes by
//! component data access (`AccessFilter`): systems that access the filtered
//! components are accent-highlighted, the rest dimmed, and every node shows
//! an `R3 W1` read/write badge (`EXCL`/`ALL` for exclusive/unbounded
//! systems). The filter row offers a component picker (AND semantics: every
//! picked component must be accessed), a "From selection" button that
//! reverse-derives the component set from the currently selected entity
//! (OR semantics: any accessed component counts) and a clear button.
//! Replies from older `jackdaw_remote` versions carry no access data
//! (`access_reported == false`): the filter row degrades to a hint and the
//! graph renders exactly as before the feature.

use std::collections::BTreeSet;

use bevy::prelude::*;
use jackdaw_feathers::button::{ButtonClickEvent, ButtonProps, ButtonVariant, button};
use jackdaw_feathers::picker::{
    PickerItems, PickerProps, SelectInput, SpawnItemInput, match_text, picker_item,
};
use jackdaw_feathers::tokens;
use jackdaw_remote::scene_snapshot::RemoteEntity;

use super::super::entity_browser::{RemoteSceneCache, RemoteSelection};
use super::graph::{self, GraphEdgeMaterial, GraphNodeSpec};
use super::schedules::{ACCESS_READ, ACCESS_UNBOUNDED, ACCESS_WRITE, SchedulesReply, SystemInfo};
use super::style;
use crate::selection::Selection;

/// Which schedule's graph is shown. Defaults to `"Update"`; the rebuild
/// system falls back to the reply's first schedule if `"Update"` is absent.
#[derive(Resource)]
pub struct SelectedSchedule(pub String);

impl Default for SelectedSchedule {
    fn default() -> Self {
        Self("Update".to_string())
    }
}

// --------------------------- Filter state ---------------------------

/// How the current [`AccessFilter`] was built: hand-picked components (AND
/// semantics) or derived from the selection (OR semantics). Any manual edit
/// to a selection-derived filter (adding or removing a chip) flips it back
/// to `Manual`, since the set no longer mirrors the selection.
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub enum FilterSource {
    #[default]
    Manual,
    Selection {
        /// How many components the selection contributed at resolve time.
        used: usize,
    },
}

/// The System Graph's component-access filter: which component type names
/// to highlight systems by. Empty `components` means no filtering (the
/// graph renders unhighlighted).
#[derive(Resource, Clone, Debug, PartialEq, Eq, Default)]
pub struct AccessFilter {
    pub components: Vec<String>,
    pub source: FilterSource,
}

// --------------------------- Filter pure functions ---------------------------

/// True when `system`'s access table names `component`: full type-path
/// equality first, then a final-`::`-segment fallback so names from the
/// reflect registry (scene snapshot keys) still match the `Components`
/// registry names the access table uses. Exclusive systems and `unbounded`
/// accesses touch everything, so they match any component.
pub fn access_matches(system: &SystemInfo, component: &str) -> bool {
    if component.is_empty() {
        return false;
    }
    if system.exclusive {
        return true;
    }
    let short = style::short_type_name(component);
    system.accesses.iter().any(|access| {
        access.kind == ACCESS_UNBOUNDED
            || (!access.component.is_empty()
                && (access.component == component
                    || style::short_type_name(&access.component) == short))
    })
}

/// True when `system` accesses any of `components` (OR semantics, the
/// reverse-lookup question "which systems could touch this entity?").
pub fn matches_any(components: &[String], system: &SystemInfo) -> bool {
    components
        .iter()
        .any(|component| access_matches(system, component))
}

/// True when `system` passes `filter`. Manual picks use AND (every picked
/// component must be accessed; an empty manual filter matches everything);
/// a selection-derived filter uses OR via [`matches_any`].
pub fn matches_filter(filter: &AccessFilter, system: &SystemInfo) -> bool {
    match filter.source {
        FilterSource::Manual => filter
            .components
            .iter()
            .all(|component| access_matches(system, component)),
        FilterSource::Selection { .. } => matches_any(&filter.components, system),
    }
}

/// The sorted, deduplicated union of component names across every system's
/// access table in the reply: the filter picker's candidates, so every
/// candidate is guaranteed to be named by at least one system. Empty-string
/// components (the `unbounded` marker entries, which match any filter) are
/// excluded.
pub fn access_component_options(reply: &SchedulesReply) -> Vec<String> {
    let mut names = BTreeSet::new();
    for schedule in &reply.schedules {
        for system in &schedule.systems {
            for access in &system.accesses {
                if !access.component.is_empty() {
                    names.insert(access.component.clone());
                }
            }
        }
    }
    names.into_iter().collect()
}

/// Node box background for a system node: accent-highlighted when it passes
/// an active filter, dimmed (same card color, lower alpha) when it does not,
/// and the normal card surface whenever no filter is active — the
/// pre-feature default.
pub fn node_color(filtering: bool, hit: bool) -> Color {
    match (filtering, hit) {
        (true, true) => tokens::ACCENT_BLUE.with_alpha(0.28),
        (true, false) => tokens::COMPONENT_CARD_BG.with_alpha(0.35),
        (false, _) => tokens::COMPONENT_CARD_BG,
    }
}

/// The small access badge under a node label: `R3 W1` read/write counts,
/// `ALL` for an unbounded access (may touch any component), `EXCL` for an
/// exclusive (`&mut World`) system, and `None` when the system reports no
/// interpreted accesses (older replies, or access-only-presence systems).
pub fn access_badge(system: &SystemInfo) -> Option<String> {
    if system.exclusive {
        return Some("EXCL".to_string());
    }
    if system
        .accesses
        .iter()
        .any(|access| access.kind == ACCESS_UNBOUNDED)
    {
        return Some("ALL".to_string());
    }
    let reads = system
        .accesses
        .iter()
        .filter(|access| access.kind == ACCESS_READ)
        .count();
    let writes = system
        .accesses
        .iter()
        .filter(|access| access.kind == ACCESS_WRITE)
        .count();
    if reads + writes == 0 {
        None
    } else {
        Some(format!("R{reads} W{writes}"))
    }
}

/// The component names of the currently selected remote entity, from the
/// scene-snapshot cache: the keys of its components map, sorted. Empty when
/// nothing is selected or the selected entity is not in the cache (e.g.
/// despawned since the last snapshot).
pub fn selection_components(sel: Option<u64>, entities: &[RemoteEntity]) -> Vec<String> {
    let Some(bits) = sel else {
        return Vec::new();
    };
    let mut names: Vec<String> = entities
        .iter()
        .find(|entity| entity.entity == bits)
        .map(|entity| entity.components.keys().cloned().collect())
        .unwrap_or_default();
    names.sort();
    names
}

/// The component names of the editor's local selection (authoring or PIE
/// preview entities) from their archetypes, sorted and deduplicated. The
/// fallback path for "From selection" when no BRP-live entity is selected.
fn local_selection_components(world: &World) -> Vec<String> {
    let selection = world.resource::<Selection>();
    let mut names = BTreeSet::new();
    for &entity in &selection.entities {
        let Ok(entity_ref) = world.get_entity(entity) else {
            continue;
        };
        for id in entity_ref.archetype().components() {
            if let Some(info) = world.components().get_info(*id) {
                names.insert(info.name().to_string());
            }
        }
    }
    names.into_iter().collect()
}

#[derive(Component)]
struct DepgraphPanel;

#[derive(Component)]
pub(crate) struct DepgraphMeta;

#[derive(Component)]
pub(crate) struct DepgraphSelector;

/// Marks the filter row between the schedule selector and the ambiguity
/// banner; rebuilt reactively like the other panel sections.
#[derive(Component)]
pub(crate) struct DepgraphFilterRow;

#[derive(Component)]
pub(crate) struct DepgraphBanner;

#[derive(Component)]
pub(crate) struct DepgraphCanvas;

/// Marks a schedule-selector button with the schedule name it selects.
#[derive(Component)]
pub(crate) struct ScheduleButton(String);

/// Opens the component-access picker for the filter.
#[derive(Component)]
pub(crate) struct AddAccessFilterButton;

/// One selected filter component; clicking removes it from the filter.
#[derive(Component)]
pub(crate) struct AccessFilterChip {
    type_path: String,
}

/// Runs "From selection": derives the filter from the current selection.
#[derive(Component)]
pub(crate) struct FromSelectionButton;

/// Clears the filter.
#[derive(Component)]
pub(crate) struct ClearFilterButton;

/// Marks the component picker opened for the access filter.
#[derive(Component)]
pub(crate) struct AccessFilterPicker;

// --------------------------- Panel ---------------------------

/// Build the dependency graph panel content (no header: the dock tab is the
/// title).
pub fn depgraph_panel_content() -> impl Bundle {
    (
        DepgraphPanel,
        Node {
            width: Val::Percent(100.0),
            height: Val::Percent(100.0),
            flex_direction: FlexDirection::Column,
            ..default()
        },
        BackgroundColor(tokens::PANEL_BG),
        children![
            (
                DepgraphMeta,
                Node {
                    width: Val::Percent(100.0),
                    ..default()
                },
            ),
            (
                DepgraphSelector,
                Node {
                    flex_direction: FlexDirection::Row,
                    flex_wrap: FlexWrap::Wrap,
                    column_gap: Val::Px(tokens::SPACING_SM),
                    row_gap: Val::Px(tokens::SPACING_SM),
                    padding: UiRect::axes(Val::Px(tokens::SPACING_MD), Val::Px(tokens::SPACING_SM)),
                    ..default()
                },
            ),
            (
                DepgraphFilterRow,
                Node {
                    flex_direction: FlexDirection::Row,
                    flex_wrap: FlexWrap::Wrap,
                    align_items: AlignItems::Center,
                    column_gap: Val::Px(tokens::SPACING_SM),
                    row_gap: Val::Px(tokens::SPACING_SM),
                    padding: UiRect::axes(Val::Px(tokens::SPACING_MD), Val::Px(tokens::SPACING_SM)),
                    ..default()
                },
            ),
            (
                DepgraphBanner,
                Node {
                    width: Val::Percent(100.0),
                    ..default()
                },
            ),
            (
                Node {
                    flex_direction: FlexDirection::Column,
                    width: Val::Percent(100.0),
                    flex_grow: 1.0,
                    min_height: Val::Px(0.0),
                    ..default()
                },
                children![(
                    DepgraphCanvas,
                    Node {
                        width: Val::Percent(100.0),
                        height: Val::Percent(100.0),
                        ..default()
                    },
                )],
            ),
        ],
    )
}

/// A warning-tinted banner explaining what "ambiguities" means, shown only
/// when the selected schedule has at least one.
fn ambiguity_banner(count: usize) -> impl Bundle {
    let warning = Color::Srgba(tokens::DESTRUCTIVE_RED);
    (
        Node {
            width: Val::Percent(100.0),
            padding: UiRect::axes(Val::Px(tokens::SPACING_MD), Val::Px(tokens::SPACING_SM)),
            border: UiRect::bottom(Val::Px(1.0)),
            ..default()
        },
        BackgroundColor(warning.with_alpha(0.12)),
        BorderColor::all(warning),
        children![(
            Text::new(format!(
                "{count} ambiguities: unordered systems with conflicting data access"
            )),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..default()
            },
            TextColor(warning),
        )],
    )
}

/// A removable access-filter chip for one component, in the Live Queries
/// builder's chip style.
fn access_filter_chip(component: &str) -> impl Bundle {
    (
        button(
            ButtonProps::new(format!("{}  x", style::short_type_name(component)))
                .with_variant(ButtonVariant::Default),
        ),
        AccessFilterChip {
            type_path: component.to_string(),
        },
    )
}

/// Rebuild the selector row, meta line, filter row, banner, and graph canvas
/// when the reply, selected schedule, or access filter changes, or the panel
/// opens.
pub(crate) fn rebuild_depgraph(
    reply: Option<Res<SchedulesReply>>,
    selected: Res<SelectedSchedule>,
    filter: Res<AccessFilter>,
    remote_selection: Res<RemoteSelection>,
    local_selection: Res<Selection>,
    mut commands: Commands,
    mut materials: ResMut<Assets<GraphEdgeMaterial>>,
    meta_containers: Query<Entity, With<DepgraphMeta>>,
    selector_containers: Query<Entity, With<DepgraphSelector>>,
    filter_containers: Query<Entity, With<DepgraphFilterRow>>,
    banner_containers: Query<Entity, With<DepgraphBanner>>,
    canvas_containers: Query<Entity, With<DepgraphCanvas>>,
    new_ui: Query<
        (),
        Or<(
            Added<DepgraphMeta>,
            Added<DepgraphSelector>,
            Added<DepgraphFilterRow>,
            Added<DepgraphBanner>,
            Added<DepgraphCanvas>,
        )>,
    >,
) {
    let reply_changed = matches!(reply.as_ref(), Some(r) if r.is_changed());
    if !reply_changed && !selected.is_changed() && !filter.is_changed() && new_ui.is_empty() {
        return;
    }

    let schedules = reply
        .as_ref()
        .map(|r| r.schedules.as_slice())
        .unwrap_or(&[]);
    let active = schedules
        .iter()
        .find(|s| s.schedule == selected.0)
        .or_else(|| schedules.first());

    for container in &selector_containers {
        commands.entity(container).despawn_children();
        for info in schedules {
            let is_active = active.is_some_and(|a| a.schedule == info.schedule);
            let variant = if is_active {
                ButtonVariant::Active
            } else {
                ButtonVariant::Default
            };
            commands.spawn((
                button(ButtonProps::new(info.schedule.clone()).with_variant(variant)),
                ScheduleButton(info.schedule.clone()),
                ChildOf(container),
            ));
        }
    }

    // Access data comes from the reply's capability flag; without it the
    // filter row degrades to a hint and the graph renders unfiltered.
    let access_data = reply.as_ref().is_some_and(|r| r.access_reported);

    let mut meta_right = match active {
        Some(info) => {
            let edge_total = info.edges.len() + info.ambiguities.len();
            let mut text = format!(
                "{}: {} systems, {} ambiguities",
                info.schedule,
                info.systems.len(),
                info.ambiguities.len()
            );
            if let FilterSource::Selection { used } = filter.source
                && access_data
                && !filter.components.is_empty()
            {
                text.push_str(&format!(", from selection: {used} components"));
            }
            if edge_total > graph::MAX_EDGES {
                text.push_str(&format!(
                    ", showing {} of {edge_total} edges",
                    graph::MAX_EDGES
                ));
            }
            text
        }
        None => "no schedules".to_string(),
    };
    if !access_data {
        meta_right.push_str(", access data unavailable");
    }
    for container in &meta_containers {
        commands.entity(container).despawn_children();
        commands.spawn((
            style::panel_meta("System dependency graph", &meta_right),
            ChildOf(container),
        ));
    }

    for container in &filter_containers {
        commands.entity(container).despawn_children();
        if !access_data {
            // Degradation: older `jackdaw_remote` replies carry no access
            // data, so filtering, badges, and reverse lookup are hidden.
            commands.spawn((
                (
                    Text::new("component access data requires a newer jackdaw_remote"),
                    TextFont {
                        font_size: tokens::TEXT_SIZE_SM,
                        ..default()
                    },
                    TextColor(tokens::TEXT_SECONDARY),
                ),
                ChildOf(container),
            ));
            continue;
        }
        commands.spawn((
            button(ButtonProps::new("Add component").with_variant(ButtonVariant::Default)),
            AddAccessFilterButton,
            ChildOf(container),
        ));
        for component in &filter.components {
            commands.spawn((access_filter_chip(component), ChildOf(container)));
        }
        let has_selection =
            remote_selection.selected.is_some() || !local_selection.entities.is_empty();
        let from_variant = if has_selection {
            ButtonVariant::Default
        } else {
            ButtonVariant::Disabled
        };
        commands.spawn((
            button(ButtonProps::new("From selection").with_variant(from_variant)),
            FromSelectionButton,
            ChildOf(container),
        ));
        if !filter.components.is_empty() {
            commands.spawn((
                button(ButtonProps::new("Clear").with_variant(ButtonVariant::Ghost)),
                ClearFilterButton,
                ChildOf(container),
            ));
        }
    }

    let ambiguity_count = active.map(|a| a.ambiguities.len()).unwrap_or(0);
    for container in &banner_containers {
        commands.entity(container).despawn_children();
        if ambiguity_count > 0 {
            commands.spawn((ambiguity_banner(ambiguity_count), ChildOf(container)));
        }
    }

    for container in &canvas_containers {
        commands.entity(container).despawn_children();
        let Some(info) = active else { continue };
        let filtering = access_data && !filter.components.is_empty();
        let nodes: Vec<GraphNodeSpec> = info
            .systems
            .iter()
            .map(|s| GraphNodeSpec {
                label: style::short_type_name(&s.name),
                subtitle: access_data.then(|| access_badge(s)).flatten(),
            })
            .collect();
        let node_colors: Vec<Color> = info
            .systems
            .iter()
            .map(|s| node_color(filtering, filtering && matches_filter(&filter, s)))
            .collect();
        let ambiguities: Vec<(usize, usize)> =
            info.ambiguities.iter().map(|a| (a.a, a.b)).collect();
        graph::spawn_graph(
            &mut commands,
            &mut materials,
            container,
            &nodes,
            &info.edges,
            &ambiguities,
            &node_colors,
        );
    }
}

/// Select a schedule when its selector button is clicked.
pub(crate) fn on_schedule_button_clicked(
    event: On<ButtonClickEvent>,
    buttons: Query<&ScheduleButton>,
    mut selected: ResMut<SelectedSchedule>,
) {
    let Ok(target) = buttons.get(event.entity) else {
        return;
    };
    if selected.0 != target.0 {
        selected.0 = target.0.clone();
    }
}

// --------------------------- Filter interaction ---------------------------

/// Open the component-access picker when the filter row's "Add component"
/// button is clicked. Candidates are the reply's access-name union, so every
/// option is guaranteed to match at least one system.
pub(crate) fn on_add_access_filter_clicked(
    event: On<ButtonClickEvent>,
    add_buttons: Query<(), With<AddAccessFilterButton>>,
    open_pickers: Query<Entity, With<AccessFilterPicker>>,
    reply: Option<Res<SchedulesReply>>,
    mut commands: Commands,
) {
    if add_buttons.get(event.entity).is_err() {
        return;
    }

    // Toggle: a second click while a picker is open closes it.
    if let Some(picker) = open_pickers.iter().next() {
        commands.entity(picker).despawn();
        return;
    }

    let Some(reply) = reply else { return };
    let options = access_component_options(&reply);
    if options.is_empty() {
        return;
    }

    let props = PickerProps::new(access_picker_spawn_item, access_picker_select)
        .items(options)
        .title("Filter by component access")
        .placeholder(Some("Search Components.."));

    commands.spawn((
        props,
        AccessFilterPicker,
        crate::EditorEntity,
        crate::BlocksCameraInput,
    ));
}

/// Remove a component from the filter when its chip is clicked. A
/// selection-derived filter becomes manual on the first edit.
pub(crate) fn on_access_filter_chip_clicked(
    event: On<ButtonClickEvent>,
    chips: Query<&AccessFilterChip>,
    mut filter: ResMut<AccessFilter>,
) {
    let Ok(chip) = chips.get(event.entity) else {
        return;
    };
    filter.components.retain(|c| c != &chip.type_path);
    filter.source = FilterSource::Manual;
}

/// Clear the filter when the filter row's "Clear" button is clicked.
pub(crate) fn on_clear_filter_clicked(
    event: On<ButtonClickEvent>,
    buttons: Query<(), With<ClearFilterButton>>,
    mut filter: ResMut<AccessFilter>,
) {
    if buttons.get(event.entity).is_err() {
        return;
    }
    filter.components.clear();
    filter.source = FilterSource::Manual;
}

/// Resolve "From selection": prefer the BRP-live selected entity's cached
/// component names, falling back to the editor's local selection
/// (authoring / PIE preview entities). The archetype walk needs `&mut
/// World`, so the work runs as a queued command. A selection that yields no
/// components (nothing selected, or the entity left the cache) leaves the
/// filter untouched.
pub(crate) fn on_from_selection_clicked(
    event: On<ButtonClickEvent>,
    buttons: Query<(), With<FromSelectionButton>>,
    mut commands: Commands,
) {
    if buttons.get(event.entity).is_err() {
        return;
    }
    commands.queue(apply_selection_filter);
}

fn apply_selection_filter(world: &mut World) {
    let remote_bits = world.resource::<RemoteSelection>().selected;
    let remote = {
        let cache = world.resource::<RemoteSceneCache>();
        selection_components(remote_bits, &cache.entities)
    };
    let components = if remote.is_empty() {
        local_selection_components(world)
    } else {
        remote
    };
    if components.is_empty() {
        return;
    }
    let used = components.len();
    let mut filter = world.resource_mut::<AccessFilter>();
    filter.components = components;
    filter.source = FilterSource::Selection { used };
}

fn access_picker_spawn_item(
    In(SpawnItemInput { matched, entities }): In<SpawnItemInput>,
    mut commands: Commands,
) -> Result {
    commands.spawn((
        picker_item(matched.index),
        ChildOf(entities.list),
        children![match_text(matched.segments)],
    ));
    Ok(())
}

fn access_picker_select(
    input: In<SelectInput>,
    items: Query<&PickerItems<String>>,
    pickers: Query<&AccessFilterPicker>,
    mut filter: ResMut<AccessFilter>,
    mut commands: Commands,
) -> Result {
    let picker = input.entities.picker;
    let value = items.get(picker)?.at(input.index)?.clone();

    if pickers.get(picker).is_ok() {
        if !filter.components.contains(&value) {
            filter.components.push(value);
        }
        filter.source = FilterSource::Manual;
    }

    commands.entity(picker).try_despawn();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::super::schedules::SystemAccessEntry;
    use super::*;

    fn system(name: &str, accesses: &[(&str, &str)], exclusive: bool) -> SystemInfo {
        SystemInfo {
            name: name.to_string(),
            sets: Vec::new(),
            accesses: accesses
                .iter()
                .map(|&(component, kind)| SystemAccessEntry {
                    component: component.to_string(),
                    kind: kind.to_string(),
                })
                .collect(),
            exclusive,
        }
    }

    fn schedule(name: &str, systems: Vec<SystemInfo>) -> super::super::schedules::ScheduleInfo {
        super::super::schedules::ScheduleInfo {
            schedule: name.to_string(),
            systems,
            edges: Vec::new(),
            ambiguities: Vec::new(),
        }
    }

    fn transform() -> String {
        "bevy_transform::components::transform::Transform".to_string()
    }

    /// QA 交底 ①: the picker's candidates are the access-name union with the
    /// unbounded marker's empty component excluded and duplicates merged.
    #[test]
    fn access_options_exclude_empty_components_and_dedup() {
        let reply = SchedulesReply {
            schedules: vec![
                schedule(
                    "Update",
                    vec![
                        system(
                            "a",
                            &[(transform().as_str(), ACCESS_WRITE), ("", ACCESS_UNBOUNDED)],
                            false,
                        ),
                        system("b", &[(transform().as_str(), ACCESS_READ)], false),
                    ],
                ),
                schedule(
                    "Startup",
                    vec![system("c", &[("sky::Health", ACCESS_READ)], false)],
                ),
            ],
            access_reported: true,
        };
        let options = access_component_options(&reply);
        assert_eq!(
            options,
            vec![
                "bevy_transform::components::transform::Transform".to_string(),
                "sky::Health".to_string(),
            ],
            "unbounded's empty component must not become a picker candidate"
        );
    }

    /// QA 交底 ②: unbounded and exclusive systems hit for any filtered
    /// component — an exclusive system accesses everything.
    #[test]
    fn unbounded_and_exclusive_match_any_component() {
        let unbounded = system("sweep", &[("", ACCESS_UNBOUNDED)], false);
        let exclusive = system("save_world", &[], true);
        for component in [
            "sky::Health",
            "bevy_transform::components::transform::Transform",
        ] {
            assert!(access_matches(&unbounded, component));
            assert!(access_matches(&exclusive, component));
        }

        let filter = AccessFilter {
            components: vec!["sky::Health".to_string()],
            source: FilterSource::Manual,
        };
        assert!(matches_filter(&filter, &unbounded));
        assert!(matches_filter(&filter, &exclusive));
    }

    #[test]
    fn manual_filter_requires_every_component() {
        let both = system(
            "both",
            &[
                (transform().as_str(), ACCESS_WRITE),
                ("sky::Health", ACCESS_READ),
            ],
            false,
        );
        let only_one = system("only_one", &[(transform().as_str(), ACCESS_WRITE)], false);

        let mut filter = AccessFilter {
            components: vec![transform(), "sky::Health".to_string()],
            source: FilterSource::Manual,
        };
        assert!(matches_filter(&filter, &both));
        assert!(!matches_filter(&filter, &only_one));

        // An empty manual filter is no filtering: everything matches.
        filter.components.clear();
        assert!(matches_filter(&filter, &only_one));
    }

    #[test]
    fn selection_filter_matches_any_component() {
        let touches_health = system("h", &[("sky::Health", ACCESS_READ)], false);
        let touches_velocity = system("v", &[("sky::Velocity", ACCESS_WRITE)], false);
        let filter = AccessFilter {
            components: vec!["sky::Health".to_string(), "sky::Velocity".to_string()],
            source: FilterSource::Selection { used: 2 },
        };
        assert!(matches_filter(&filter, &touches_health));
        assert!(matches_filter(&filter, &touches_velocity));
        // OR via the standalone function, too.
        assert!(matches_any(
            &["sky::Velocity".to_string()],
            &touches_velocity
        ));
        assert!(!matches_any(
            &["sky::Velocity".to_string()],
            &touches_health
        ));
    }

    /// The access table names components via the `Components` registry while
    /// snapshot keys come from the reflect registry; both agree on full
    /// paths for built-in types, and the short-name fallback covers the
    /// rest.
    #[test]
    fn short_name_fallback_matches_across_namespaces() {
        let system = system("s", &[("sky::physics::Transform", ACCESS_WRITE)], false);
        assert!(access_matches(
            &system,
            "bevy_transform::components::transform::Transform"
        ));
        // A component that merely shares the short name of nothing present
        // does not match.
        assert!(!access_matches(&system, "bevy_ecs::name::Name"));
    }

    /// Regression anchor: with no filter active every node keeps the
    /// pre-feature default card color.
    #[test]
    fn node_color_defaults_without_filter() {
        assert_eq!(node_color(false, true), tokens::COMPONENT_CARD_BG);
        assert_eq!(node_color(false, false), tokens::COMPONENT_CARD_BG);
    }

    #[test]
    fn node_color_highlights_hits_and_dims_misses() {
        let hit = node_color(true, true);
        let miss = node_color(true, false);
        assert_eq!(hit, tokens::ACCENT_BLUE.with_alpha(0.28));
        assert_eq!(miss, tokens::COMPONENT_CARD_BG.with_alpha(0.35));
        assert_ne!(hit, miss);
    }

    #[test]
    fn access_badge_counts_reads_and_writes() {
        let s = system(
            "s",
            &[
                (transform().as_str(), ACCESS_WRITE),
                ("sky::Health", ACCESS_READ),
                ("sky::Mana", ACCESS_READ),
                ("sky::Tag", "archetypal"),
            ],
            false,
        );
        assert_eq!(access_badge(&s).as_deref(), Some("R2 W1"));
    }

    #[test]
    fn access_badge_marks_all_and_exclusive_and_none() {
        let unbounded = system("u", &[("", ACCESS_UNBOUNDED)], false);
        assert_eq!(access_badge(&unbounded).as_deref(), Some("ALL"));

        let exclusive = system("e", &[], true);
        assert_eq!(access_badge(&exclusive).as_deref(), Some("EXCL"));

        // No reported accesses at all (older replies, or presence-only
        // systems): no badge.
        let empty = system("n", &[], false);
        assert_eq!(access_badge(&empty), None);
        let archetypal = system("has", &[("sky::Tag", "archetypal")], false);
        assert_eq!(access_badge(&archetypal), None);
    }

    #[test]
    fn selection_components_sorted_from_cached_entity() {
        let mut components = std::collections::HashMap::new();
        components.insert("sky::Velocity".to_string(), serde_json::Value::Null);
        components.insert("bevy_ecs::name::Name".to_string(), serde_json::Value::Null);
        let entities = vec![
            RemoteEntity {
                entity: 7,
                components,
                scene_node_id: None,
            },
            RemoteEntity {
                entity: 9,
                components: Default::default(),
                scene_node_id: None,
            },
        ];
        let names = selection_components(Some(7), &entities);
        assert_eq!(
            names,
            vec![
                "bevy_ecs::name::Name".to_string(),
                "sky::Velocity".to_string()
            ]
        );
    }

    #[test]
    fn selection_components_empty_without_selection_or_entity() {
        assert!(selection_components(None, &[]).is_empty());
        let entities = vec![RemoteEntity {
            entity: 1,
            components: Default::default(),
            scene_node_id: None,
        }];
        // Selected entity not in the cache (despawned since last snapshot).
        assert!(selection_components(Some(2), &entities).is_empty());
    }
}
