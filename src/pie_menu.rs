//! Play-button run-config dropdown. The caret opens a list of every
//! launchable instance; clicking a row toggles launch/stop. When the
//! project has no `jackdaw.toml`, a single scaffold row is shown instead.
//! A per-frame system closes the popover on Escape or an outside click.

use bevy::picking::pointer::PointerButton;
use bevy::prelude::*;
use bevy::ui::ui_transform::UiGlobalTransform;
use jackdaw_feathers::button::{ButtonProps, ButtonVariant, button};
use jackdaw_feathers::icons::{EditorFont, Icon, IconFont};
use jackdaw_feathers::tokens;
use jackdaw_pie_protocol::manifest::RunConfig;

use crate::pie::{InstanceKey, PieSession, launch_instance, stop_instance};
use crate::run_config::{CargoMeta, RunConfigs, read_run_configs, scaffold_manifest};

const MENU_MIN_WIDTH: f32 = 220.0;
const CHECK_SLOT_WIDTH: f32 = 16.0;

pub struct PieMenuPlugin;

impl Plugin for PieMenuPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PieMenuState>()
            .add_observer(on_menu_button_click)
            .add_observer(on_instance_row_click)
            .add_observer(on_startup_row_click)
            .add_observer(on_scaffold_row_click)
            .add_systems(Update, close_menu_on_outside_click);
    }
}

/// Marker on the caret button that opens the run-config dropdown. Sits
/// in the Play/Pause pill right after the Play button.
#[derive(Component)]
pub struct PieMenuButton;

/// Marker on the open dropdown root.
#[derive(Component)]
pub struct PieMenuPopover;

/// Marker on one instance row, carrying the instance it launches or
/// stops when clicked.
#[derive(Component)]
pub struct PieInstanceRow(pub InstanceKey);

/// Marker on the fallback row shown when the project has no
/// `jackdaw.toml`; clicking it scaffolds one.
#[derive(Component)]
pub struct PieScaffoldRow;

/// Marker on the first row, which launches the game on its own startup
/// scene — the scene the game's own code loads, no editor override.
#[derive(Component)]
pub struct PieStartupRow;

#[derive(Resource, Default)]
pub struct PieMenuState {
    pub popover_entity: Option<Entity>,
}

fn on_menu_button_click(
    mut click: On<PointerClick>,
    buttons: Query<(Entity, &ComputedNode, &UiGlobalTransform), With<PieMenuButton>>,
    parents: Query<&ChildOf>,
    mut state: ResMut<PieMenuState>,
    mut commands: Commands,
) {
    if click.event().button != PointerButton::Primary {
        return;
    }
    let Some(button) = find_ancestor_with(click.event_target(), &parents, |e| buttons.contains(e))
    else {
        return;
    };
    click.propagate(false);

    if let Some(popover) = state.popover_entity.take() {
        if let Ok(mut ec) = commands.get_entity(popover) {
            ec.despawn();
        }
        return;
    }

    let Ok((_, computed, global_tf)) = buttons.get(button) else {
        return;
    };
    let (_, _, pos) = global_tf.to_scale_angle_translation();
    let size = computed.size() * computed.inverse_scale_factor();
    let right = pos.x + size.x / 2.0;
    let top = pos.y + size.y / 2.0 + 4.0;

    commands.queue(move |world: &mut World| {
        let popover = spawn_menu(world, right, top);
        world.resource_mut::<PieMenuState>().popover_entity = Some(popover);
    });
}

/// Row data snapshotted before spawning so `spawn_menu` can take `&mut World`
/// without keeping the session and config borrows alive.
struct RowSpec {
    key: InstanceKey,
    label: String,
    /// The dim cargo-target suffix (`bin:server`), when the run launches
    /// something other than the default game binary.
    badge: Option<String>,
    running: bool,
}

fn spawn_menu(world: &mut World, right_x: f32, top_y: f32) -> Entity {
    let editor_font = world.get_resource::<EditorFont>().map(|f| f.0.clone());
    let icon_font = world.get_resource::<IconFont>().map(|f| f.0.clone());

    let rows = collect_rows(world);

    let popover = world
        .spawn((
            PieMenuPopover,
            Node {
                position_type: PositionType::Absolute,
                top: Val::Px(top_y),
                left: Val::Px(right_x - MENU_MIN_WIDTH),
                min_width: Val::Px(MENU_MIN_WIDTH),
                flex_direction: FlexDirection::Column,
                padding: UiRect::all(Val::Px(tokens::SPACING_XS)),
                border: UiRect::all(Val::Px(1.0)),
                border_radius: BorderRadius::all(Val::Px(tokens::BORDER_RADIUS_MD)),
                row_gap: Val::Px(2.0),
                ..Default::default()
            },
            BackgroundColor(tokens::MENU_BG),
            BorderColor::all(tokens::BORDER_SUBTLE),
            ZIndex(1000),
        ))
        .id();

    // First group: the game's own startup scene (the pre-current-scene
    // meaning of Play), separated from the per-instance rows below.
    spawn_startup_row(world, popover, editor_font.clone());
    spawn_menu_divider(world, popover);

    if rows.is_empty() {
        spawn_scaffold_row(world, popover, editor_font, icon_font);
    } else {
        for row in rows {
            spawn_instance_row(world, popover, row, editor_font.clone());
        }
    }

    popover
}

/// The first group of the dropdown: the game's own startup scene, which is
/// what the main Play button launched before "play the current scene"
/// existed. Kept as an explicit row so the old path stays one click away,
/// above the per-instance rows it always led to.
fn spawn_startup_row(world: &mut World, popover: Entity, editor_font: Option<Handle<Font>>) {
    let row = world
        .spawn((
            PieStartupRow,
            button(
                ButtonProps::new("")
                    .with_variant(ButtonVariant::Ghost)
                    .align_left(),
            ),
            ChildOf(popover),
        ))
        .id();

    if let Some(handle) = editor_font.clone() {
        world.spawn((
            Text::new(String::from(Icon::Play.unicode())),
            TextFont {
                font: handle.into(),
                font_size: tokens::TEXT_SIZE,
                ..Default::default()
            },
            TextColor(tokens::DOC_TAB_INACTIVE_LABEL),
            Pickable::IGNORE,
            ChildOf(row),
        ));
    }

    let mut label_font = TextFont {
        font_size: tokens::TEXT_SIZE_SM,
        ..Default::default()
    };
    if let Some(handle) = editor_font {
        label_font.font = handle.into();
    }
    world.spawn((
        Text::new("Play Startup Scene".to_string()),
        label_font,
        TextColor(tokens::DOC_TAB_INACTIVE_LABEL),
        Pickable::IGNORE,
        ChildOf(row),
    ));
}

/// The hairline between the startup-scene group and the instance rows.
fn spawn_menu_divider(world: &mut World, popover: Entity) {
    world.spawn((
        Node {
            height: Val::Px(1.0),
            margin: UiRect::axes(Val::Px(4.0), Val::Px(2.0)),
            ..Default::default()
        },
        BackgroundColor(tokens::BORDER_SUBTLE),
        Pickable::IGNORE,
        ChildOf(popover),
    ));
}

/// Collect one `RowSpec` per launchable instance. Single-instance configs
/// drop the `#1` suffix in the label; the key always carries the index.
fn collect_rows(world: &mut World) -> Vec<RowSpec> {
    let runs = world.resource::<RunConfigs>().manifest.runs.clone();
    let session = world.non_send::<PieSession>();

    let mut rows = Vec::new();
    for run in &runs {
        let label = run.label().to_string();
        let badge = target_badge(run);
        for instance in 1..=run.instances {
            let key = InstanceKey {
                config: label.clone(),
                instance,
            };
            let display = if run.instances == 1 {
                label.clone()
            } else {
                key.to_string()
            };
            let running = session.is_running(&key);
            rows.push(RowSpec {
                key,
                label: display,
                badge: badge.clone(),
                running,
            });
        }
    }
    rows
}

/// The suffix marking which cargo target a row launches, so same-named
/// runs with different targets tell apart at a glance: `bin:server`,
/// `example:split_screen`. A run without a target — the default game
/// binary — carries none. The kind and name come from the build
/// pipeline's own reading of the target, so the badge can never name
/// another target than the one the launch builds.
fn target_badge(run: &RunConfig) -> Option<String> {
    let target = crate::run_config::cargo_target(run)?;
    let (kind, name) = target.named()?;
    Some(format!("{kind}:{name}"))
}

fn spawn_instance_row(
    world: &mut World,
    popover: Entity,
    spec: RowSpec,
    editor_font: Option<Handle<Font>>,
) {
    let label_color = if spec.running {
        tokens::DOC_TAB_ACTIVE_LABEL
    } else {
        tokens::DOC_TAB_INACTIVE_LABEL
    };

    let row = world
        .spawn((
            PieInstanceRow(spec.key),
            button(
                ButtonProps::new("")
                    .with_variant(ButtonVariant::Ghost)
                    .align_left(),
            ),
            ChildOf(popover),
        ))
        .id();

    spawn_check_slot(world, row, spec.running);

    let mut label_font = TextFont {
        font_size: tokens::TEXT_SIZE_SM,
        ..Default::default()
    };
    if let Some(handle) = editor_font.as_ref() {
        label_font.font = handle.clone().into();
    }
    world.spawn((
        Text::new(spec.label),
        label_font,
        TextColor(label_color),
        Pickable::IGNORE,
        ChildOf(row),
    ));

    if let Some(badge) = spec.badge {
        let mut badge_font = TextFont {
            font_size: tokens::TEXT_SIZE_XS,
            ..Default::default()
        };
        if let Some(handle) = editor_font.as_ref() {
            badge_font.font = handle.clone().into();
        }
        world.spawn((
            Text::new(badge),
            badge_font,
            TextColor(tokens::TEXT_MUTED_COLOR.into()),
            Pickable::IGNORE,
            ChildOf(row),
        ));
    }
}

/// Fixed-width slot holding the row's checkbox, so labels stay aligned
/// across rows whether or not the run is up.
fn spawn_check_slot(world: &mut World, row: Entity, running: bool) {
    let slot = world
        .spawn((
            Node {
                width: Val::Px(CHECK_SLOT_WIDTH),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..Default::default()
            },
            Pickable::IGNORE,
            ChildOf(row),
        ))
        .id();

    jackdaw_feathers::button::spawn_inert_checkbox(world, slot, running);
}

fn spawn_scaffold_row(
    world: &mut World,
    popover: Entity,
    editor_font: Option<Handle<Font>>,
    icon_font: Option<Handle<Font>>,
) {
    let row = world
        .spawn((
            PieScaffoldRow,
            button(
                ButtonProps::new("")
                    .with_variant(ButtonVariant::Ghost)
                    .align_left(),
            ),
            ChildOf(popover),
        ))
        .id();

    if let Some(handle) = icon_font {
        world.spawn((
            Text::new(String::from(Icon::FilePlus.unicode())),
            TextFont {
                font: handle.into(),
                font_size: tokens::TEXT_SIZE,
                ..Default::default()
            },
            TextColor(tokens::DOC_TAB_INACTIVE_LABEL),
            Pickable::IGNORE,
            ChildOf(row),
        ));
    }

    let mut label_font = TextFont {
        font_size: tokens::TEXT_SIZE_SM,
        ..Default::default()
    };
    if let Some(handle) = editor_font {
        label_font.font = handle.into();
    }
    world.spawn((
        Text::new("Generate jackdaw.toml".to_string()),
        label_font,
        TextColor(tokens::DOC_TAB_INACTIVE_LABEL),
        Pickable::IGNORE,
        ChildOf(row),
    ));
}

fn on_instance_row_click(
    mut click: On<PointerClick>,
    rows: Query<&PieInstanceRow>,
    parents: Query<&ChildOf>,
    mut commands: Commands,
) -> Result {
    if click.event().button != PointerButton::Primary {
        return Ok(());
    }
    let Some(row) = find_ancestor_with(click.event_target(), &parents, |e| rows.contains(e)) else {
        return Ok(());
    };
    click.propagate(false);

    let key = rows.get(row)?.0.clone();
    commands.queue(move |world: &mut World| {
        if world.non_send::<PieSession>().is_running(&key) {
            stop_instance(world, &key);
        } else if let Some(run) = world
            .resource::<RunConfigs>()
            .manifest
            .run_by_name(&key.config)
            .cloned()
        {
            launch_instance(world, key.clone(), run);
        }
        close_menu(world);
    });
    Ok(())
}

fn on_startup_row_click(
    mut click: On<PointerClick>,
    rows: Query<(), With<PieStartupRow>>,
    parents: Query<&ChildOf>,
    mut commands: Commands,
) {
    if click.event().button != PointerButton::Primary {
        return;
    }
    if find_ancestor_with(click.event_target(), &parents, |e| rows.contains(e)).is_none() {
        return;
    }
    click.propagate(false);

    // The game's own startup scene: the same first-run launch the main
    // Play button used before "play the current scene" existed, with no
    // scene override in the child's environment.
    commands.queue(|world: &mut World| {
        crate::pie::handle_play(world);
        close_menu(world);
    });
}

fn on_scaffold_row_click(
    mut click: On<PointerClick>,
    rows: Query<&PieScaffoldRow>,
    parents: Query<&ChildOf>,
    mut commands: Commands,
) {
    if click.event().button != PointerButton::Primary {
        return;
    }
    if find_ancestor_with(click.event_target(), &parents, |e| rows.contains(e)).is_none() {
        return;
    }
    click.propagate(false);

    commands.queue(|world: &mut World| {
        write_scaffold(world);
        read_run_configs(world);
        close_menu(world);
    });
}

/// Write a starter `jackdaw.toml` to the open project's root. Logs and
/// bails on a missing project or an io error rather than failing the
/// frame. Never overwrites: an existing file holds the user's plugin,
/// package, pins, and run configurations.
fn write_scaffold(world: &World) {
    let Some(root) = world
        .get_resource::<crate::project::ProjectRoot>()
        .map(|p| p.root.clone())
    else {
        warn!("PIE: scaffold requested but no project is open");
        return;
    };
    let path = root.join("jackdaw.toml");
    if path.is_file() {
        warn!("PIE: {} already exists; leaving it alone", path.display());
        return;
    }
    let Some(meta) = CargoMeta::load(&root) else {
        warn!("PIE: cargo metadata failed for {}", root.display());
        return;
    };
    let body = scaffold_manifest(&meta);
    if let Err(err) = std::fs::write(&path, body) {
        warn!("PIE: failed to write {}: {err}", path.display());
    }
}

fn close_menu(world: &mut World) {
    if let Some(popover) = world.resource_mut::<PieMenuState>().popover_entity.take() {
        world.despawn(popover);
    }
}

fn close_menu_on_outside_click(
    mouse: Res<ButtonInput<MouseButton>>,
    keyboard: Res<ButtonInput<KeyCode>>,
    mut state: ResMut<PieMenuState>,
    popovers: Query<&ComputedNode, With<PieMenuPopover>>,
    popover_transforms: Query<&UiGlobalTransform, With<PieMenuPopover>>,
    windows: Query<&Window>,
    focus: crate::keybind_focus::KeybindFocus,
    mut commands: Commands,
) {
    let Some(popover_entity) = state.popover_entity else {
        return;
    };
    if focus.keyboard_is_spoken_for() {
        return;
    }
    if !mouse.just_pressed(MouseButton::Left) && !keyboard.just_pressed(KeyCode::Escape) {
        return;
    }
    if keyboard.just_pressed(KeyCode::Escape) {
        if let Ok(mut ec) = commands.get_entity(popover_entity) {
            ec.despawn();
        }
        state.popover_entity = None;
        return;
    }

    let cursor = windows
        .single()
        .ok()
        .and_then(bevy::prelude::Window::cursor_position);
    if let (Some(cursor), Ok(computed), Ok(global_tf)) = (
        cursor,
        popovers.get(popover_entity),
        popover_transforms.get(popover_entity),
    ) {
        let (_, _, pos) = global_tf.to_scale_angle_translation();
        let size = computed.size() * computed.inverse_scale_factor();
        let min = pos - size * 0.5;
        let max = pos + size * 0.5;
        if cursor.x >= min.x && cursor.x <= max.x && cursor.y >= min.y && cursor.y <= max.y {
            return;
        }
    }

    if let Ok(mut ec) = commands.get_entity(popover_entity) {
        ec.despawn();
    }
    state.popover_entity = None;
}

fn find_ancestor_with<F>(start: Entity, parents: &Query<&ChildOf>, predicate: F) -> Option<Entity>
where
    F: Fn(Entity) -> bool,
{
    let mut entity = start;
    for _ in 0..8 {
        if predicate(entity) {
            return Some(entity);
        }
        if let Ok(co) = parents.get(entity) {
            entity = co.parent();
        } else {
            return None;
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::feathers::controls::FeathersCheckbox;
    use bevy::ui::Checked;

    fn check_slot_app() -> App {
        let mut app = App::new();
        app.add_plugins((
            bevy::app::TaskPoolPlugin::default(),
            bevy::asset::AssetPlugin::default(),
            bevy::scene::ScenePlugin,
        ))
        .init_asset::<Image>()
        .init_asset::<Font>();
        app
    }

    fn spawn_slot(app: &mut App, running: bool) {
        let row = app.world_mut().spawn(Node::default()).id();
        spawn_check_slot(app.world_mut(), row, running);
    }

    /// A run's row is marked with the native checkbox, checked while the run
    /// is up and clear while it is not.
    #[test]
    fn a_running_instance_is_marked_with_a_checked_feathers_checkbox() {
        let mut app = check_slot_app();
        spawn_slot(&mut app, true);

        let mut boxes = app
            .world_mut()
            .query_filtered::<Entity, With<FeathersCheckbox>>();
        let checkbox = boxes
            .iter(app.world())
            .next()
            .expect("the slot holds a feathers checkbox");
        assert!(
            app.world().get::<Checked>(checkbox).is_some(),
            "a running instance reads as checked",
        );
    }

    #[test]
    fn a_stopped_instance_leaves_the_box_clear() {
        let mut app = check_slot_app();
        spawn_slot(&mut app, false);

        let mut boxes = app
            .world_mut()
            .query_filtered::<Entity, With<FeathersCheckbox>>();
        let checkbox = boxes
            .iter(app.world())
            .next()
            .expect("the slot holds a feathers checkbox");
        assert!(
            app.world().get::<Checked>(checkbox).is_none(),
            "a stopped instance reads as unchecked",
        );
    }

    fn row_spec(label: &str, badge: Option<String>) -> RowSpec {
        RowSpec {
            key: InstanceKey {
                config: label.to_string(),
                instance: 1,
            },
            label: label.to_string(),
            badge,
            running: false,
        }
    }

    /// The texts `spawn_instance_row` put under its row, which itself
    /// hangs under `popover`: `(text, font size, color)` per text.
    fn spawned_row_texts(
        app: &mut App,
        popover: Entity,
    ) -> Vec<(String, bevy::text::FontSize, Color)> {
        // Collect first: the row lookup needs the world again, and the
        // query iterator holds its borrow.
        let candidates: Vec<Entity> = {
            let mut rows = app
                .world_mut()
                .query_filtered::<Entity, With<PieInstanceRow>>();
            rows.iter(app.world()).collect()
        };
        let row = candidates
            .into_iter()
            .find(|row| {
                app.world()
                    .get::<ChildOf>(*row)
                    .is_some_and(|child_of| child_of.parent() == popover)
            })
            .expect("the row hangs under the popover");
        let mut texts = app
            .world_mut()
            .query::<(&Text, &TextFont, &TextColor, &ChildOf)>();
        texts
            .iter(app.world())
            .filter(|(_, _, _, child_of)| child_of.parent() == row)
            .map(|(text, font, color, _)| (text.0.clone(), font.font_size, color.0))
            .collect()
    }

    /// A targeted row's badge rides along after the label, in the muted
    /// color and the smaller size every other dim annotation uses.
    #[test]
    fn a_targeted_row_carries_a_dim_badge_after_its_label() {
        let mut app = check_slot_app();
        let popover = app.world_mut().spawn(Node::default()).id();
        spawn_instance_row(
            app.world_mut(),
            popover,
            row_spec("Server", Some("bin:server".to_string())),
            None,
        );

        let texts = spawned_row_texts(&mut app, popover);
        let texts: std::collections::HashMap<String, (bevy::text::FontSize, Color)> = texts
            .into_iter()
            .map(|(text, size, color)| (text, (size, color)))
            .collect();
        let (size, color) = texts
            .get("bin:server")
            .expect("the badge renders after the label");
        assert_eq!(*size, tokens::TEXT_SIZE_XS, "the badge is the small size");
        assert_eq!(
            *color,
            Color::Srgba(tokens::TEXT_MUTED_COLOR),
            "the badge is the muted annotation color"
        );
        assert!(texts.contains_key("Server"), "the label still renders");
    }

    #[test]
    fn a_row_without_a_target_renders_no_badge() {
        let mut app = check_slot_app();
        let popover = app.world_mut().spawn(Node::default()).id();
        spawn_instance_row(app.world_mut(), popover, row_spec("Play", None), None);

        let texts = spawned_row_texts(&mut app, popover);
        let labels: Vec<String> = texts.into_iter().map(|(text, _, _)| text).collect();
        assert_eq!(labels, ["Play".to_string()], "the label alone");
    }

    fn run_from(toml_text: &str) -> RunConfig {
        let manifest: jackdaw_pie_protocol::manifest::Manifest = toml::from_str(toml_text).unwrap();
        manifest.runs.into_iter().next().unwrap()
    }

    #[test]
    fn the_badge_names_the_cargo_target_kind() {
        assert_eq!(
            target_badge(&run_from("[[run]]\ntarget = { bin = \"server\" }")),
            Some("bin:server".to_string())
        );
        assert_eq!(
            target_badge(&run_from(
                "[[run]]\ntarget = { example = \"split_screen\" }"
            )),
            Some("example:split_screen".to_string())
        );
        assert_eq!(target_badge(&run_from("[[run]]\nname = \"Play\"")), None);
    }
}
