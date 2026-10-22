//! The visibility filter's rules: a deny over an allow over a game type
//! over the engine allowlist, and what enumeration makes of a world.

use bevy::prelude::*;
use bevy::reflect::TypePath;
use jackdaw::inspector::resource_panel::{
    ResourcePanelVisibility, default_resource_panel_visibility, enumerate_visible_resources,
};

/// A game's own resource: not bevy, not jackdaw, so it is visible with no
/// configuration at all.
#[derive(Resource, Reflect, Default, Debug)]
#[reflect(Resource, Default)]
struct TestScore {
    points: u32,
}

#[test]
fn a_game_type_is_visible_without_any_configuration() {
    let vis = ResourcePanelVisibility::default();
    assert!(vis.visible("my_game::Score"));
    assert!(vis.visible("some_crate::deep::Wallet"));
}

#[test]
fn an_allow_admits_what_the_rules_would_otherwise_hide() {
    let mut vis = ResourcePanelVisibility::default();
    assert!(!vis.visible("bevy_extra::knob::Knob"));
    vis.allow_path("bevy_extra::knob::Knob");
    assert!(vis.visible("bevy_extra::knob::Knob"));
    vis.allow_prefix("bevy_extra::dial::");
    assert!(vis.visible("bevy_extra::dial::Dial"));
}

#[test]
fn a_deny_suppresses_even_an_allow_and_a_game_type() {
    let mut vis = ResourcePanelVisibility::default();
    vis.allow_path("my_game::Noisy");
    vis.allow_prefix("my_game::");
    assert!(vis.visible("my_game::Noisy"));
    vis.deny_path("my_game::Noisy");
    assert!(!vis.visible("my_game::Noisy"), "a deny outranks an allow");

    vis.deny_prefix("my_game::internal::");
    assert!(
        !vis.visible("my_game::internal::Cache"),
        "a deny prefix outranks the game-type rule"
    );
    assert!(vis.visible("my_game::Score"));
}

#[test]
fn the_default_visibility_admits_the_engine_allowlist_and_hides_the_rest() {
    let vis = default_resource_panel_visibility();
    for path in [
        "bevy_light::ambient_light::GlobalAmbientLight",
        "bevy_camera::clear_color::ClearColor",
        "bevy_gizmos::config::GizmoConfigStore",
        "bevy_time::time::Time<bevy_time::virt::Virtual>",
        "bevy_time::time::Time<bevy_time::fixed::Fixed>",
    ] {
        assert!(vis.visible(path), "{path} should be visible");
    }
    for path in [
        "bevy_time::time::Time<bevy_time::real::Real>",
        "bevy_time::time::Time<()>",
        "bevy_asset::assets::Assets<bevy_scene::Scene>",
        "bevy_ecs::schedule::Schedule",
        "bevy_render::render_resource::WgpuWrapper",
        "bevy_window::Window",
        "jackdaw::commands::CommandHistory",
        "jackdaw_terrain::TerrainDataStore",
    ] {
        assert!(!vis.visible(path), "{path} should stay hidden");
    }
}

#[test]
fn enumeration_lists_visible_resources_only_and_groups_game_first() {
    let mut world = World::new();
    world.insert_resource(TestScore { points: 7 });
    world.init_resource::<bevy::time::Time<bevy::time::Virtual>>();
    world.init_resource::<bevy::time::Time<bevy::time::Real>>();

    let mut registry = bevy::reflect::TypeRegistry::new();
    registry.register::<TestScore>();
    registry.register::<bevy::time::Time<bevy::time::Virtual>>();
    registry.register::<bevy::time::Time<bevy::time::Real>>();

    let rows = enumerate_visible_resources(&world, &registry, &default_resource_panel_visibility());
    let paths: Vec<&str> = rows.iter().map(|row| row.type_path.as_str()).collect();

    // The allowlist's spelling of the generic clocks matches what the
    // registry actually reports, which is the one thing a string
    // allowlist can silently get wrong.
    assert!(
        paths.contains(&"bevy_time::time::Time<bevy_time::virt::Virtual>"),
        "Time<Virtual> is listed: {paths:?}"
    );
    assert!(
        paths.contains(&TestScore::type_path()),
        "the game resource is listed: {paths:?}"
    );
    assert!(
        !paths.iter().any(|path| path.contains("real::Real")),
        "Time<Real> is denied: {paths:?}"
    );

    // Game rows group first, and every row names a live resource entity.
    assert_eq!(rows[0].type_path, TestScore::type_path());
    assert!(
        rows[0].group.is_empty(),
        "the game group is the Game section"
    );
    for row in &rows {
        assert!(
            world.get_entity(row.entity).is_ok(),
            "{} names a live entity",
            row.type_path
        );
    }
}
