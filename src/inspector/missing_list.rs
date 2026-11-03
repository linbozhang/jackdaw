//! The scene-problems list: what the audit found about references, one row
//! per broken one, each a rebind away from whole — and, beside it, the
//! binding problems the last load recorded, one row per wrong field or type
//! spelling, with the entity a Locate away.
//!
//! A reference row names the document, the entity, the component and field
//! holding the reference, and the reference as spelled. Its buttons rebind
//! through the picker (writing the reference into the open tab's own
//! document, so the change is an edit like any other — the tab turns dirty,
//! nothing reaches a file until its own save), open the document's folder in
//! the desktop's file manager, copy the reference, or bring the document
//! forward with the entity selected. A document with no tab of its own is
//! not rewritten from here — the row's rebind answers with the advice to
//! open it first (the first-version boundary the plan set). A binding row
//! names the entity, the component, and the field when there is one; its
//! buttons select the entity and copy the spelling (no Rebind: a type or
//! field spelling is not rewritten through a file picker).

use std::path::Path;

use bevy::picking::events::PointerClick;
use bevy::prelude::*;
use jackdaw_feathers::icons::EditorFont;
use jackdaw_feathers::picker::{
    PickerItems, PickerProps, SelectInput, SpawnItemInput, match_text, picker_item,
};
use jackdaw_feathers::tokens;
use path_slash::PathExt as _;

use crate::reference_audit::{AuditFinding, FindingKind};

/// Marker on the list's scrim node.
#[derive(Component)]
pub struct MissingListRoot;

/// What one row's button does. The row carries its finding, so the observer
/// never walks the node tree.
#[derive(Component, Clone)]
pub struct MissingButton {
    pub action: MissingAction,
    pub finding: AuditFinding,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum MissingAction {
    Rebind,
    Show,
    Copy,
    Locate,
}

/// What one binding row's button does. A binding problem has no reference to
/// rebind or file to show — the row's moves are selecting its entity and
/// copying the spelling that needs rewriting.
#[derive(Component, Clone)]
pub struct BindingButton {
    pub action: BindingAction,
    pub issue: jackdaw_bsn::BindingIssue,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum BindingAction {
    Locate,
    Copy,
}

/// The picker a row's Rebind opened, so its choice reaches the row that
/// asked.
#[derive(Component)]
pub struct MissingPicker(pub AuditFinding);

/// The one button that closes the list.
#[derive(Component)]
struct CloseListButton;

pub(crate) fn plugin(app: &mut App) {
    // The row buttons observe their own clicks where they are spawned; the
    // rebind picker's select system registers through its PickerProps.
    app.add_observer(on_missing_button_click)
        .add_observer(on_binding_button_click)
        .add_observer(on_load_failure_button_click)
        .add_observer(on_close_list_click);
}

/// Bring the audit's findings up as the list: nothing to show says so in the
/// status bar, anything to show gets the dialog. The findings are gathered
/// fresh, so the list never disagrees with the project; the binding rows ride
/// beside them (the last load's structured record), making the panel the
/// scene-problems list decision 4(a) named — two sections, one board.
pub fn open_missing_list(world: &mut World) {
    let findings = crate::reference_audit::audit_references(world);
    world.insert_resource(crate::reference_audit::AuditFindings(findings.clone()));
    let bindings: Vec<jackdaw_bsn::BindingIssue> = world
        .get_resource::<jackdaw_bsn::BindingIssues>()
        .map(|issues| issues.rows().to_vec())
        .unwrap_or_default();
    let failures: Vec<crate::asset_failures::LoadFailureRow> = world
        .get_resource::<crate::asset_failures::WarnedFailures>()
        .map(|warned| warned.rows().to_vec())
        .unwrap_or_default();
    if findings.is_empty() && bindings.is_empty() && failures.is_empty() {
        crate::status_bar::notify_info(world, "no broken references");
        return;
    }
    spawn_missing_list(world, &findings, &bindings, &failures);
}

/// How many rows one section renders before "... and N more" — the dialog
/// stays a dialog, the session keeps the rest.
const MAX_ROWS_PER_SECTION: usize = 12;

fn spawn_missing_list(
    world: &mut World,
    findings: &[AuditFinding],
    bindings: &[jackdaw_bsn::BindingIssue],
    failures: &[crate::asset_failures::LoadFailureRow],
) {
    let Some(editor_font) = world.get_resource::<EditorFont>().map(|f| f.0.clone()) else {
        // Headless: the findings resource is what tests and tooling assert
        // against, the UI never spawns.
        return;
    };
    despawn_missing_list(world);
    let scrim = world
        .spawn((
            MissingListRoot,
            Node {
                position_type: PositionType::Absolute,
                left: Val::Px(0.0),
                top: Val::Px(0.0),
                width: Val::Percent(100.0),
                height: Val::Percent(100.0),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Center,
                ..Default::default()
            },
            BackgroundColor(Color::srgba(0.0, 0.0, 0.0, 0.55)),
            GlobalZIndex(100),
        ))
        .id();
    let card = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                row_gap: Val::Px(6.0),
                padding: UiRect::all(Val::Px(20.0)),
                min_width: Val::Px(560.0),
                max_width: Val::Px(820.0),
                border: UiRect::all(Val::Px(1.0)),
                border_radius: BorderRadius::all(Val::Px(tokens::BORDER_RADIUS_MD)),
                ..Default::default()
            },
            BackgroundColor(tokens::PANEL_BG),
            BorderColor::all(tokens::BORDER_SUBTLE),
            ChildOf(scrim),
        ))
        .id();
    world.spawn((
        Text::new("Scene Problems"),
        TextFont {
            font: editor_font.clone().into(),
            font_size: tokens::TEXT_SIZE_LG,
            ..Default::default()
        },
        TextColor(tokens::TEXT_PRIMARY),
        ChildOf(card),
    ));
    let summary = match (findings.len(), bindings.len(), failures.len()) {
        (0, 0, n) => format!(
            "no broken references; {n} load failure{} on the board",
            plural_s(n)
        ),
        (_f, b, l) => format!(
            "{}; {b} binding problem{}, {l} load failure{}",
            crate::reference_audit::summarize(findings),
            plural_s(b),
            plural_s(l),
        ),
    };
    world.spawn((
        Text::new(summary),
        TextFont {
            font: editor_font.clone().into(),
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        ChildOf(card),
    ));
    if !findings.is_empty() {
        spawn_section_header(world, card, editor_font.clone(), "Broken references");
        for finding in findings {
            spawn_finding_row(world, card, editor_font.clone(), finding);
        }
    }
    if !bindings.is_empty() {
        spawn_section_header(world, card, editor_font.clone(), "Binding problems");
        for issue in bindings.iter().take(MAX_ROWS_PER_SECTION) {
            spawn_binding_row(world, card, editor_font.clone(), issue);
        }
    }
    if !failures.is_empty() {
        spawn_section_header(world, card, editor_font.clone(), "Asset load failures");
        for row in failures.iter().take(MAX_ROWS_PER_SECTION) {
            spawn_load_failure_row(world, card, editor_font.clone(), row);
        }
    }
    let close = spawn_text_button(
        world,
        card,
        editor_font,
        "Close",
        CloseListButton,
        tokens::TOOLBAR_BG,
    );
    world.entity_mut(close).observe(on_close_list_click);
}

fn plural_s(n: usize) -> &'static str {
    if n == 1 { "" } else { "s" }
}

/// A section title between the summary and its rows.
fn spawn_section_header(world: &mut World, parent: Entity, font: Handle<Font>, title: &str) {
    world.spawn((
        Text::new(title.to_string()),
        TextFont {
            font: font.into(),
            font_size: tokens::TEXT_SIZE,
            ..Default::default()
        },
        TextColor(tokens::TEXT_PRIMARY),
        ChildOf(parent),
    ));
}

/// One binding row: the four-tuple face the audit rows spell, in the error
/// color, with the moves a binding problem has — select its entity, copy the
/// spelling that needs rewriting. No Rebind: a type or field spelling is not
/// rewritten through the picker.
fn spawn_binding_row(
    world: &mut World,
    parent: Entity,
    font: Handle<Font>,
    issue: &jackdaw_bsn::BindingIssue,
) {
    let row = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Row,
                align_items: AlignItems::Center,
                column_gap: Val::Px(8.0),
                ..Default::default()
            },
            ChildOf(parent),
        ))
        .id();
    world.spawn((
        Text::new(issue.line()),
        TextFont {
            font: font.clone().into(),
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(tokens::TEXT_ERROR),
        Node {
            flex_grow: 1.0,
            min_width: Val::Px(0.0),
            overflow: Overflow::clip(),
            ..Default::default()
        },
        ChildOf(row),
    ));
    if issue.entity.is_some() {
        let button = spawn_text_button(
            world,
            row,
            font.clone(),
            "Locate",
            BindingButton {
                action: BindingAction::Locate,
                issue: issue.clone(),
            },
            tokens::TOOLBAR_BG,
        );
        world.entity_mut(button).observe(on_binding_button_click);
    }
    let button = spawn_text_button(
        world,
        row,
        font,
        "Copy",
        BindingButton {
            action: BindingAction::Copy,
            issue: issue.clone(),
        },
        tokens::TOOLBAR_BG,
    );
    world.entity_mut(button).observe(on_binding_button_click);
}

/// What one load-failure row's button does: reveal the file's folder, or
/// copy the path (the moves a broken file has).
#[derive(Component, Clone)]
pub struct LoadFailureButton {
    pub action: LoadFailureAction,
    pub row: crate::asset_failures::LoadFailureRow,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum LoadFailureAction {
    Show,
    Copy,
}

/// The load-failure row's button, answered.
fn on_load_failure_button_click(
    trigger: On<PointerClick>,
    buttons: Query<&LoadFailureButton>,
    mut commands: Commands,
) {
    let Ok(button) = buttons.get(trigger.event_target()) else {
        return;
    };
    let button = button.clone();
    commands.queue(move |world: &mut World| match button.action {
        LoadFailureAction::Show => show_load_failure(world, &button.row),
        LoadFailureAction::Copy => copy_load_failure(world, &button.row),
    });
}

/// The folder holding the failed file, in the desktop's file manager.
fn show_load_failure(world: &mut World, row: &crate::asset_failures::LoadFailureRow) {
    let folder = row
        .file
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| row.file.clone());
    if let Err(err) = crate::project_window::open_with_desktop(&folder) {
        crate::status_bar::notify_warn(
            world,
            format!("{} cannot be opened: {err}", folder.display()),
        );
    }
}

/// The failed file's path, on the clipboard.
fn copy_load_failure(world: &mut World, row: &crate::asset_failures::LoadFailureRow) {
    if let Some(mut clipboard) = world.get_resource_mut::<Clipboard>() {
        let spelled = row.file.to_string_lossy().into_owned();
        let _ = clipboard.set_text(spelled.clone());
        crate::status_bar::notify_info(world, format!("copied {spelled}"));
    }
}

/// One load-failure row: the file the engine could not read and why, with
/// Show (its folder) and Copy (its path).
fn spawn_load_failure_row(
    world: &mut World,
    parent: Entity,
    font: Handle<Font>,
    row: &crate::asset_failures::LoadFailureRow,
) {
    let holder = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Row,
                align_items: AlignItems::Center,
                column_gap: Val::Px(8.0),
                ..Default::default()
            },
            ChildOf(parent),
        ))
        .id();
    world.spawn((
        Text::new(format!(
            "{} failed to load ({})",
            row.file.display(),
            row.error
        )),
        TextFont {
            font: font.clone().into(),
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(tokens::TEXT_WARNING),
        Node {
            flex_grow: 1.0,
            min_width: Val::Px(0.0),
            overflow: Overflow::clip(),
            ..Default::default()
        },
        ChildOf(holder),
    ));
    for (label, action) in [
        ("Show", LoadFailureAction::Show),
        ("Copy", LoadFailureAction::Copy),
    ] {
        let button = spawn_text_button(
            world,
            holder,
            font.clone(),
            label,
            LoadFailureButton {
                action,
                row: row.clone(),
            },
            tokens::TOOLBAR_BG,
        );
        world
            .entity_mut(button)
            .observe(on_load_failure_button_click);
    }
}

/// The binding row's button, answered.
fn on_binding_button_click(
    trigger: On<PointerClick>,
    buttons: Query<&BindingButton>,
    mut commands: Commands,
) {
    let Ok(button) = buttons.get(trigger.event_target()) else {
        return;
    };
    let button = button.clone();
    commands.queue(move |world: &mut World| match button.action {
        BindingAction::Locate => locate_binding(world, &button.issue),
        BindingAction::Copy => copy_binding(world, &button.issue),
    });
}

/// Select the entity a binding row names, the way a reference row's Locate
/// selects the holder of a broken reference.
fn locate_binding(world: &mut World, issue: &jackdaw_bsn::BindingIssue) {
    let Some(named) = issue.entity.as_deref() else {
        return;
    };
    let mut named_query = world.query_filtered::<Entity, With<Name>>();
    let hit = named_query.iter(world).find(|entity| {
        world
            .get::<Name>(*entity)
            .is_some_and(|name| name.as_str() == named)
    });
    match hit {
        Some(entity) => {
            crate::selection::select_only(world, entity);
            crate::status_bar::notify_info(world, format!("selected {named}"));
        }
        None => {
            crate::status_bar::notify_warn(world, format!("{named} is not in the open scene"));
        }
    }
}

/// The binding row's component and field, on the clipboard — the spelling a
/// document author needs to search for.
fn copy_binding(world: &mut World, issue: &jackdaw_bsn::BindingIssue) {
    let spelled = match &issue.field {
        Some(field) => format!("{}.{}", issue.component, field),
        None => issue.component.clone(),
    };
    if let Some(mut clipboard) = world.get_resource_mut::<Clipboard>() {
        let _ = clipboard.set_text(spelled.clone());
        crate::status_bar::notify_info(world, format!("copied {spelled}"));
    }
}

fn spawn_finding_row(
    world: &mut World,
    parent: Entity,
    font: Handle<Font>,
    finding: &AuditFinding,
) {
    let row = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Row,
                align_items: AlignItems::Center,
                column_gap: Val::Px(8.0),
                ..Default::default()
            },
            ChildOf(parent),
        ))
        .id();
    world.spawn((
        Text::new(finding.line()),
        TextFont {
            font: font.clone().into(),
            font_size: tokens::TEXT_SIZE_SM,
            ..Default::default()
        },
        TextColor(color_of(finding.kind)),
        Node {
            flex_grow: 1.0,
            min_width: Val::Px(0.0),
            overflow: Overflow::clip(),
            ..Default::default()
        },
        ChildOf(row),
    ));
    for (label, action) in [
        ("Rebind", MissingAction::Rebind),
        ("Locate", MissingAction::Locate),
        ("Show", MissingAction::Show),
        ("Copy", MissingAction::Copy),
    ] {
        let button = spawn_text_button(
            world,
            row,
            font.clone(),
            label,
            MissingButton {
                action,
                finding: finding.clone(),
            },
            tokens::TOOLBAR_BG,
        );
        world.entity_mut(button).observe(on_missing_button_click);
    }
}

fn color_of(kind: FindingKind) -> Color {
    match kind {
        FindingKind::Missing => tokens::TEXT_ERROR,
        FindingKind::Ambiguous => Color::srgb(0.9, 0.7, 0.2),
        FindingKind::MachinePath => tokens::TEXT_SECONDARY,
    }
}

/// A plain button whose marker says what it does, answering with the entity
/// the caller hangs its observer on. Padded generously: the list's rows are
/// dense and the buttons small, and both a person and an automated click
/// have an easier time landing on a roomy one.
fn spawn_text_button<M: Component>(
    world: &mut World,
    parent: Entity,
    font: Handle<Font>,
    label: &str,
    marker: M,
    bg: Color,
) -> Entity {
    let node = world
        .spawn((
            marker,
            Node {
                padding: UiRect::axes(Val::Px(16.0), Val::Px(8.0)),
                border_radius: BorderRadius::all(Val::Px(tokens::BORDER_RADIUS_MD)),
                ..Default::default()
            },
            BackgroundColor(bg),
            ChildOf(parent),
        ))
        .id();
    world.spawn((
        Text::new(label.to_string()),
        TextFont {
            font: font.into(),
            font_size: tokens::TEXT_SIZE,
            ..Default::default()
        },
        TextColor(tokens::TEXT_PRIMARY),
        Pickable::IGNORE,
        ChildOf(node),
    ));
    node
}

pub fn on_missing_button_click(
    trigger: On<PointerClick>,
    buttons: Query<&MissingButton>,
    mut commands: Commands,
) {
    let Ok(button) = buttons.get(trigger.event_target()) else {
        return;
    };
    let button = button.clone();
    commands.queue(move |world: &mut World| match button.action {
        MissingAction::Rebind => open_rebind_picker(world, &button.finding),
        MissingAction::Show => show_in_file_manager(world, &button.finding),
        MissingAction::Copy => copy_reference(world, &button.finding),
        MissingAction::Locate => locate(world, &button.finding),
    });
}

fn on_close_list_click(
    trigger: On<PointerClick>,
    closers: Query<&CloseListButton>,
    mut commands: Commands,
) {
    if closers.get(trigger.event_target()).is_err() {
        return;
    }
    commands.queue(|world: &mut World| despawn_missing_list(world));
}

fn despawn_missing_list(world: &mut World) {
    let roots: Vec<Entity> = world
        .query_filtered::<Entity, With<MissingListRoot>>()
        .iter(world)
        .collect();
    for root in roots {
        if let Ok(ec) = world.get_entity_mut(root) {
            ec.despawn();
        }
    }
}

/// Put up the picker of files the project holds, for the row's reference to
/// be rebound to. A document no tab holds is not written from here.
fn open_rebind_picker(world: &mut World, finding: &AuditFinding) {
    if tab_holding(world, finding).is_none() {
        crate::status_bar::notify_warn(
            world,
            format!(
                "{} is not open; open it first, then rebind from this list or its inspector",
                finding.document.display()
            ),
        );
        return;
    }
    crate::inspector::asset_row::close_open_asset_picker(world);
    // Every document the project holds, not only the files the index carries
    // as assets of their own: a reference names a document — a prefab a
    // scene instances, a material a mesh wears — and the prefab and the
    // scene are not assets in the index's sense, so listing entries alone
    // would offer nothing to rebind a broken prefab source to.
    let assets = crate::asset_index::assets_dir(world);
    let mut items: Vec<String> = match assets.as_deref() {
        Some(assets) => jackdaw_bsn::walk_document_files(assets)
            .into_iter()
            .filter_map(|file| {
                let relative = file.strip_prefix(assets).ok()?;
                if crate::asset_index::is_catalog_file(relative) {
                    return None;
                }
                Some(relative.to_slash_lossy().into_owned())
            })
            .collect(),
        None => Vec::new(),
    };
    items.sort();
    if items.is_empty() {
        crate::status_bar::notify_warn(world, "this project holds no assets to rebind to");
        return;
    }
    world.spawn((
        PickerProps::new(spawn_missing_picker_item, on_missing_pick)
            .items(items)
            .title("Rebind reference")
            .placeholder(Some("Search assets..")),
        MissingPicker(finding.clone()),
        crate::EditorEntity,
        crate::BlocksCameraInput,
    ));
    world.flush();
}

/// One entry in the rebind picker, the way the asset rows spell theirs.
fn spawn_missing_picker_item(
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

/// The tab whose document is `finding.document`, as the index keys it.
fn tab_holding(world: &World, finding: &AuditFinding) -> Option<usize> {
    let scenes = world.resource::<crate::scenes::Scenes>();
    scenes.tabs.iter().position(|tab| {
        tab.path.as_deref().is_some_and(|path| {
            crate::asset_index::indexed_path(world, path).as_deref()
                == Some(finding.document.as_path())
        })
    })
}

/// The pick a row's Rebind opened, answered: the reference in the open tab's
/// document is rewritten to the chosen path, as an edit (the tab turns
/// dirty; nothing reaches a file until the tab's own save).
fn on_missing_pick(
    input: In<SelectInput>,
    items: Query<&PickerItems<String>>,
    pickers: Query<&MissingPicker>,
    mut commands: Commands,
) -> Result {
    let picker = input.entities.picker;
    let chosen = items.get(picker)?.at(input.index)?.clone();
    let finding = pickers.get(picker).map(|picker| picker.0.clone());
    commands.entity(picker).try_despawn();
    let Ok(finding) = finding else { return Ok(()) };
    commands.queue(move |world: &mut World| {
        rebind(world, &finding, &chosen);
    });
    Ok(())
}

/// Rewrite one reference in the open tab's document and dirty the tab.
pub(crate) fn rebind(world: &mut World, finding: &AuditFinding, chosen: &str) {
    let Some(index) = tab_holding(world, finding) else {
        return;
    };
    let rewritten = rewrite_tab_reference(world, index, finding, chosen);
    if !rewritten {
        crate::status_bar::notify_warn(
            world,
            "the document no longer holds that reference; reopen the list",
        );
        return;
    }
    {
        let mut scenes = world.resource_mut::<crate::scenes::Scenes>();
        scenes.set_changed();
        scenes.tabs[index].dirty = true;
    }
    crate::status_bar::notify_info(
        world,
        format!("rebound to {chosen}; save the tab to write it"),
    );
}

/// Rewrite the reference one finding names, in the document its tab holds:
/// the snapshot of an inactive scene tab, the cache entry of a prefab tab,
/// or the live AST of the active scene tab. Answers whether the reference
/// was found and replaced.
fn rewrite_tab_reference(
    world: &mut World,
    index: usize,
    finding: &AuditFinding,
    chosen: &str,
) -> bool {
    // A tab's document spells its prefab sources absolutely (the load made
    // them so), while the finding names them the way a save would — so both
    // sides meet on the relative spelling before the rewrite.
    let assets = crate::asset_index::assets_dir(world);
    let snapshot = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        match scenes.tabs.get(index).map(|tab| &tab.content) {
            Some(crate::scenes::TabContent::Scene(Some(ast))) => Some(ast.deep_clone()),
            _ => None,
        }
    };
    if let Some(mut ast) = snapshot {
        fold_sources_to_relative(&mut ast, assets.as_deref());
        let replaced = rewrite_ast_reference(&mut ast, finding, chosen);
        if replaced {
            let mut scenes = world.resource_mut::<crate::scenes::Scenes>();
            scenes.tabs[index].content = crate::scenes::TabContent::Scene(Some(Box::new(ast)));
        }
        return replaced;
    }
    let held_prefab = {
        let scenes = world.resource::<crate::scenes::Scenes>();
        match scenes.tabs.get(index).map(|tab| &tab.content) {
            Some(crate::scenes::TabContent::Prefab(path)) => Some(path.clone()),
            _ => None,
        }
    };
    if let Some(held) = held_prefab {
        let Some(mut ast) = world
            .resource::<crate::prefab::PrefabAstCache>()
            .get(held.as_path())
            .map(crate::prefab::resolver_bsn::clone_scene)
        else {
            return false;
        };
        fold_sources_to_relative(&mut ast, assets.as_deref());
        let replaced = rewrite_ast_reference(&mut ast, finding, chosen);
        if replaced {
            world
                .resource_mut::<crate::prefab::PrefabAstCache>()
                .insert(held.as_path(), ast);
            // The world still shows the cache entry it was spawned from:
            // activating the tab again installs the rewritten one, the way
            // reopening the document would.
            if world.resource::<crate::scenes::Scenes>().active == index {
                crate::scenes::swap::activate_tab(world, index);
            }
        }
        return replaced;
    }
    // The active scene tab: its document is the live AST, and the world it
    // is rebuilt from follows entity by entity.
    let live = world.remove_resource::<jackdaw_bsn::SceneBsnAst>();
    let Some(mut ast) = live else {
        return false;
    };
    fold_sources_to_relative(&mut ast, assets.as_deref());
    let replaced = rewrite_ast_reference(&mut ast, finding, chosen);
    if replaced {
        let entities: Vec<Entity> = ast.ecs_to_ast.keys().copied().collect();
        world.insert_resource(ast);
        let chosen_path = Path::new(chosen);
        for entity in entities {
            // The world the next save emits from reads the component, not
            // the patch: an `IsA` whose source was rebound takes the new
            // file directly, spelled absolutely the way the load left it.
            if let Ok(mut held) = world.get_entity_mut(entity) {
                if let Some(mut isa) = held.get_mut::<jackdaw_prefab::IsA>() {
                    let was = isa.source.clone();
                    let folded = match assets.as_deref() {
                        Some(assets) if was.is_absolute() => {
                            pathdiff::diff_paths(&was, assets).unwrap_or(was)
                        }
                        _ => was,
                    };
                    if folded == chosen_path {
                        // matched the new value already
                    } else if folded == Path::new(&finding.reference) {
                        isa.source = match assets.as_deref() {
                            Some(assets) => assets.join(chosen),
                            None => chosen_path.to_path_buf(),
                        };
                    }
                }
                if world.get::<jackdaw_bsn::AstNodeRef>(entity).is_some() {
                    crate::scene_io::resync_entity_from_ast(world, entity);
                }
            }
        }
    } else {
        world.insert_resource(ast);
    }
    replaced
}

/// Fold a document's absolute prefab sources to their relative spellings,
/// the way a save does, so a rewrite matches what the finding names.
fn fold_sources_to_relative(ast: &mut jackdaw_bsn::SceneBsnAst, assets: Option<&Path>) {
    if let Some(assets) = assets {
        jackdaw_prefab::relativize_isa_sources_under(ast, assets);
    }
}

/// Find the node and field a finding names, in an AST, and rewrite the
/// reference it holds. The names travel as the finding spells them: the
/// entity's `#Name`, the component's type path (matched on its short name),
/// and the field.
fn rewrite_ast_reference(
    ast: &mut jackdaw_bsn::SceneBsnAst,
    finding: &AuditFinding,
    chosen: &str,
) -> bool {
    use jackdaw_bsn::{BsnPatch, BsnValue};
    let mut replaced = false;
    let mut walk: Vec<Entity> = ast.roots.clone();
    while let Some(node) = walk.pop() {
        walk.extend(ast.get_children_ast(node));
        let name_matches = finding
            .entity_name
            .as_deref()
            .is_none_or(|named| ast.get_name(node) == Some(named));
        if !name_matches {
            continue;
        }
        let Some(patches) = ast.get_patches(node).cloned() else {
            continue;
        };
        for patch_entity in patches.0 {
            let Some(mut patch) = ast.world.get_mut::<BsnPatch>(patch_entity) else {
                continue;
            };
            let matches_component = match &*patch {
                BsnPatch::Struct(data) => {
                    data.type_path
                        .ends_with(&format!("::{}", finding.component))
                        || data.type_path == finding.component
                }
                // A newtype component — the `AudioPlayer` a Song carries, the
                // `MeshMaterial3d` a mesh wears — is a patch whose type_path
                // the audit reports truncated at its last `::` (a generic
                // tail reads `AudioSource>`), so the arm meets it the way
                // the Struct arm meets a short name: by the path's own tail.
                // Without this arm the rebind answered that the document no
                // longer holds the reference it had just reported (AR11).
                BsnPatch::TupleStruct(data) => {
                    data.type_path == finding.component
                        || data.type_path.rsplit("::").next() == Some(finding.component.as_str())
                }
                BsnPatch::Base(_) => finding.component == "Base",
                _ => false,
            };
            if !matches_component {
                continue;
            }
            match &mut *patch {
                BsnPatch::Struct(data) => {
                    for field in data.fields.0.iter_mut() {
                        if field.name != finding.field {
                            continue;
                        }
                        match &mut field.value {
                            BsnValue::String(spelling) if spelling == &finding.reference => {
                                *spelling = chosen.to_string();
                                replaced = true;
                            }
                            BsnValue::List(items) => {
                                for item in items.iter_mut() {
                                    if let BsnValue::String(spelling) = item
                                        && spelling == &finding.reference
                                    {
                                        *spelling = chosen.to_string();
                                        replaced = true;
                                    }
                                }
                            }
                            // A materials map — the entries the audit picks
                            // up on the two override layers (`MaterialOverrides`
                            // / `InstanceMaterialOverrides`, T23) — holds its
                            // references as the map's values, one per material
                            // name. The same depth rule as the list arm: the
                            // strings that are values directly, and only them
                            // — never a key (a material name is not a path)
                            // and never a string nested inside a value.
                            BsnValue::Map(entries) => {
                                for (_, value) in entries.iter_mut() {
                                    if let BsnValue::String(spelling) = value
                                        && spelling == &finding.reference
                                    {
                                        *spelling = chosen.to_string();
                                        replaced = true;
                                    }
                                }
                            }
                            _ => {}
                        }
                    }
                }
                BsnPatch::TupleStruct(data) => {
                    // The newtype's one held value is the reference the
                    // audit named (its field reads "0").
                    for value in &mut data.values {
                        if let BsnValue::String(spelling) = value
                            && spelling == &finding.reference
                        {
                            *spelling = chosen.to_string();
                            replaced = true;
                        }
                    }
                }
                BsnPatch::Base(base) if base == &finding.reference => {
                    *base = chosen.to_string();
                    replaced = true;
                }
                _ => {}
            }
        }
    }
    replaced
}

/// The folder holding the finding's document, in the desktop's file manager.
fn show_in_file_manager(world: &mut World, finding: &AuditFinding) {
    let assets = crate::asset_index::assets_dir(world);
    let file = match assets {
        Some(assets) => assets.join(&finding.document),
        None => finding.document.clone(),
    };
    let folder = file.parent().map(Path::to_path_buf).unwrap_or(file);
    if let Err(err) = crate::project_window::open_with_desktop(&folder) {
        crate::status_bar::notify_warn(
            world,
            format!("{} cannot be opened: {err}", folder.display()),
        );
    }
}

/// The finding's reference, on the clipboard.
fn copy_reference(world: &mut World, finding: &AuditFinding) {
    if let Some(mut clipboard) = world.get_resource_mut::<Clipboard>() {
        let _ = clipboard.set_text(finding.reference.clone());
        crate::status_bar::notify_info(world, format!("copied {}", finding.reference));
    }
}

/// Bring the finding's document forward with its entity selected. A document
/// with no tab opens one; a named entity in a tab already in front is
/// selected outright.
fn locate(world: &mut World, finding: &AuditFinding) {
    let assets = crate::asset_index::assets_dir(world);
    let Some(assets) = assets else {
        return;
    };
    let file = jackdaw_bsn::existing_form(&assets.join(&finding.document))
        .unwrap_or_else(|| assets.join(&finding.document));
    if tab_holding(world, finding).is_none() {
        crate::scenes::operators::scene_open_system(world, &file);
        crate::status_bar::notify_info(
            world,
            format!(
                "opened {}; rebind from the list once its tab is in front",
                finding.document.display()
            ),
        );
        return;
    }
    let Some(named) = finding.entity_name.as_deref() else {
        crate::status_bar::notify_warn(world, "the reference sits on an unnamed entity");
        return;
    };
    let mut named_query = world.query_filtered::<Entity, With<Name>>();
    let hit = named_query.iter(world).find(|entity| {
        world
            .get::<Name>(*entity)
            .is_some_and(|name| name.as_str() == named)
    });
    match hit {
        Some(entity) => {
            crate::selection::select_only(world, entity);
            crate::status_bar::notify_info(world, format!("selected {named}"));
        }
        None => {
            crate::status_bar::notify_warn(world, format!("{named} is not in the open scene"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use jackdaw_bsn::{BsnPatch, BsnValue};

    /// The finding a tuple-struct reference produces, built the way the
    /// audit actually builds it: the component is the patch's own
    /// `type_path` after its last `::` (`reference_audit`'s `rsplit` names a
    /// newtype's generic tail — `AudioSource>` — truncating the full path
    /// with generics), the field the newtype holds, the reference as the
    /// document spells it.
    fn tuple_struct_finding(ast: &mut jackdaw_bsn::SceneBsnAst, entity: &str) -> AuditFinding {
        let mut type_path = String::new();
        let mut reference = String::new();
        let mut walk: Vec<Entity> = ast.roots.clone();
        while let Some(node) = walk.pop() {
            walk.extend(ast.get_children_ast(node));
            if ast.get_name(node) != Some(entity) {
                continue;
            }
            for patch_entity in ast
                .get_patches(node)
                .cloned()
                .map(|patches| patches.0)
                .unwrap_or_default()
            {
                if let Some(BsnPatch::TupleStruct(data)) = ast.world.get::<BsnPatch>(patch_entity) {
                    type_path = data.type_path.clone();
                    for value in &data.values {
                        if let jackdaw_bsn::BsnValue::String(spelling) = value {
                            reference = spelling.clone();
                        }
                    }
                }
            }
        }
        let component = type_path
            .rsplit("::")
            .next()
            .unwrap_or(&type_path)
            .to_string();
        AuditFinding {
            document: Path::new("t18.bsn").to_path_buf(),
            entity_name: Some(entity.to_string()),
            component,
            field: "0".to_string(),
            reference,
            kind: FindingKind::Missing,
        }
    }

    /// The tuple-struct references the audit reports — the `AudioPlayer` a
    /// Song carries — rebind. Before the `TupleStruct` arm the matcher fell
    /// through and the rebind answered "the document no longer holds that
    /// reference" for the very finding it had just reported (AR11's red,
    /// three live runs on the T2 matrix).
    #[test]
    fn a_tuple_struct_reference_rebinds() {
        let text = "#Root\n\
             bevy_transform::components::transform::Transform\n\
             bevy_ecs::hierarchy::Children [\n\
             #Song\n\
             bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>(\
             \"sounds/blip.wav\")\n\
             bevy_audio::audio::PlaybackSettings {\n\
             mode: bevy_audio::audio::PlaybackMode::Loop,\n\
             }\n\
             ]\n";
        let mut ast = jackdaw_bsn::parse_bsn_text(text).expect("the scene parses");
        let finding = tuple_struct_finding(&mut ast, "Song");

        let replaced = rewrite_ast_reference(&mut ast, &finding, "sounds/blip_renamed.wav");

        assert!(
            replaced,
            "the tuple-struct finding the audit names rewrites"
        );
        let mut spelled = String::new();
        let mut walk: Vec<Entity> = ast.roots.clone();
        while let Some(node) = walk.pop() {
            walk.extend(ast.get_children_ast(node));
            for patch_entity in ast
                .get_patches(node)
                .cloned()
                .map(|patches| patches.0)
                .unwrap_or_default()
            {
                if let Some(BsnPatch::TupleStruct(data)) = ast.world.get::<BsnPatch>(patch_entity) {
                    for value in &data.values {
                        if let jackdaw_bsn::BsnValue::String(spelling) = value {
                            spelled = spelling.clone();
                        }
                    }
                }
            }
        }
        assert_eq!(
            spelled, "sounds/blip_renamed.wav",
            "the document carries the chosen path"
        );
    }

    /// A finding naming another component leaves the tuple-struct patch
    /// alone: the arm matches by the patch's own type path, not by the
    /// reference alone.
    #[test]
    fn a_tuple_struct_rebind_stays_on_its_own_component() {
        let text = "#Song\n\
             bevy_audio::audio::AudioPlayer<bevy_audio::audio_source::AudioSource>(\
             \"sounds/blip.wav\")\n";
        let mut ast = jackdaw_bsn::parse_bsn_text(text).expect("the scene parses");
        let finding = AuditFinding {
            document: Path::new("t18.bsn").to_path_buf(),
            entity_name: Some("Song".to_string()),
            component: "some_game::SomeOtherComponent".to_string(),
            field: "0".to_string(),
            reference: "sounds/blip.wav".to_string(),
            kind: FindingKind::Missing,
        };

        let replaced = rewrite_ast_reference(&mut ast, &finding, "sounds/blip_renamed.wav");

        assert!(!replaced, "another component's finding does not rewrite");
        let mut walk: Vec<Entity> = ast.roots.clone();
        while let Some(node) = walk.pop() {
            walk.extend(ast.get_children_ast(node));
            for patch_entity in ast
                .get_patches(node)
                .cloned()
                .map(|patches| patches.0)
                .unwrap_or_default()
            {
                if let Some(BsnPatch::TupleStruct(data)) = ast.world.get::<BsnPatch>(patch_entity) {
                    for value in &data.values {
                        if let jackdaw_bsn::BsnValue::String(spelling) = value {
                            assert_eq!(
                                spelling, "sounds/blip.wav",
                                "the held reference stays untouched"
                            );
                        }
                    }
                }
            }
        }
    }

    /// The materials map of an override layer, spelled the way a save
    /// writes it, and the finding the audit builds for one of its values
    /// (the component by its short name, the field `materials`, the
    /// reference as the value spells it).
    const OVERRIDE_SCENE: &str = "#props\n\
         jackdaw_scene_types::types::GltfSource {\n\
         path: \"models/props.glb\",\n\
         scene_index: 0,\n\
         }\n\
         jackdaw_scene_types::types::MaterialOverrides {\n\
         materials: map[\n\
         (\"Rock\", \"materials/mossy.bsn\"),\n\
         (\"Trim\", \"materials/deep.bsn\")\n\
         ],\n\
         }\n";

    fn override_finding(entity: &str, reference: &str) -> AuditFinding {
        AuditFinding {
            document: Path::new("t23.bsn").to_path_buf(),
            entity_name: Some(entity.to_string()),
            component: "MaterialOverrides".to_string(),
            field: "materials".to_string(),
            reference: reference.to_string(),
            kind: FindingKind::Missing,
        }
    }

    /// The materials map an override layer holds, read back off the AST as
    /// `(key, value)` spelling pairs. Entries whose halves are not plain
    /// strings are skipped — the reader only witnesses the strings.
    fn override_map_of(ast: &jackdaw_bsn::SceneBsnAst, entity: &str) -> Vec<(String, String)> {
        let mut walk: Vec<Entity> = ast.roots.clone();
        while let Some(node) = walk.pop() {
            walk.extend(ast.get_children_ast(node));
            if ast.get_name(node) != Some(entity) {
                continue;
            }
            for patch_entity in ast
                .get_patches(node)
                .cloned()
                .map(|patches| patches.0)
                .unwrap_or_default()
            {
                if let Some(BsnPatch::Struct(data)) = ast.world.get::<BsnPatch>(patch_entity) {
                    if !data.type_path.ends_with("MaterialOverrides") {
                        continue;
                    }
                    for field in &data.fields.0 {
                        if field.name != "materials" {
                            continue;
                        }
                        if let BsnValue::Map(entries) = &field.value {
                            return entries
                                .iter()
                                .filter_map(|(key, value)| match (key, value) {
                                    (BsnValue::String(key), BsnValue::String(value)) => {
                                        Some((key.clone(), value.clone()))
                                    }
                                    _ => None,
                                })
                                .collect();
                        }
                    }
                }
            }
        }
        Vec::new()
    }

    /// The map values the audit picks up on an override layer rebind. Before
    /// the `Map` arm the matcher fell through and the rebind answered "the
    /// document no longer holds that reference" for the very finding it had
    /// just reported (MO9's red, the T2 live matrix).
    #[test]
    fn an_override_map_reference_rebinds() {
        let mut ast = jackdaw_bsn::parse_bsn_text(OVERRIDE_SCENE).expect("the scene parses");
        let finding = override_finding("props", "materials/deep.bsn");

        let replaced = rewrite_ast_reference(&mut ast, &finding, "materials/deep2.bsn");

        assert!(
            replaced,
            "the override-map finding the audit names rewrites"
        );
        assert_eq!(
            override_map_of(&ast, "props"),
            vec![
                ("Rock".to_string(), "materials/mossy.bsn".to_string()),
                ("Trim".to_string(), "materials/deep2.bsn".to_string()),
            ],
            "only the entry naming the file moved; its siblings stay"
        );
        // The model's own source — a reference of its own on the same
        // entity — was never the finding's field, and stays.
        let mut walk: Vec<Entity> = ast.roots.clone();
        while let Some(node) = walk.pop() {
            walk.extend(ast.get_children_ast(node));
            for patch_entity in ast
                .get_patches(node)
                .cloned()
                .map(|patches| patches.0)
                .unwrap_or_default()
            {
                if let Some(BsnPatch::Struct(data)) = ast.world.get::<BsnPatch>(patch_entity)
                    && data.type_path.ends_with("GltfSource")
                {
                    assert_eq!(
                        data.fields.0[0].value,
                        BsnValue::String("models/props.glb".to_string()),
                        "a sibling component's reference stays untouched"
                    );
                }
            }
        }
    }

    /// Every entry naming the broken file moves, together; a key that
    /// happens to spell the path is a material name, not a reference, and
    /// never moves; and a value that only nests the spelling keeps it.
    #[test]
    fn an_override_map_rebind_moves_values_only() {
        let text = "#kit\n\
             jackdaw_scene_types::types::MaterialOverrides {\n\
             materials: map[\n\
             (\"A\", \"materials/gone.bsn\"),\n\
             (\"B\", \"materials/gone.bsn\"),\n\
             (\"materials/gone.bsn\", \"materials/kept.bsn\")\n\
             ],\n\
             }\n";
        let mut ast = jackdaw_bsn::parse_bsn_text(text).expect("the scene parses");
        let finding = override_finding("kit", "materials/gone.bsn");

        let replaced = rewrite_ast_reference(&mut ast, &finding, "materials/back.bsn");

        assert!(replaced, "the entries naming the file rewrite");
        assert_eq!(
            override_map_of(&ast, "kit"),
            vec![
                ("A".to_string(), "materials/back.bsn".to_string()),
                ("B".to_string(), "materials/back.bsn".to_string()),
                (
                    "materials/gone.bsn".to_string(),
                    "materials/kept.bsn".to_string()
                ),
            ],
            "both holders moved; the key that spells the path stays a name"
        );
    }

    /// A finding naming another component, or another field, leaves the
    /// override map alone: the arm matches by the patch's type path and the
    /// field's name, not by the reference alone.
    #[test]
    fn an_override_map_rebind_stays_on_its_own_component_and_field() {
        let mut ast = jackdaw_bsn::parse_bsn_text(OVERRIDE_SCENE).expect("the scene parses");

        let mut finding = override_finding("props", "materials/deep.bsn");
        finding.component = "InstanceMaterialOverrides".to_string();
        let replaced = rewrite_ast_reference(&mut ast, &finding, "materials/deep2.bsn");
        assert!(
            !replaced,
            "another layer's finding does not rewrite the map"
        );
        assert_eq!(
            override_map_of(&ast, "props"),
            vec![
                ("Rock".to_string(), "materials/mossy.bsn".to_string()),
                ("Trim".to_string(), "materials/deep.bsn".to_string()),
            ],
            "the map is untouched by another layer's finding"
        );

        let mut ast = jackdaw_bsn::parse_bsn_text(OVERRIDE_SCENE).expect("the scene parses");
        let finding = override_finding("props", "materials/nobody-holds-this.bsn");
        let replaced = rewrite_ast_reference(&mut ast, &finding, "materials/deep2.bsn");
        assert!(!replaced, "a reference no value spells does not rewrite");
        assert!(
            override_map_of(&ast, "props")
                .iter()
                .all(|(_, value)| value != "materials/deep2.bsn"),
            "the chosen path landed nowhere"
        );
    }
}
