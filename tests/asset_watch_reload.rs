//! The watcher-driven reload chain, end to end over real filesystem events
//! (T18 plan §四-T1 anchor 1).
//!
//! Every other reload anchor calls the walk or the reload directly; this one
//! stands the real notify watcher, writes the file the way an external tool
//! would, and lets the chain run: watcher event → `AssetScanPending` → walk →
//! `reload_in_place`, which is the "换值不换柄" protocol the Project window
//! and the thumbnails stand on. It is the anchor the A6 discipline was written
//! for, so it keeps its own tempdir, drives nothing but its own file, and
//! holds a ten-second budget before declaring the chain broken.
//!
//! ```text
//! cargo test --test asset_watch_reload
//! ```

use std::path::Path;
use std::time::{Duration, Instant, SystemTime};

use bevy::asset::AssetPlugin;
use bevy::prelude::*;
use jackdaw::asset_index;
use jackdaw::project::ProjectRoot;

use jackdaw_api::prelude::{AssetKind, AssetKinds};
use jackdaw_bsn::{with_asset_header, write_document_text};

const MATERIAL_TYPE: &str = "bevy_pbr::pbr_material::StandardMaterial";

/// The grass material as a file: `value` is a field the reload has to change.
fn grass_document(value: f32) -> String {
    with_asset_header(
        MATERIAL_TYPE,
        &format!(
            "#grass\n\
             {MATERIAL_TYPE} {{\n    perceptual_roughness: {value}\n}}\n"
        ),
    )
}

/// The indexing arrangement standing alone: the plugin a project open runs,
/// pointed at a throwaway project, in the Editor state its systems run in.
fn index_app(root: &Path) -> App {
    let mut app = App::new();
    app.add_plugins((
        bevy::app::TaskPoolPlugin::default(),
        AssetPlugin::default(),
        // States, so the asset index's systems can run in the Editor state.
        bevy::state::app::StatesPlugin,
        asset_index::plugin,
    ));
    app.init_asset::<Image>();
    app.init_asset::<StandardMaterial>();
    app.register_asset_reflect::<Image>();
    app.register_asset_reflect::<StandardMaterial>();
    app.register_type::<StandardMaterial>();
    app.init_resource::<jackdaw::asset_catalog::AssetCatalog>();
    app.init_resource::<jackdaw::material_assets::MaterialRegistry>();
    app.insert_resource(ProjectRoot {
        root: root.to_path_buf(),
        config: jackdaw::project::ProjectConfig::default(),
    });
    let mut kinds = AssetKinds::default();
    kinds.register(AssetKind::compiled(
        jackdaw::definition_assets::MATERIAL_KIND,
        "Material",
        MATERIAL_TYPE,
    ));
    app.insert_resource(kinds);
    app.init_state::<jackdaw::AppState>();
    app.world_mut()
        .resource_mut::<NextState<jackdaw::AppState>>()
        .set(jackdaw::AppState::Editor);
    app
}

/// The mtime the file at `path` carries now, for assertions about staleness.
fn mtime_of(path: &Path) -> SystemTime {
    std::fs::metadata(path)
        .and_then(|meta| meta.modified())
        .expect("the file's mtime is read")
}

/// An external write the watcher must see: the document is replaced in place,
/// with enough of a pause that the mtime moves.
fn rewrite_external(path: &Path, value: f32) {
    std::thread::sleep(Duration::from_millis(50));
    write_document_text(path, &grass_document(value)).expect("the file is rewritten");
}

#[test]
fn an_external_write_reloads_into_the_handle_references_hold() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let assets = tmp.path().join("assets");
    let materials = assets.join("materials");
    std::fs::create_dir_all(&materials).expect("the assets tree is made");
    let grass = materials.join("grass.bsn");
    write_document_text(&grass, &grass_document(0.2)).expect("the material is written");

    let mut app = index_app(tmp.path());

    // The project opens: the walk indexes the file and the watcher starts.
    let deadline = Instant::now() + Duration::from_secs(5);
    while Instant::now() < deadline {
        app.update();
        let indexed = app
            .world()
            .get_resource::<asset_index::AssetIndex>()
            .and_then(|index| index.get(Path::new("materials/grass.bsn")).cloned());
        if indexed.is_some() {
            break;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
    let entry = app
        .world()
        .get_resource::<asset_index::AssetIndex>()
        .and_then(|index| index.get(Path::new("materials/grass.bsn")).cloned())
        .expect("the opened project's walk indexed the material");
    let handle = entry
        .value
        .handle()
        .cloned()
        .expect("the material is held as a handle");
    assert_eq!(
        entry.mtime,
        mtime_of(&grass),
        "indexed at the mtime it read"
    );

    // An external tool rewrites the file in place.
    rewrite_external(&grass, 0.31);

    // Watcher → pending → walk → reload_in_place, inside a ten-second budget.
    // One assertion owns the leg: the *handle* the editor hands out stays the
    // same while the value it carries follows the file.
    let deadline = Instant::now() + Duration::from_secs(10);
    let mut outcome = None;
    while Instant::now() < deadline {
        app.update();
        let entry = app
            .world()
            .get_resource::<asset_index::AssetIndex>()
            .and_then(|index| index.get(Path::new("materials/grass.bsn")).cloned());
        if let Some(entry) = entry {
            let same_handle = entry.value.handle().map(UntypedHandle::id) == Some(handle.id());
            let fresh_value = {
                let materials = app.world().resource::<Assets<StandardMaterial>>();
                entry
                    .value
                    .handle()
                    .and_then(|held| materials.get(&held.clone().typed::<StandardMaterial>()))
                    .map(|material| material.perceptual_roughness)
            };
            if same_handle && fresh_value == Some(0.31) {
                outcome = Some(fresh_value);
                break;
            }
        }
        std::thread::sleep(Duration::from_millis(100));
    }

    assert_eq!(
        outcome,
        Some(Some(0.31)),
        "the external write reached the editor: the same handle now carries the file's value"
    );
    let entry = app
        .world()
        .resource::<asset_index::AssetIndex>()
        .get(Path::new("materials/grass.bsn"))
        .expect("still indexed");
    assert_eq!(
        entry.mtime,
        mtime_of(&grass),
        "the walk landed at the file's new mtime"
    );
}
