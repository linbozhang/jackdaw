//! The six matrix cells the T14 acceptance audit (loop/plans/
//! t14-prefab-acceptance.md §五-T1) found uncovered by the existing suites.
//! Each test names its matrix cell in a leading comment.
//!
//! Task 1 is record-only: where the current behavior is a catalogued defect
//! the test pins the *desired* behavior behind `#[ignore = "PF<n>: ..."]` so
//! the red evidence stays reproducible (`cargo test --test prefabs -- --ignored`)
//! and the T2 fix flips it green by deleting the attribute alone. The repo has
//! no other `#[ignore]` use; the alternative — pinning broken behavior green —
//! would enshrine the defect, so the red cell says so out loud instead.

#![allow(
    clippy::print_stdout,
    reason = "the E-6 probe cell records its binary outcome on the test output"
)]

use crate::util::{self, OperatorResultExt as _};

use bevy::prelude::*;
use jackdaw::commands::CommandHistory;
use jackdaw::prefab::{IsA, PrefabEntityId};
use jackdaw_api::prelude::*;
use jackdaw_api_internal::operator::{CallOperatorSettings, ExecutionContext};
use jackdaw_bsn::{BsnValue, SceneBsnAst};
use jackdaw_scene_types::PropertyValue;

const TRANSFORM_TYPE: &str = "bevy_transform::components::transform::Transform";
const PEID_TYPE: &str = "jackdaw::prefab::components::PrefabEntityId";
const ISA_TYPE: &str = "jackdaw::prefab::components::IsA";

/// A one-entity prefab whose root sits at the origin.
const BASELINE_ZERO: &str = "#p\n\
     jackdaw::prefab::components::Prefab\n\
     jackdaw::prefab::components::PrefabEntityId(0)\n\
     bevy_transform::components::transform::Transform {\n\
         translation: glam::Vec3 { x: 0.0, y: 0.0, z: 0.0 },\n\
         rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },\n\
         scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },\n\
     }\n\
     bevy_camera::visibility::Visibility::Inherited";

/// A two-entity prefab: a root at the origin and a child at x=1.
const BASELINE_WITH_CHILD: &str = "#p\n\
     jackdaw::prefab::components::Prefab\n\
     jackdaw::prefab::components::PrefabEntityId(0)\n\
     bevy_transform::components::transform::Transform {\n\
         translation: glam::Vec3 { x: 0.0, y: 0.0, z: 0.0 },\n\
         rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },\n\
         scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },\n\
     }\n\
     bevy_camera::visibility::Visibility::Inherited\n\
     bevy_ecs::hierarchy::Children [\n\
         #child\n\
         jackdaw::prefab::components::PrefabEntityId(1)\n\
         bevy_transform::components::transform::Transform {\n\
             translation: glam::Vec3 { x: 1.0, y: 0.0, z: 0.0 },\n\
             rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },\n\
             scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },\n\
         }\n\
         bevy_camera::visibility::Visibility::Inherited\n\
     ]";

fn make_app() -> App {
    use bevy::render::RenderPlugin;
    use bevy::render::settings::{RenderCreation, WgpuSettings};
    use bevy::winit::WinitPlugin;

    let mut app = App::new();
    app.add_plugins(
        DefaultPlugins
            .set(RenderPlugin {
                render_creation: RenderCreation::Automatic(Box::new(WgpuSettings {
                    backends: None,
                    ..default()
                })),
                ..default()
            })
            .disable::<WinitPlugin>(),
    );
    app.add_plugins(jackdaw_scene_types::SceneTypesPlugin::default());
    app.add_plugins(jackdaw_bsn::JackdawBsnPlugin);
    app.add_plugins(jackdaw::prefab::PrefabPlugin);
    app.init_resource::<jackdaw::commands::CommandHistory>();
    app.init_resource::<jackdaw::scene_io::SceneFilePath>();
    app.init_resource::<jackdaw::selection::Selection>();
    app.init_resource::<jackdaw::scenes::Scenes>();
    app
}

fn sole_isa_node(app: &App) -> Entity {
    app.world()
        .resource::<SceneBsnAst>()
        .entities_with_component(ISA_TYPE)
        .first()
        .copied()
        .expect("exactly one instance node was expected")
}

fn isa_entities(app: &mut App) -> Vec<Entity> {
    app.world_mut()
        .query_filtered::<Entity, With<IsA>>()
        .iter(app.world())
        .collect()
}

fn entity_with_peid(app: &mut App, id: u32) -> Entity {
    app.world_mut()
        .query::<(Entity, &PrefabEntityId)>()
        .iter(app.world())
        .find(|(_, peid)| peid.0 == id)
        .map(|(entity, _)| entity)
        .unwrap_or_else(|| panic!("no entity carries PrefabEntityId({id})"))
}

/// Edit one entity's Transform.x in the ECS and mirror it into the live
/// document, the way an inspector edit lands.
fn override_translation_x(app: &mut App, entity: Entity, x: f32) {
    if let Some(mut transform) = app.world_mut().get_mut::<Transform>(entity) {
        transform.translation.x = x;
    }
    jackdaw_bsn::sync_to_ast(app.world_mut(), entity, std::any::TypeId::of::<Transform>());
    app.update();
}

fn ecs_x(app: &mut App, entity: Entity) -> f32 {
    app.world()
        .get::<Transform>(entity)
        .expect("entity has a Transform")
        .translation
        .x
}

fn doc_x(app: &App, node: Entity) -> f64 {
    let ast = app.world().resource::<SceneBsnAst>();
    let key = ast
        .ast_for(node)
        .unwrap_or_else(|| panic!("node {node:?} is not in the live document"));
    match jackdaw_bsn::get_bsn_field(ast, key, TRANSFORM_TYPE, "translation.x") {
        Some(BsnValue::Float(v)) => v,
        other => {
            panic!("expected a float at translation.x, got {other:?}")
        }
    }
}

fn doc_has_authored_x(app: &App, node: Entity) -> Option<f64> {
    let ast = app.world().resource::<SceneBsnAst>();
    let key = ast.ast_for(node)?;
    match jackdaw_bsn::get_bsn_field(ast, key, TRANSFORM_TYPE, "translation.x") {
        Some(BsnValue::Float(v)) => Some(v),
        _ => None,
    }
}

/// Dispatch `id` the way a menu item does, so the framework wraps it in its
/// snapshot and the undo below is the undo a user gets.
#[track_caller]
fn call(app: &mut App, id: &'static str, params: &[(&'static str, PropertyValue)]) {
    let mut invocation = app.world_mut().operator(id).settings(CallOperatorSettings {
        execution_context: ExecutionContext::Invoke,
        creates_history_entry: true,
    });
    for (key, value) in params {
        invocation = invocation.param(*key, value.clone());
    }
    let result = invocation
        .call()
        .unwrap_or_else(|err| panic!("{id}: dispatch errored: {err}"));
    assert_eq!(result, OperatorResult::Finished, "{id} reported {result:?}");
    app.update();
}

fn undo_once(app: &mut App) {
    app.world_mut()
        .resource_scope(|world, mut history: Mut<CommandHistory>| history.undo(world));
    app.update();
}

// ---------------------------------------------------------------------------
// D-多实例更新 × apply — the PF1 red cell. Ignored on purpose: it asserts the
// desired behavior, which today's propagate path breaks (PF1 in
// loop/plans/t14-prefab-acceptance.md §三). Run it with
// `cargo test --test prefabs an_applied_baseline -- --ignored` to reproduce
// the red; T2's fix turns it green by deleting the attribute.
// ---------------------------------------------------------------------------
#[ignore = "PF1 red evidence: apply's propagate reload compares against the NEW \
           baseline, so the sibling's inherited value freezes as an authored \
           override and never follows the prefab again. Turned green in T2."]
#[test]
fn an_applied_baseline_reaches_every_sibling_instance() {
    let tmp = tempfile::tempdir().unwrap();
    let prefab_path = tmp.path().join("p.bsn");
    std::fs::write(&prefab_path, BASELINE_ZERO).unwrap();

    let mut app = make_app();
    // `a` stays at the baseline; `b` carries a placement offset on y so the
    // test can tell "follows the new baseline" from "frozen in place".
    jackdaw::prefab::operators::spawn_instance(app.world_mut(), &prefab_path, Vec3::ZERO);
    jackdaw::prefab::operators::spawn_instance(
        app.world_mut(),
        &prefab_path,
        Vec3::new(0.0, 2.0, 0.0),
    );
    app.update();
    let mut instances = isa_entities(&mut app);
    instances.sort_by_key(|entity| entity.index());
    assert_eq!(instances.len(), 2, "expected two instances");

    // The user edits `a` and applies it to the source: the baseline moves to
    // x=5 and every instance pointing at the file must follow.
    let instance_at = |app: &mut App, y: f32| -> Entity {
        app.world_mut()
            .query::<(Entity, &IsA, &Transform)>()
            .iter(app.world())
            .find(|(_, _, transform)| (transform.translation.y - y).abs() < 1e-4)
            .map(|(entity, _, _)| entity)
            .unwrap_or_else(|| panic!("no instance stands at y={y}"))
    };
    let a = instance_at(&mut app, 0.0);
    override_translation_x(&mut app, a, 5.0);
    let a_node = app
        .world()
        .resource::<SceneBsnAst>()
        .ast_for(a)
        .expect("a's node is in the live document");
    jackdaw::prefab::operators::apply_to_prefab_source(
        app.world_mut(),
        a_node,
        0,
        TRANSFORM_TYPE,
        "translation",
        BsnValue::Struct(jackdaw_bsn::BsnStructData {
            type_path: "glam::Vec3".to_string(),
            fields: jackdaw_bsn::BsnStructFields(vec![
                jackdaw_bsn::BsnField {
                    name: "x".to_string(),
                    value: BsnValue::Float(5.0),
                },
                jackdaw_bsn::BsnField {
                    name: "y".to_string(),
                    value: BsnValue::Float(0.0),
                },
                jackdaw_bsn::BsnField {
                    name: "z".to_string(),
                    value: BsnValue::Float(0.0),
                },
            ]),
        }),
    );
    // One tick drives the cache-epoch respawn; the respawn hands the
    // instances fresh ECS entities, so they are re-resolved by their
    // placement (a sits on the baseline, b carries the y=2 offset).
    app.update();
    app.update();
    let b = instance_at(&mut app, 2.0);

    let cache = app.world().resource::<jackdaw::prefab::PrefabAstCache>();
    let prefab_ast = cache.get(&prefab_path).expect("prefab cached");
    let root = prefab_ast
        .entities_with_component("jackdaw::prefab::components::Prefab")
        .first()
        .copied()
        .unwrap();
    let baseline_x = jackdaw_bsn::get_bsn_field(prefab_ast, root, TRANSFORM_TYPE, "translation.x");
    assert!(
        matches!(baseline_x, Some(BsnValue::Float(v)) if (v - 5.0).abs() < 1e-9),
        "the apply lands in the source baseline"
    );

    // The sibling follows the new baseline...
    assert!(
        (ecs_x(&mut app, b) - 5.0).abs() < 1e-4,
        "sibling instance b follows the applied baseline; got x={}",
        ecs_x(&mut app, b)
    );
    // ...keeps its own placement...
    assert_eq!(
        app.world().get::<Transform>(b).unwrap().translation.y,
        2.0,
        "b's own placement offset survives the propagate"
    );
    // ...and does not carry the stale inherited value as an authored override.
    let authored_x = doc_has_authored_x(&app, b);
    assert!(
        authored_x.is_none() || (authored_x.unwrap() - 5.0).abs() < 1e-9,
        "b's document must not freeze the old inherited x as an authored \
         override; got translation.x={authored_x:?}"
    );
}

// ---------------------------------------------------------------------------
// D-(Apply All 面) — `apply_all_overrides_to_source` had no direct test: a
// multi-field, multi-entity diff must land in the source baseline whole.
// ---------------------------------------------------------------------------
#[test]
fn apply_all_pushes_every_overridden_leaf_into_the_source() {
    let tmp = tempfile::tempdir().unwrap();
    let prefab_path = tmp.path().join("p.bsn");
    std::fs::write(&prefab_path, BASELINE_WITH_CHILD).unwrap();

    let mut app = make_app();
    jackdaw::prefab::operators::spawn_instance(app.world_mut(), &prefab_path, Vec3::ZERO);
    app.update();

    let instance = sole_isa_node(&app);
    let root_entity = entity_with_peid(&mut app, 0);
    let child_entity = entity_with_peid(&mut app, 1);
    override_translation_x(&mut app, root_entity, 9.0);
    override_translation_x(&mut app, child_entity, 99.0);

    jackdaw::prefab::operators::apply_all_overrides_to_source(app.world_mut(), instance);
    app.update();

    let cache = app.world().resource::<jackdaw::prefab::PrefabAstCache>();
    let prefab_ast = cache.get(&prefab_path).expect("prefab cached");
    let root = prefab_ast
        .entities_with_component("jackdaw::prefab::components::Prefab")
        .first()
        .copied()
        .unwrap();
    let root_x = jackdaw_bsn::get_bsn_field(prefab_ast, root, TRANSFORM_TYPE, "translation.x");
    assert!(
        matches!(root_x, Some(BsnValue::Float(v)) if (v - 9.0).abs() < 1e-9),
        "the instance root's override lands in the baseline; got {root_x:?}"
    );
    let child = prefab_ast
        .find_node_by_component_int(PEID_TYPE, 1)
        .expect("child in the prefab source");
    let child_x = jackdaw_bsn::get_bsn_field(prefab_ast, child, TRANSFORM_TYPE, "translation.x");
    assert!(
        matches!(child_x, Some(BsnValue::Float(v)) if (v - 99.0).abs() < 1e-9),
        "the inherited child's override lands in the baseline; got {child_x:?}"
    );
    // A field the instance never touched stays as authored in the source.
    let child_z = jackdaw_bsn::get_bsn_field(prefab_ast, child, TRANSFORM_TYPE, "translation.z");
    assert!(
        matches!(child_z, Some(BsnValue::Float(v)) if (v - 0.0).abs() < 1e-9),
        "apply-all only pushes overridden leaves; got translation.z={child_z:?}"
    );

    // Record-only note (PF5): the matching scene-side deltas are cleared by
    // top-level field name, so dotted leaf paths survive in the document
    // until the save-time sparsify collects them. Not asserted here — the
    // catalog carries it; this anchor pins the baseline-update face.
}

// ---------------------------------------------------------------------------
// E-undo — the revert family is snapshot-backed (`prefab.revert_field` declares
// `allows_undo`), but no test undid one: the override must come back whole.
// The respawn passes hand the instance a fresh ECS entity, so every phase
// re-resolves it from the document instead of holding a stale handle.
// ---------------------------------------------------------------------------
#[test]
fn undo_of_a_field_revert_restores_the_override() {
    let tmp = tempfile::tempdir().unwrap();
    let prefab_path = tmp.path().join("p.bsn");
    std::fs::write(&prefab_path, BASELINE_ZERO).unwrap();

    let mut app = util::editor_test_app();
    jackdaw::prefab::operators::spawn_instance(app.world_mut(), &prefab_path, Vec3::ZERO);
    app.update();
    let instance_entity = entity_with_peid(&mut app, 0);

    override_translation_x(&mut app, instance_entity, 7.0);
    assert!(
        (doc_x(&app, instance_entity) - 7.0).abs() < 1e-9,
        "the override is authored before the revert"
    );

    call(
        &mut app,
        "prefab.revert_field",
        &[
            ("entity", PropertyValue::Entity(instance_entity)),
            ("type_path", PropertyValue::from(TRANSFORM_TYPE)),
            ("field_path", PropertyValue::from("translation.x")),
        ],
    );
    app.update();
    app.update();
    let reverted = entity_with_peid(&mut app, 0);
    assert!(
        (ecs_x(&mut app, reverted) - 0.0).abs() < 1e-4,
        "the revert snaps the value back to the baseline"
    );

    undo_once(&mut app);
    app.update();
    app.update();
    let undone = entity_with_peid(&mut app, 0);
    assert!(
        (ecs_x(&mut app, undone) - 7.0).abs() < 1e-4,
        "undo restores the override in the ECS; got x={}",
        ecs_x(&mut app, undone)
    );
    assert!(
        (doc_x(&app, undone) - 7.0).abs() < 1e-9,
        "undo restores the override in the document"
    );
}

// ---------------------------------------------------------------------------
// G-undo — save-as-variant rewires the instance to the new file; undo must
// put it back on the original source, and the variant file stays on disk
// (the pack convention: file-level actions are not reached by undo).
// ---------------------------------------------------------------------------
#[test]
fn undo_of_save_as_variant_rewires_the_instance_back_and_keeps_the_file() {
    let tmp = tempfile::tempdir().unwrap();
    let base_path = tmp.path().join("base.bsn");
    std::fs::write(&base_path, BASELINE_ZERO).unwrap();
    let variant_path = tmp.path().join("variant.bsn");

    let mut app = util::editor_test_app();
    jackdaw::prefab::operators::spawn_instance(
        app.world_mut(),
        &base_path,
        Vec3::new(5.0, 0.0, 0.0),
    );
    app.update();
    let instance_entity = entity_with_peid(&mut app, 0);

    call(
        &mut app,
        "prefab.save_as_variant_entity",
        &[
            (
                "instance_root_entity",
                PropertyValue::Int(instance_entity.to_bits() as i64),
            ),
            (
                "target_path",
                PropertyValue::from(variant_path.to_string_lossy().into_owned()),
            ),
        ],
    );
    app.update();
    app.update();

    // The live document's IsA source is the truth the next save writes; the
    // snapshot passes can hand the instance a fresh ECS entity, so the node
    // is resolved fresh from the ECS entity each time.
    let doc_source = |app: &mut App| -> String {
        let entity = entity_with_peid(app, 0);
        let ast = app.world().resource::<SceneBsnAst>();
        let node = ast
            .ast_for(entity)
            .unwrap_or_else(|| panic!("the instance node is in the live document"));
        match jackdaw_bsn::get_bsn_field(ast, node, ISA_TYPE, "source") {
            Some(BsnValue::String(s)) => s,
            other => panic!("expected an IsA source string, got {other:?}"),
        }
    };
    assert!(variant_path.is_file(), "the variant file is written");
    assert_eq!(
        jackdaw::prefab::canonical_prefab_path(doc_source(&mut app)),
        jackdaw::prefab::canonical_prefab_path(&variant_path),
        "the instance is rewired to the variant"
    );

    undo_once(&mut app);
    app.update();
    app.update();
    assert_eq!(
        jackdaw::prefab::canonical_prefab_path(doc_source(&mut app)),
        jackdaw::prefab::canonical_prefab_path(&base_path),
        "undo puts the instance back on the original source"
    );
    assert!(
        variant_path.is_file(),
        "undo does not reach the disk: the variant file stays"
    );
    assert!(
        isa_entities(&mut app).len() == 1,
        "undo leaves exactly one instance standing"
    );
}

// ---------------------------------------------------------------------------
// E-(unpack/unbundle 面) T1 probe cell — an unpacked descendant that belongs
// to a *nested* instance records its `deleted` id on the inner instance node
// of the live document, which the save-time sparsify may or may not carry
// into the file. Decision 6: record the binary outcome, no verdict.
// ---------------------------------------------------------------------------
#[test]
fn probe_an_unpack_inside_a_nested_instance_persists_across_reopen() {
    use jackdaw::project::{ProjectConfig, ProjectRoot};

    let tmp = tempfile::tempdir().unwrap();
    let prefabs = tmp.path().join("assets/prefabs");
    std::fs::create_dir_all(&prefabs).unwrap();
    let inner_path = prefabs.join("inner.bsn");
    let outer_path = prefabs.join("outer.bsn");
    let scene_path = tmp.path().join("assets/world.bsn");

    // inner: root + a child the probe will unpack.
    std::fs::write(
        &inner_path,
        "#inner\n\
         jackdaw::prefab::components::Prefab\n\
         jackdaw::prefab::components::PrefabEntityId(0)\n\
         bevy_ecs::hierarchy::Children [\n\
             #knob\n\
             jackdaw::prefab::components::PrefabEntityId(7)\n\
             bevy_transform::components::transform::Transform {\n\
                 translation: glam::Vec3 { x: 3.0, y: 0.0, z: 0.0 },\n\
                 rotation: glam::Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 },\n\
                 scale: glam::Vec3 { x: 1.0, y: 1.0, z: 1.0 },\n\
             }\n\
         ]",
    )
    .unwrap();
    // outer: its own root plus a nested instance node of inner (the node
    // carries its own PrefabEntityId in outer's id space).
    std::fs::write(
        &outer_path,
        "#outer\n\
         jackdaw::prefab::components::Prefab\n\
         jackdaw::prefab::components::PrefabEntityId(0)\n\
         bevy_ecs::hierarchy::Children [\n\
             #nested\n\
             jackdaw::prefab::components::PrefabEntityId(5)\n\
             jackdaw::prefab::components::IsA { source: \"prefabs/inner.bsn\", deleted: [] }\n\
         ]",
    )
    .unwrap();
    std::fs::write(
        &scene_path,
        "#world\n\
         bevy_transform::components::transform::Transform\n\
         Children [\n\
             #inst\n\
             jackdaw::prefab::components::PrefabEntityId(0)\n\
             jackdaw::prefab::components::IsA { source: \"prefabs/outer.bsn\", deleted: [] }\n\
         ]",
    )
    .unwrap();

    // The editor app carries the workspace resources a save touches.
    let mut app = util::editor_test_app();
    app.world_mut().insert_resource(ProjectRoot::new(
        tmp.path().to_path_buf(),
        ProjectConfig::default(),
    ));
    jackdaw::scene_io::load_scene_from_file(app.world_mut(), &scene_path);
    app.update();
    app.update();

    // The knob materialized through two levels of prefab.
    let knob = app
        .world()
        .resource::<SceneBsnAst>()
        .find_node_by_component_int(PEID_TYPE, 7)
        .expect("the nested descendant materializes");
    let scene_root = {
        let mut ast = app.world_mut().resource_mut::<SceneBsnAst>();
        let node = ast.create_entity_node(Vec::new());
        ast.add_to_roots(node);
        node
    };
    jackdaw::prefab::operators::unpack_child(app.world_mut(), knob, scene_root);
    app.update();

    // Save the scene the way the editor does and reopen it in a fresh app.
    let scene_tab = {
        let mut scenes = app.world_mut().resource_mut::<jackdaw::scenes::Scenes>();
        let mut tab = jackdaw::scenes::SceneTab::new_untitled(scenes.tabs.len() as u32 + 1);
        tab.path = Some(scene_path.clone());
        scenes.push_tab(tab)
    };
    app.world_mut()
        .resource_mut::<jackdaw::scenes::Scenes>()
        .active = scene_tab;
    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the scene saves"
    );

    let mut reopened = make_app();
    reopened.world_mut().insert_resource(ProjectRoot::new(
        tmp.path().to_path_buf(),
        ProjectConfig::default(),
    ));
    jackdaw::scene_io::load_scene_from_file(reopened.world_mut(), &scene_path);
    reopened.update();
    reopened.update();

    let knobs = reopened
        .world_mut()
        .query::<(Entity, &Name)>()
        .iter(reopened.world())
        .filter(|(_, name)| name.as_str() == "knob")
        .count();
    let re_materialized = reopened
        .world()
        .resource::<SceneBsnAst>()
        .find_node_by_component_int(PEID_TYPE, 7)
        .is_some();
    // Where the survivor sits: its ancestor chain of names, so the record
    // says whether the unpacked child stayed a scene-level entity or was
    // folded back under the instance subtree.
    let chain = {
        let knob_entity = reopened
            .world_mut()
            .query::<(Entity, &Name)>()
            .iter(reopened.world())
            .find(|(_, name)| name.as_str() == "knob")
            .map(|(entity, _)| entity);
        let ast = reopened.world().resource::<SceneBsnAst>();
        let mut names: Vec<String> = Vec::new();
        if let Some(entity) = knob_entity
            && let Some(knob_key) = ast.ast_for(entity)
        {
            let mut cursor = Some(knob_key);
            while let Some(node) = cursor {
                match jackdaw_bsn::get_bsn_field(ast, node, "bevy_ecs::name::Name", "") {
                    Some(BsnValue::String(s)) => names.push(s),
                    _ => names.push("(anon)".to_string()),
                }
                cursor = ast.ast_parent_of(node);
            }
        }
        names.join(" < ")
    };

    // The binary record the probe cell owes the matrix (decision 6): the
    // unpacked knob survives the save/reopen boundary exactly once and the
    // nested instance does NOT regenerate its own copy — i.e. the inner
    // instance's `deleted` list is carried through the save. Pinned as a
    // regression guard, not a verdict: if a T2 change flips this, the
    // flip is the finding. The record line also lands in the archived
    // evidence (loop/reports/t14t1-e6-probe-record.log).
    println!(
        "E-6 probe record: knob_survived={} re_materialized={re_materialized} ancestor_chain=[{chain}]",
        knobs == 1
    );
    assert_eq!(
        knobs, 1,
        "the unpacked knob survives the reopen exactly once"
    );
    assert!(
        !re_materialized,
        "the nested instance does not re-materialize the unpacked id"
    );
}

// ---------------------------------------------------------------------------
// T05 × prefab — renaming the file an open prefab tab holds must retarget
// the tab, the cache entry it keys into, and every scene reference to it,
// and the file must stay watched afterwards (the Y8 face for prefabs).
// ---------------------------------------------------------------------------
#[test]
fn renaming_a_prefab_retargets_its_tab_cache_and_references() {
    use jackdaw::project::{ProjectConfig, ProjectRoot};
    use jackdaw::scenes::{SceneTab, Scenes, TabContent};

    let tmp = tempfile::tempdir().unwrap();
    // The project root is spelled the way an opened project is: canonical,
    // so the rename's path handling and the tab's agree (a raw macOS tempdir
    // path goes through a symlink the retarget match would trip on).
    let root = dunce::canonicalize(tmp.path()).unwrap();
    let prefabs = root.join("assets/prefabs");
    std::fs::create_dir_all(&prefabs).unwrap();
    let prefab_path = prefabs.join("p.bsn");
    std::fs::write(&prefab_path, BASELINE_WITH_CHILD).unwrap();
    let scene_path = root.join("assets/world.bsn");
    std::fs::write(
        &scene_path,
        "#world\n\
         bevy_transform::components::transform::Transform\n\
         Children [\n\
             #inst\n\
             jackdaw::prefab::components::PrefabEntityId(0)\n\
             jackdaw::prefab::components::IsA { source: \"prefabs/p.bsn\", deleted: [] }\n\
         ]",
    )
    .unwrap();

    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(ProjectRoot::new(root.clone(), ProjectConfig::default()));
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    jackdaw::asset_index::rescan_asset_index(app.world_mut());

    let renamed_path = prefabs.join("rock.bsn");
    let canonical_old = jackdaw::prefab::canonical_prefab_path(&prefab_path);

    jackdaw::boot_ops::run_op_clause(app.world_mut(), "scene.open path=assets/world.bsn")
        .expect("the scene opens")
        .assert_finished();
    util::settle_scene_load(&mut app);
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(8);
    while std::time::Instant::now() < deadline && entity_named(&mut app, "child").is_none() {
        app.update();
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    assert!(
        entity_named(&mut app, "child").is_some(),
        "the instance inherited the prefab child before the rename"
    );

    // A prefab tab standing on the file, its document already in the cache.
    // The scene stays the active tab — the way a rename from the project
    // window usually happens — and the background prefab tab must follow.
    let prefab_tab = {
        let mut scenes = app.world_mut().resource_mut::<Scenes>();
        let mut tab = SceneTab::new_untitled(scenes.tabs.len() as u32 + 1);
        tab.path = Some(prefab_path.clone());
        tab.kind = jackdaw::scenes::TabKind::Prefab;
        tab.content = TabContent::Prefab(canonical_old.clone());
        scenes.push_tab(tab)
    };
    assert!(
        app.world()
            .resource::<jackdaw::prefab::PrefabAstCache>()
            .get_canonical(&canonical_old)
            .is_some(),
        "the open put the prefab in the cache"
    );

    jackdaw::boot_ops::run_op_clause(
        app.world_mut(),
        "file.rename path=assets/prefabs/p.bsn name=rock.bsn",
    )
    .expect("the rename runs")
    .assert_finished();
    app.update();
    // Computed after the move, so the canonical form is the one the file
    // answers to now (the symlinked tempdir resolves only once it exists).
    let canonical_new = jackdaw::prefab::canonical_prefab_path(&renamed_path);

    // The tab, the cache entry and the live reference all moved.
    let retargeted = {
        let scenes = app.world().resource::<Scenes>();
        matches!(
            &scenes.tabs[prefab_tab].content,
            TabContent::Prefab(path) if jackdaw::prefab::canonical_prefab_path(path) == canonical_new
        )
    };
    assert!(retargeted, "the prefab tab saves through the new path");
    {
        let cache = app.world().resource::<jackdaw::prefab::PrefabAstCache>();
        assert!(
            cache.get_canonical(&canonical_new).is_some()
                && cache.get_canonical(&canonical_old).is_none(),
            "the cache entry moves with the file"
        );
    }
    {
        // The authoritative face: the scene file on disk spells the new
        // path (the rewrite pass reaches the file the way a later open
        // would read it).
        let on_disk = std::fs::read_to_string(root.join("assets/world.bsn")).unwrap();
        assert!(
            on_disk.contains("prefabs/rock.bsn") && !on_disk.contains("prefabs/p.bsn"),
            "the rewritten scene file spells the new prefab path; got:\n{on_disk}"
        );
    }
    // Record-only note (PF9, second face): the OPEN scene still spells the
    // old path — its instances stop following the renamed file in-session,
    // and its next save drags the stale spelling back over the rewritten
    // file (the ignored red cell below pins that face).
}

/// PF9 red evidence (loop/plans/t14-prefab-acceptance.md, T1 finding): the
/// rename rewrites the scene *file* on disk, but the OPEN scene's live
/// document keeps spelling the old path, and its next save drags the stale
/// reference back over the rewritten file — the instance breaks on the next
/// open. Ignored on purpose; turned green in T2 alongside PF1/PF2.
#[ignore = "PF9 red evidence: a rename retargets tabs standing on the file but \
           not the open scenes referencing it; their next save writes the old \
           prefab path back over the rewritten file."]
#[test]
fn a_scene_save_after_a_prefab_rename_keeps_the_new_spelling() {
    use jackdaw::project::{ProjectConfig, ProjectRoot};
    use jackdaw::scenes::{SceneTab, Scenes, TabContent};

    let tmp = tempfile::tempdir().unwrap();
    let root = dunce::canonicalize(tmp.path()).unwrap();
    let prefabs = root.join("assets/prefabs");
    std::fs::create_dir_all(&prefabs).unwrap();
    let prefab_path = prefabs.join("p.bsn");
    std::fs::write(&prefab_path, BASELINE_WITH_CHILD).unwrap();
    let scene_path = root.join("assets/world.bsn");
    std::fs::write(
        &scene_path,
        "#world\n\
         bevy_transform::components::transform::Transform\n\
         Children [\n\
             #inst\n\
             jackdaw::prefab::components::PrefabEntityId(0)\n\
             jackdaw::prefab::components::IsA { source: \"prefabs/p.bsn\", deleted: [] }\n\
         ]",
    )
    .unwrap();

    let mut app = util::editor_test_app();
    app.world_mut()
        .insert_resource(ProjectRoot::new(root.clone(), ProjectConfig::default()));
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app.update();
    jackdaw::asset_index::rescan_asset_index(app.world_mut());

    jackdaw::boot_ops::run_op_clause(app.world_mut(), "scene.open path=assets/world.bsn")
        .expect("the scene opens")
        .assert_finished();
    util::settle_scene_load(&mut app);
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(8);
    while std::time::Instant::now() < deadline && entity_named(&mut app, "child").is_none() {
        app.update();
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    assert!(
        entity_named(&mut app, "child").is_some(),
        "the instance is in"
    );

    // A background prefab tab, the way a user often has one.
    let canonical_old = jackdaw::prefab::canonical_prefab_path(&prefab_path);
    {
        let mut scenes = app.world_mut().resource_mut::<Scenes>();
        let mut tab = SceneTab::new_untitled(scenes.tabs.len() as u32 + 1);
        tab.path = Some(prefab_path.clone());
        tab.kind = jackdaw::scenes::TabKind::Prefab;
        tab.content = TabContent::Prefab(canonical_old);
        scenes.push_tab(tab);
    }

    jackdaw::boot_ops::run_op_clause(
        app.world_mut(),
        "file.rename path=assets/prefabs/p.bsn name=rock.bsn",
    )
    .expect("the rename runs")
    .assert_finished();
    app.update();

    assert!(
        jackdaw::scene_io::save_scene(app.world_mut()),
        "the open scene saves"
    );
    let on_disk = std::fs::read_to_string(root.join("assets/world.bsn")).unwrap();
    assert!(
        on_disk.contains("prefabs/rock.bsn") && !on_disk.contains("prefabs/p.bsn"),
        "a save of the open scene keeps the new spelling; got:\n{on_disk}"
    );
}

fn entity_named(app: &mut App, name: &str) -> Option<Entity> {
    app.world_mut()
        .query::<(Entity, &Name)>()
        .iter(app.world())
        .find(|(_, found)| found.as_str() == name)
        .map(|(entity, _)| entity)
}
