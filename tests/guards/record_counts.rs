//! Record-count consistency for undo: a user-facing gesture leaves exactly
//! one entry on the undo stack.
//!
//! Covers the Y1 family (self-pushing operators that also took a framework
//! snapshot, so one click became two entries), N1 (`component.add` /
//! `component.remove`), Y2 (the Outliner context-menu Duplicate that left
//! nothing at all) and Y4 (the unpack-by-drag gesture that left two entries
//! and an undo middle state), plus the `jackdaw/history` BRP probe the
//! on-machine chains assert through.
//!
//! Every dispatch goes through `run_op_clause_as_user`, the button/keybind
//! path (`creates_history_entry: true`), because that is the setting the
//! double-record defect lives under.

use bevy::prelude::*;
use bevy::reflect::TypePath;
use jackdaw::boot_ops::run_op_clause_as_user;
use jackdaw::remote::server::history_handler;
use serde_json::json;

use super::batch_undo::{call, depth, scene_text};
use crate::util::{self, OperatorResultExt as _};

/// A scene entity the selection-driven gestures act on.
const ZONE_SCENE: &str = "#Zone\nbevy_transform::components::transform::Transform\n";

/// A prefab whose instance has a child worth unpacking: `#Pebble` at
/// `PrefabEntityId` 7, carried at x=3 so its Transform survives visibly.
const ROCK_PREFAB: &str = "#Rock\n\
     jackdaw::prefab::components::Prefab\n\
     jackdaw::prefab::components::PrefabEntityId(0)\n\
     bevy_transform::components::transform::Transform\n\
     bevy_ecs::hierarchy::Children [\n\
         #Pebble\n\
         jackdaw::prefab::components::PrefabEntityId(7)\n\
         bevy_transform::components::transform::Transform {\n\
             translation: glam::Vec3 { x: 3.0, y: 0.0, z: 0.0 },\n\
             rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },\n\
             scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },\n\
         }\n\
     ]";

/// An editor on a project holding a saved scene (open in front) and a prefab
/// with one child, whose instances the gestures unpack.
fn editor() -> (App, tempfile::TempDir) {
    let tmp = tempfile::Builder::new()
        .prefix("jackdaw-record-counts-")
        .tempdir()
        .expect("temp dir");
    std::fs::create_dir_all(tmp.path().join("assets/prefabs")).expect("asset folders");
    std::fs::write(tmp.path().join("assets/prefabs/rock.bsn"), ROCK_PREFAB).expect("the prefab");
    std::fs::write(tmp.path().join("assets/zone.bsn"), ZONE_SCENE).expect("the scene");

    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(jackdaw::project::ProjectRoot {
            root: tmp.path().to_path_buf(),
            config: default(),
        });
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    jackdaw::boot_ops::run_op_clause(app.world_mut(), "scene.open path=assets/zone.bsn")
        .expect("the scene opens")
        .assert_finished();
    util::settle_scene_load(&mut app);
    (app, tmp)
}

/// The Zone scene entity, selected so selection-driven gestures have a target.
fn zone_selected(app: &mut App) -> Entity {
    let zone = app
        .world_mut()
        .query::<(Entity, &Name)>()
        .iter(app.world())
        .find(|(_, name)| name.as_str() == "Zone")
        .map(|(entity, _)| entity)
        .expect("the Zone entity");
    jackdaw::selection::select_only(app.world_mut(), zone);
    app.update();
    zone
}

/// How many entities in the scene answer to `name`.
fn named(app: &mut App, name: &str) -> usize {
    app.world_mut()
        .query::<&Name>()
        .iter(app.world())
        .filter(|entity_name| entity_name.as_str() == name)
        .count()
}

fn undo(app: &mut App) {
    super::batch_undo::history(app, "history.undo");
}

fn redo(app: &mut App) {
    super::batch_undo::history(app, "history.redo");
}

fn user(app: &mut App, clause: &str) {
    run_op_clause_as_user(app.world_mut(), clause)
        .unwrap_or_else(|err| panic!("{clause}: {err}"))
        .assert_finished();
    app.update();
}

// ------------------------------------------------------------------ Y1 ---

/// An Add-menu spawn is one entry: the operator's own `SpawnEntity` push,
/// with no framework snapshot beside it.
#[test]
fn an_add_menu_spawn_is_one_user_entry() {
    let (mut app, _tmp) = editor();
    let before = depth(&app);
    user(&mut app, "entity.add.cube");
    assert_eq!(depth(&app), before + 1, "one entry for one Add");
    undo(&mut app);
    assert_eq!(named(&mut app, "Cube"), 0, "the undo takes the cube back");
}

/// `spawn_undoable`-backed adds (the reflection probe) are one entry too.
#[test]
fn a_spawn_undoable_add_is_one_user_entry() {
    let (mut app, _tmp) = editor();
    let before = depth(&app);
    user(&mut app, "entity.add.reflection_probe");
    assert_eq!(depth(&app), before + 1, "one entry for the probe");
    undo(&mut app);
    assert_eq!(named(&mut app, "Reflection Probe"), 0);
}

/// The J keybind joins the selected brushes as one entry: the operator's
/// own `SetBrush` + `Despawn` group, with no framework snapshot beside it.
/// Its one undo takes the join back.
#[test]
fn the_join_keybind_is_one_user_entry() {
    let (mut app, _tmp) = editor();
    let left = app
        .world_mut()
        .spawn((
            Name::new("LeftBrush"),
            jackdaw_scene_types::Brush::cuboid(0.5, 0.5, 0.5),
            Transform::default(),
            Visibility::default(),
        ))
        .id();
    let right = app
        .world_mut()
        .spawn((
            Name::new("RightBrush"),
            jackdaw_scene_types::Brush::cuboid(0.5, 0.5, 0.5),
            Transform::from_translation(Vec3::new(2.0, 0.0, 0.0)),
            Visibility::default(),
        ))
        .id();
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), left);
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), right);
    jackdaw::selection::select_many(app.world_mut(), &[left, right]);
    app.update();
    app.update();

    let before_text = scene_text(&mut app);
    let before = depth(&app);
    user(&mut app, "brush.join");
    assert_eq!(depth(&app), before + 1, "the join keybind is one entry");
    let joined = scene_text(&mut app);
    assert_ne!(joined, before_text, "the brushes merged in the document");

    // One undo takes the join back: both brushes exist again, each with its
    // own document node. (Byte equality is deliberately not asserted: the
    // async `recenter_brush_origins` pass shifts the kept brush's Transform
    // the frame after the join, and the join's own command group does not
    // record that shift — a pre-existing undo gap in the join itself, out
    // of scope for the record-count fix this test pins.)
    undo(&mut app);
    let named_after: std::collections::HashSet<&str> = app
        .world_mut()
        .query::<&Name>()
        .iter(app.world())
        .map(Name::as_str)
        .collect();
    assert!(
        named_after.contains("LeftBrush") && named_after.contains("RightBrush"),
        "one undo restores both brushes, got {named_after:?}"
    );
    let restored = scene_text(&mut app);
    assert_eq!(
        restored.matches("#LeftBrush").count(),
        1,
        "left is back in the document"
    );
    assert_eq!(
        restored.matches("#RightBrush").count(),
        1,
        "right is back in the document"
    );
}

/// The Ctrl+E keybind extends a brush face as one entry, the same shape as
/// the J join: the operator queues a closure into an impl that pushes its
/// own rebuild command, so a history-creating dispatch must not wrap the
/// same document change in a framework snapshot beside it.
///
/// The Face-edit-mode entry path drives it: a face picked on the active
/// brush and the target brush in the selection, the way a click in face
/// mode leaves them. (The Object-mode path needs a remembered or hovered
/// face, which a headless run cannot honestly produce.)
#[test]
fn the_extend_face_keybind_is_one_user_entry() {
    let (mut app, _tmp) = editor();
    let primary = app
        .world_mut()
        .spawn((
            Name::new("ExtendBrush"),
            jackdaw_scene_types::Brush::cuboid(0.5, 0.5, 0.5),
            Transform::default(),
            Visibility::default(),
        ))
        .id();
    let target = app
        .world_mut()
        .spawn((
            Name::new("TargetBrush"),
            jackdaw_scene_types::Brush::cuboid(0.5, 0.5, 0.5),
            // A wall square to the extension direction: its oblique faces are
            // the "angled" constraints the extend resolves against (the flat
            // axis-aligned faces of a cuboid pair constrain nothing here).
            Transform::from_rotation(Quat::from_rotation_y(std::f32::consts::FRAC_PI_4))
                .with_translation(Vec3::new(3.0, 0.0, 0.0)),
            Visibility::default(),
        ))
        .id();
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), primary);
    jackdaw::scene_io::register_entity_in_ast(app.world_mut(), target);
    app.update();
    app.update();
    // Face mode with face 0 picked on the primary, and both brushes
    // selected so the impl has a target to conform to.
    *app.world_mut().resource_mut::<jackdaw::brush::EditMode>() =
        jackdaw::brush::EditMode::BrushEdit(jackdaw::brush::BrushEditMode::Face);
    {
        let mut brush_selection = app
            .world_mut()
            .resource_mut::<jackdaw::brush::BrushSelection>();
        brush_selection.active_brush = Some(primary);
        brush_selection.sub_mut(primary).faces = vec![0];
    }
    jackdaw::selection::select_many(app.world_mut(), &[primary, target]);
    app.update();
    app.update();

    let before_text = scene_text(&mut app);
    let before = depth(&app);
    user(&mut app, "brush.extend_face_to_brush");
    assert_eq!(
        depth(&app),
        before + 1,
        "the extend keybind is one entry: the impl pushes its own command, \
         with no framework snapshot beside it"
    );
    let extended = scene_text(&mut app);
    assert_ne!(extended, before_text, "the brush changed in the document");

    undo(&mut app);
    let restored = scene_text(&mut app);
    assert_eq!(
        restored.matches("#ExtendBrush").count(),
        1,
        "the extended brush is back in the document"
    );
    assert_eq!(
        restored.matches("#TargetBrush").count(),
        1,
        "the target brush survived untouched"
    );
}

/// A transform chord (Alt+G reset) is the one `CommandGroup` the reset
/// pushes, not that group plus a snapshot.
#[test]
fn a_reset_position_chord_is_one_user_entry() {
    let (mut app, _tmp) = editor();
    let zone = zone_selected(&mut app);
    user(&mut app, "entity.set_transform entity=Zone x=5 y=0 z=0");
    let before = depth(&app);
    user(&mut app, "transform.reset_position");
    assert_eq!(depth(&app), before + 1, "one entry for the reset");
    assert_eq!(
        app.world()
            .get::<Transform>(zone)
            .expect("zone")
            .translation,
        Vec3::ZERO,
        "the reset applied"
    );
    undo(&mut app);
    assert_eq!(
        app.world()
            .get::<Transform>(zone)
            .expect("zone")
            .translation
            .x,
        5.0,
        "one undo returns the moved position"
    );
}

/// Paste Components pastes the subtree clipboard as one entry, and its undo
/// takes the pasted subtree back out of the document.
#[test]
fn paste_components_is_one_user_entry() {
    let (mut app, _tmp) = editor();
    zone_selected(&mut app);
    user(&mut app, "entity.copy_components");
    let before_text = scene_text(&mut app);
    let before = depth(&app);
    user(&mut app, "entity.paste_components");
    assert_eq!(depth(&app), before + 1, "one entry for the paste");
    let pasted = scene_text(&mut app);
    assert_ne!(pasted, before_text, "the copy reached the document");
    undo(&mut app);
    assert_eq!(
        scene_text(&mut app),
        before_text,
        "the undo takes the pasted subtree back"
    );
}

// ------------------------------------------------------------------ N1 ---

/// A probe component only this test binary registers.
#[derive(Component, Reflect, Default)]
#[reflect(Component, Default)]
struct ProbeMarker;

fn app_with_probe() -> (App, tempfile::TempDir) {
    let (mut app, tmp) = editor();
    app.register_type::<ProbeMarker>();
    app.update();
    (app, tmp)
}

/// `component.add` pushed its own `AddComponent` and then let the framework
/// snapshot the same change: two entries for one picker click.
#[test]
fn component_add_is_one_user_entry() {
    let (mut app, _tmp) = app_with_probe();
    let zone = zone_selected(&mut app);
    let before = depth(&app);
    user(
        &mut app,
        &format!(
            "component.add entity=Zone type_path={}",
            ProbeMarker::type_path()
        ),
    );
    assert_eq!(depth(&app), before + 1, "one entry for the add");
    assert!(
        app.world().entity(zone).contains::<ProbeMarker>(),
        "the component landed"
    );
    undo(&mut app);
    assert!(
        !app.world().entity(zone).contains::<ProbeMarker>(),
        "the undo removes it"
    );
}

/// `component.remove` is the same defect class on the way out.
#[test]
fn component_remove_is_one_user_entry() {
    let (mut app, _tmp) = app_with_probe();
    let zone = zone_selected(&mut app);
    user(
        &mut app,
        &format!(
            "component.add entity=Zone type_path={}",
            ProbeMarker::type_path()
        ),
    );
    let before = depth(&app);
    user(
        &mut app,
        &format!(
            "component.remove entity=Zone type_path={}",
            ProbeMarker::type_path()
        ),
    );
    assert_eq!(depth(&app), before + 1, "one entry for the remove");
    undo(&mut app);
    assert!(
        app.world().entity(zone).contains::<ProbeMarker>(),
        "the undo puts it back"
    );
}

// -------------------------------------------------------- Y1 anti-leak ---

/// Every operator whose implementation pushes its own history entry declares
/// `allows_undo = false`, so a user dispatch cannot wrap it in a second
/// framework snapshot. Add to `SELF_PUSHING` when a new self-pushing op
/// lands; the mode-B list below it is the "must not touch" counterpart.
const SELF_PUSHING: &[&str] = &[
    // entity.add.* that spawn through create_entity_in_world / spawn_undoable.
    "entity.add.cube",
    "entity.add.sphere",
    "entity.add.point_light",
    "entity.add.directional_light",
    "entity.add.spot_light",
    "entity.add.camera",
    "entity.add.empty",
    "entity.add.plane",
    "entity.add.cylinder",
    "entity.add.wedge",
    "entity.add.cone",
    "entity.add.pyramid",
    "entity.add.animation_player",
    "entity.add.audio_source",
    "entity.add.fog_volume",
    "entity.add.reflection_probe",
    "entity.add.terrain",
    // Clipboard family: the paste itself pushes.
    "entity.paste_components",
    // Transform chords: reset / rotate / nudge push a CommandGroup.
    "transform.reset_position",
    "transform.reset_rotation",
    "transform.reset_scale",
    "transform.rotate_90_yaw_ccw",
    "transform.rotate_90_yaw_cw",
    "transform.rotate_90_pitch_ccw",
    "transform.rotate_90_pitch_cw",
    "transform.rotate_90_roll_ccw",
    "transform.rotate_90_roll_cw",
    "transform.nudge_x_neg",
    "transform.nudge_x_pos",
    "transform.nudge_y_neg",
    "transform.nudge_y_pos",
    "transform.nudge_z_neg",
    "transform.nudge_z_pos",
    // Inspector component chips push their own typed commands.
    "component.add",
    "component.remove",
    // Brush card buttons execute and push SetBrush / a group in place.
    "brush.face.clear_material",
    "brush.face.apply_texture_to_all",
    "brush.face.set_uv_scale_preset",
    "brush.clear_all_materials",
    // Keyframe chords push their own keyframe command groups.
    "clip.delete_keyframes",
    "clip.paste_keyframes",
    // The join keybind (J) pushes its own SetBrush + Despawn group.
    "brush.join",
    // The extend keybind (Ctrl+E) pushes its own rebuild command.
    "brush.extend_face_to_brush",
    // The PIE "Apply All" buttons push the edit group they build.
    "pie.live_edits_apply_all",
    // The PIE tray's single-edit save pushes its own save command.
    "pie.live_edit_save",
    // Terrain panel buttons push their own SetTerrainHeights entries.
    "terrain.generate",
    "terrain.erode",
    // The Resources panel's commands are their own history entries.
    "resource.insert",
    "resource.remove",
    "resource.set_field",
];

/// Operators that stay mode B — no push of their own, the framework's
/// snapshot is their one entry. Flipping any of these to `false` would
/// strip them of undo entirely.
const SNAPSHOT_BACKED: &[&str] = &[
    "entity.duplicate",
    "entity.toggle_visibility",
    "entity.place_gltf",
    "prefab.spawn_instance",
    "prefab.unpack_child",
    "prefab.unbundle_instance",
    "prefab.apply_to_source",
    "transform.numeric_apply",
    "animation.toggle_keyframe",
    "component.revert_baseline",
];

fn allows_undo(app: &mut App, wanted: &str) -> bool {
    app.world_mut()
        .query::<&jackdaw_api_internal::lifecycle::OperatorEntity>()
        .iter(app.world())
        .find(|op| op.id() == wanted)
        .map(jackdaw_api_internal::lifecycle::OperatorEntity::allows_undo)
        .unwrap_or_else(|| panic!("operator `{wanted}` is not registered"))
}

#[test]
fn self_pushing_operators_declare_undo_transparent() {
    let (mut app, _tmp) = editor();
    for id in SELF_PUSHING {
        assert!(
            !allows_undo(&mut app, id),
            "`{id}` pushes its own history entry, so a user dispatch must not \
             snapshot around it: it would be two entries for one action"
        );
    }
}

#[test]
fn snapshot_backed_operators_keep_allows_undo() {
    let (mut app, _tmp) = editor();
    for id in SNAPSHOT_BACKED {
        assert!(
            allows_undo(&mut app, id),
            "`{id}` has no push of its own; the framework snapshot is its \
             only undo entry and `allows_undo = false` would delete it"
        );
    }
}

// ------------------------------------------------------------------ Y2 ---

/// The Outliner's right-click Duplicate leaves exactly one entry and its
/// undo takes the copy away. Before the fix the menu called
/// `duplicate_selected` directly: no operator, no snapshot, no undo.
#[test]
fn the_outliner_context_menu_duplicate_is_one_entry() {
    let (mut app, _tmp) = editor();
    let zone = zone_selected(&mut app);
    let before = depth(&app);
    let before_text = scene_text(&mut app);
    app.world_mut()
        .trigger(jackdaw_widgets::context_menu::ContextMenuAction {
            action: "hierarchy.duplicate".to_string(),
            target_entity: Some(zone),
        });
    app.update();
    app.update();
    assert_eq!(depth(&app), before + 1, "the menu item is one entry");
    assert_ne!(
        scene_text(&mut app),
        before_text,
        "the copy reached the document"
    );
    undo(&mut app);
    assert_eq!(
        scene_text(&mut app),
        before_text,
        "one undo removes the copy"
    );
    assert_eq!(depth(&app), before);
}

// ------------------------------------------------------------------ Y4 ---

/// Dragging an inherited child out of its prefab instance is one entry: the
/// operator's own snapshot spans the AST unpack and the ECS reparent its
/// body performs. One undo returns the document byte-for-byte, with no
/// "hang it back on the instance" middle state, and the forward document
/// holds the unpacked child exactly once.
#[test]
fn dragging_an_inherited_child_out_is_one_clean_entry() {
    let (mut app, _tmp) = editor();
    zone_selected(&mut app);
    user(
        &mut app,
        "prefab.spawn_instance path=prefabs/rock.bsn pos_x=0 pos_y=0 pos_z=0",
    );
    util::update_until(
        &mut app,
        "the instance's Pebble to materialize",
        std::time::Duration::from_secs(10),
        |app| named(app, "Pebble") == 1,
    );

    let before_text = scene_text(&mut app);
    let before = depth(&app);
    user(
        &mut app,
        "prefab.unpack_child child_entity=Pebble drop_target_entity=Zone",
    );

    assert_eq!(depth(&app), before + 1, "the unpack gesture is one entry");
    let forward_text = scene_text(&mut app);
    assert_eq!(
        forward_text.matches("#Pebble").count(),
        before_text.matches("#Pebble").count() + 1,
        "the unpacked child appears exactly once more in the document"
    );

    undo(&mut app);
    assert_eq!(
        scene_text(&mut app),
        before_text,
        "one undo returns the document as the gesture found it"
    );
    redo(&mut app);
    assert_eq!(scene_text(&mut app), forward_text, "redo restores it");
}

// ------------------------------------------------------- history probe ---

/// The `jackdaw/history` BRP method reports what the assertions above read
/// in-process: stack lengths, the newest labels, and the tab's dirty flag.
#[test]
fn the_history_probe_reports_the_stacks() {
    let (mut app, _tmp) = editor();
    zone_selected(&mut app);
    user(&mut app, "entity.add.cube");

    let report = call(&mut app, history_handler, json!({ "entries": 3 }));
    assert_eq!(report["undo_len"], 1, "the add left one entry: {report}");
    assert_eq!(report["redo_len"], 0);
    assert_eq!(
        report["saved_len"], 0,
        "the scene opened with no baseline edits"
    );
    assert_eq!(report["dirty"], true, "an edit lights the tab");
    assert!(
        report["top"]
            .as_str()
            .is_some_and(|label| !label.is_empty()),
        "the newest entry carries its label: {report}"
    );
    assert_eq!(
        report["undo"].as_array().map(Vec::len),
        Some(1),
        "entries lists the newest first, capped at the ask: {report}"
    );

    undo(&mut app);
    let report = call(&mut app, history_handler, json!({}));
    assert_eq!(report["undo_len"], 0, "{report}");
    assert_eq!(report["redo_len"], 1, "{report}");
    assert_eq!(report["redo"][0]["label"], "Add Cube", "{report}");
}
