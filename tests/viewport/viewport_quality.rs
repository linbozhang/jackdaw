//! The viewport settings applied: the editor's cameras, shadow maps, detail
//! and level-of-detail distances follow them, and the scene does not.

use crate::util;
use crate::util::OperatorResultExt as _;

use bevy::anti_alias::contrast_adaptive_sharpening::ContrastAdaptiveSharpening;
use bevy::anti_alias::fxaa::Fxaa;
use bevy::anti_alias::smaa::Smaa;
use bevy::anti_alias::taa::TemporalAntiAliasing;
use bevy::core_pipeline::prepass::{MotionVectorPrepass, NormalPrepass};
use bevy::light::{DirectionalLightShadowMap, PointLightShadowMap};
use bevy::pbr::{
    DistanceFog, ScreenSpaceAmbientOcclusion, ScreenSpaceAmbientOcclusionQualityLevel,
};
use bevy::prelude::*;
use bevy::render::camera::{MipBias, TemporalJitter};
use bevy::render::view::Msaa;
use bevy::ui::widget::ViewportNode;
use bevy::window::{PrimaryWindow, WindowResolution};
use jackdaw::viewport::MainViewportCamera;
use jackdaw::viewport_quality::ShadowCasters;
use jackdaw::viewport_settings::ViewportSettingsFile;
use jackdaw_surface::EnvironmentOptOut;

fn settle(app: &mut App) {
    for _ in 0..8 {
        app.update();
    }
}

fn run(app: &mut App, clause: &str) {
    jackdaw::boot_ops::run_op_clause(app.world_mut(), clause)
        .unwrap_or_else(|err| panic!("{clause}: {err}"))
        .assert_finished();
    settle(app);
}

/// An editor with one viewport panel in a 1280x720 window, keeping its
/// viewport settings in `dir`.
fn app_with_viewport(dir: &std::path::Path) -> App {
    let mut app = util::editor_test_app();
    {
        let mut windows = app
            .world_mut()
            .query_filtered::<&mut Window, With<PrimaryWindow>>();
        let mut window = windows
            .single_mut(app.world_mut())
            .expect("headless apps still have a primary window");
        window.resolution = WindowResolution::new(1280, 720);
    }
    app.world_mut().resource_mut::<ViewportSettingsFile>().path = Some(dir.join("viewport.json"));
    let root = app
        .world_mut()
        .spawn(Node {
            width: percent(100),
            height: percent(100),
            ..default()
        })
        .id();
    jackdaw::viewport::build_viewport_panel(app.world_mut(), root);
    settle(&mut app);
    app
}

fn camera(app: &mut App) -> Entity {
    app.world_mut()
        .query_filtered::<Entity, With<MainViewportCamera>>()
        .single(app.world())
        .expect("one viewport camera")
}

fn has<C: Component>(app: &mut App) -> bool {
    let camera = camera(app);
    app.world().get::<C>(camera).is_some()
}

#[test]
fn the_low_preset_turns_the_viewport_down() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = app_with_viewport(dir.path());
    assert!(
        has::<Fxaa>(&mut app),
        "the default High preset smooths with FXAA"
    );

    run(&mut app, "viewport.quality.preset preset=low");

    assert!(!has::<Fxaa>(&mut app) && !has::<TemporalAntiAliasing>(&mut app));
    let camera = camera(&mut app);
    assert_eq!(
        app.world().get::<EnvironmentOptOut>(camera).copied(),
        Some(EnvironmentOptOut {
            fog: true,
            ambient: false,
            post_processing: true,
            bloom: true,
            antialiasing: true,
        })
    );
    assert_eq!(
        *app.world().resource::<ShadowCasters>(),
        ShadowCasters {
            sun: true,
            point: false
        }
    );
    assert_eq!(
        app.world().resource::<DirectionalLightShadowMap>().size,
        512
    );
    assert_eq!(app.world().resource::<PointLightShadowMap>().size, 256);
    assert_eq!(
        app.world()
            .resource::<jackdaw_terrain::render::DetailSettings>()
            .cull_scale,
        0.4
    );
    assert_eq!(
        app.world().resource::<jackdaw_runtime::LodQuality>().bias,
        0.5
    );
}

#[test]
fn the_full_preset_adds_taa_and_ambient_occlusion_and_high_takes_them_off() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = app_with_viewport(dir.path());

    run(&mut app, "viewport.quality.preset preset=full");
    assert!(has::<TemporalAntiAliasing>(&mut app));
    assert!(has::<ScreenSpaceAmbientOcclusion>(&mut app));
    assert!(!has::<Fxaa>(&mut app));

    run(&mut app, "viewport.quality.preset preset=high");
    assert!(!has::<TemporalAntiAliasing>(&mut app));
    assert!(!has::<ScreenSpaceAmbientOcclusion>(&mut app));
    assert!(
        !has::<MotionVectorPrepass>(&mut app) && !has::<NormalPrepass>(&mut app),
        "the prepasses the effects brought go with them"
    );
    assert!(has::<Fxaa>(&mut app));
}

#[test]
fn the_scenes_fog_leaves_the_viewport_while_fog_is_hidden() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = app_with_viewport(dir.path());
    run(&mut app, "entity.add.group name=Sky");
    run(
        &mut app,
        "component.add name=Sky type_path=jackdaw_scene_types::environment::Environment",
    );
    run(&mut app, "environment.set fog.mode=Linear");
    assert!(
        has::<DistanceFog>(&mut app),
        "the scene's fog dresses the viewport"
    );

    run(&mut app, "viewport.show.toggle flag=fog on=false");
    assert!(
        !has::<DistanceFog>(&mut app),
        "hidden, the viewport draws none"
    );

    run(&mut app, "viewport.show.toggle flag=fog on=true");
    assert!(
        has::<DistanceFog>(&mut app),
        "shown again, the scene's fog is back"
    );
}

#[test]
fn each_anti_aliasing_choice_dresses_the_viewport_camera_alone() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = app_with_viewport(dir.path());

    run(&mut app, "viewport.quality.set anti_aliasing=off");
    assert!(
        !has::<Fxaa>(&mut app) && !has::<Smaa>(&mut app) && !has::<TemporalAntiAliasing>(&mut app)
    );

    run(&mut app, "viewport.quality.set anti_aliasing=smaa");
    assert!(has::<Smaa>(&mut app));
    assert!(!has::<Fxaa>(&mut app) && !has::<TemporalAntiAliasing>(&mut app));
    assert!(
        !has::<TemporalJitter>(&mut app) && !has::<MipBias>(&mut app),
        "smaa leaves taa's jitter and mip bias behind"
    );

    run(&mut app, "viewport.quality.set anti_aliasing=taa");
    assert!(has::<TemporalAntiAliasing>(&mut app));
    assert!(!has::<Smaa>(&mut app) && !has::<Fxaa>(&mut app));
    assert!(has::<TemporalJitter>(&mut app) && has::<MipBias>(&mut app));

    run(&mut app, "viewport.quality.set anti_aliasing=fxaa");
    assert!(has::<Fxaa>(&mut app));
    assert!(
        !has::<TemporalAntiAliasing>(&mut app)
            && !has::<TemporalJitter>(&mut app)
            && !has::<MipBias>(&mut app)
            && !has::<MotionVectorPrepass>(&mut app),
        "taa and the prepass it brought go together"
    );
}

#[test]
fn taa_and_smaa_hold_multisampling_off() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = app_with_viewport(dir.path());
    for choice in ["smaa", "taa"] {
        run(
            &mut app,
            &format!("viewport.quality.set anti_aliasing={choice}"),
        );
        let camera = camera(&mut app);
        assert_eq!(
            app.world().get::<Msaa>(camera),
            Some(&Msaa::Off),
            "{choice} smooths one sample per pixel"
        );
    }
}

#[test]
fn the_ssao_quality_reaches_the_camera_and_off_takes_the_prepass_back() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = app_with_viewport(dir.path());
    let camera = camera(&mut app);
    let quality_level = |app: &App| {
        app.world()
            .get::<ScreenSpaceAmbientOcclusion>(camera)
            .map(|ssao| ssao.quality_level)
    };

    run(&mut app, "viewport.ssao.set on=true quality=ultra");
    assert_eq!(
        quality_level(&app),
        Some(ScreenSpaceAmbientOcclusionQualityLevel::Ultra)
    );
    assert!(has::<NormalPrepass>(&mut app), "ssao needs normal vectors");

    run(&mut app, "viewport.ssao.set quality=low");
    assert_eq!(
        quality_level(&app),
        Some(ScreenSpaceAmbientOcclusionQualityLevel::Low)
    );

    run(&mut app, "viewport.ssao.set on=false");
    assert!(
        !has::<ScreenSpaceAmbientOcclusion>(&mut app) && !has::<NormalPrepass>(&mut app),
        "off, the effect and the prepass it brought go together"
    );
}

#[test]
fn sharpening_dresses_the_viewport_camera_with_its_strength() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = app_with_viewport(dir.path());

    let cas = |app: &mut App| {
        let camera = camera(app);
        app.world()
            .get::<ContrastAdaptiveSharpening>(camera)
            .cloned()
    };

    run(&mut app, "viewport.sharpen.set on=true strength=0.8");
    let sharpening = cas(&mut app).expect("sharpening dresses the camera");
    assert!(sharpening.enabled);
    assert_eq!(sharpening.sharpening_strength, 0.8);

    run(&mut app, "viewport.sharpen.set strength=0.25");
    let sharpening = cas(&mut app).expect("the strength changes in place");
    assert_eq!(sharpening.sharpening_strength, 0.25);

    run(&mut app, "viewport.sharpen.set on=false");
    assert!(!has::<ContrastAdaptiveSharpening>(&mut app));
}

#[test]
fn half_render_scale_draws_the_viewport_at_half_its_size() {
    let dir = tempfile::tempdir().unwrap();
    let mut app = app_with_viewport(dir.path());
    run(&mut app, "viewport.quality.set render_scale=50");

    let (viewport, node) = {
        let mut viewports = app.world_mut().query::<(&ViewportNode, &ComputedNode)>();
        let (viewport, node) = viewports.single(app.world()).expect("one viewport node");
        (viewport.camera.expect("a camera"), node.size())
    };
    let target = app
        .world()
        .get::<bevy::camera::RenderTarget>(viewport)
        .and_then(|target| target.as_image())
        .expect("the viewport renders to an image")
        .clone();
    let size = app
        .world()
        .resource::<Assets<Image>>()
        .get(&target)
        .expect("the image is loaded")
        .size();
    assert!(node.x > 100.0, "the viewport is laid out: {node}");
    assert_eq!(size, (node * 0.5).round().as_uvec2());
}
