//! The image formats the import UI invites, probed and pinned (T18 plan
//! §四-T1 probe 1, AR2).
//!
//! `asset_ingest::classify` and the asset rows' pick filters both name
//! `.jpg`/`.jpeg`, so the import face invites them; the decode half lives
//! behind bevy's `jpeg` feature, which the workspace did not enable — a
//! dropped jpg decoded nothing and the loader refused the extension
//! (`InvalidImageExtension("jpg")`). The decode chain here is real (a
//! fixture jpg through the real `AssetServer` and `ImageLoader`), so the
//! feature going missing again fails the first test, and the second pins
//! the manifest line the fix turned on so a drift in either direction is
//! caught.
//!
//! ```text
//! cargo test --test asset_formats
//! ```

use std::path::PathBuf;
use std::time::{Duration, Instant};

use bevy::asset::{AssetPlugin, LoadState};
use bevy::prelude::*;

/// Where the workspace manifest sits, so the feature line is read from the
/// build that is running this test rather than from a copy.
fn workspace_manifest() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml")
}

/// A minimal app whose asset server reads a throwaway directory, the
/// arrangement the editor's `AssetPlugin` is in (`launch.rs` sets only
/// `file_path`).
fn asset_app(assets_dir: &std::path::Path) -> App {
    let mut app = App::new();
    app.add_plugins((
        bevy::app::TaskPoolPlugin::default(),
        AssetPlugin {
            file_path: assets_dir.to_string_lossy().into_owned(),
            ..default()
        },
        // Registers the image loader; the loader's extension list is what the
        // `jpeg` feature opens and closes.
        bevy::image::ImagePlugin::default(),
    ));
    app.register_asset_loader(bevy::image::ImageLoader::new(
        bevy::image::CompressedImageFormats::NONE,
    ));
    app.init_asset::<Image>();
    app
}

/// The jpg the import UI invites, copied into a throwaway assets root.
fn copied_probe(root: &std::path::Path) -> PathBuf {
    let source =
        PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/images/probe_1x1.jpg");
    let dir = root.join("pictures");
    std::fs::create_dir_all(&dir).expect("the assets folder is made");
    let destination = dir.join("probe.jpg");
    std::fs::copy(&source, &destination).expect("the probe jpg is copied");
    destination
}

/// A jpg the import face invites decodes: `classify` and the pick filters
/// name `.jpg`/`.jpeg`, so the loader the server holds must accept the
/// extension and produce an image. Red on a workspace whose bevy selection
/// lost the `jpeg` feature: the loader refuses the extension
/// (`InvalidImageExtension`), and the load fails.
#[test]
fn a_jpg_the_import_ui_invites_decodes() {
    let tmp = tempfile::tempdir().expect("tempdir");
    let _destination = copied_probe(tmp.path());
    let mut app = asset_app(tmp.path());

    let server = app.world().resource::<AssetServer>().clone();
    let handle = server.load::<Image>("pictures/probe.jpg");

    // Filesystem and decode latency vary; a generous deadline rather than a
    // fixed frame count.
    let deadline = Instant::now() + Duration::from_secs(10);
    let mut state = None;
    while Instant::now() < deadline {
        app.update();
        match server.load_state(handle.id()) {
            LoadState::NotLoaded | LoadState::Loading => {}
            resolved => {
                state = Some(resolved);
                break;
            }
        }
        std::thread::sleep(Duration::from_millis(20));
    }

    let state = state.expect("the jpg load resolves inside the deadline");
    assert!(
        state.is_loaded(),
        "a jpg the import UI invites must decode; got {state:?} -- \
         if this reads as an invalid image extension, the workspace bevy selection lost the \
         `jpeg` feature"
    );
    let image = app
        .world()
        .resource::<Assets<Image>>()
        .get(&handle)
        .expect("the decoded image is in the store");
    assert_eq!(
        image.size(),
        bevy::math::UVec2::new(1, 1),
        "the probe is 1x1"
    );
}

/// The manifest teaches the decode feature (T18 decision 4-A): the editor
/// workspace's bevy selection names `jpeg`, because `classify` and the pick
/// filters invite jpg imports and the decode half has to answer them. The
/// template game does not (the template ships no jpg assets), so this pins
/// the editor side only.
#[test]
fn the_workspace_selection_teaches_the_jpeg_feature() {
    let manifest = std::fs::read_to_string(workspace_manifest()).expect("the manifest is read");
    let bevy_block = manifest
        .split("bevy = { git =")
        .nth(1)
        .and_then(|rest| rest.split("] }").next())
        .expect("the bevy dependency block is in the manifest");
    // A feature line is a bare `"jpeg",` entry; a line a comment leads is a
    // remark, not a selection.
    let listed = bevy_block
        .lines()
        .any(|line| line.trim_start().starts_with("\"jpeg\","));
    assert!(
        listed,
        "the workspace bevy features must enable `jpeg` -- the import UI invites .jpg and the \
         decode feature answers it; got block:\nbevy = {{ git ={bevy_block}] }}"
    );
}
