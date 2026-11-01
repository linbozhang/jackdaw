//! The headless App-level prototype of the T22 acceptance triad (matrix cell
//! M10's three assertions, kernel prototype round): a bevy App with no
//! renderer drives a 2D player probe body through the tile-grid kernel. The
//! real-machine legs (direct run / PIE / staged export) are T2/T3 work; this
//! file pins the wiring shape the game-side template module will quote —
//! the level is a resource, one system integrates forces, one resolves, one
//! censuses triggers, in one chained schedule.
//!
//! Ground holds / walls block / triggers fire, all asserted on ECS state the
//! way a game would read it (bevy-native, no editor involved).

use bevy::prelude::*;
use jackdaw_tilemap_collision::*;

const CELL: f32 = 32.0;
const DT: f32 = 1.0 / 60.0;
const GRAVITY: f32 = 900.0;
const WALK: f32 = 96.0;

/// The level as a resource: the T2 wiring fills this from the scene's
/// tilemap layer components (mode per layer) instead of this test's builder.
#[derive(Resource)]
struct Level(TileGrid);

/// The held walk input, in world units per second. `0.0` stands still.
#[derive(Resource)]
struct WalkInput(f32);

/// The 2D player probe body.
#[derive(Component)]
struct PlayerProbe(Probe);

/// Frames the body currently overlaps a trigger cell, and how many frames
/// it has been inside at least one — the prototype of the flip the real
/// game turns into an event or a counter.
#[derive(Resource, Default)]
struct TriggerCensus {
    inside: usize,
    frames_inside: u32,
}

fn apply_inputs(input: Res<WalkInput>, mut probe: Single<&mut PlayerProbe>) {
    probe.0.velocity.x = input.0;
    probe.0.velocity.y -= GRAVITY * DT;
}

fn resolve(level: Res<Level>, mut probe: Single<&mut PlayerProbe>) {
    let outcome = move_probe(&level.0, &probe.0, DT);
    probe.0.center = outcome.center;
    probe.0.velocity = outcome.velocity;
    probe.0.grounded = outcome.grounded;
}

fn census_triggers(
    level: Res<Level>,
    probe: Single<&PlayerProbe>,
    mut census: ResMut<TriggerCensus>,
) {
    let bounds = Aabb::from_center_half(probe.0.center, probe.0.half_size);
    census.inside = level.0.trigger_cells_overlapping(&bounds).count();
    if census.inside > 0 {
        census.frames_inside += 1;
    }
}

/// A floor row across the bottom of an 8-wide grid.
fn floor_only() -> TileGrid {
    let mut grid = TileGrid::new(Vec2::ZERO, CELL, 8, 2);
    for x in 0..8 {
        grid.set(IVec2::new(x, 0), CollisionMode::Solid);
    }
    grid
}

/// An app with the three systems chained, one probe body, and the level.
fn probe_app(level: TileGrid, walk: f32, start: Vec2) -> App {
    let mut app = App::new();
    app.insert_resource(Level(level))
        .insert_resource(WalkInput(walk))
        .insert_resource(TriggerCensus::default())
        .add_systems(Update, (apply_inputs, resolve, census_triggers).chain());
    app.world_mut().spawn(PlayerProbe(Probe {
        center: start,
        half_size: Vec2::splat(8.0),
        velocity: Vec2::ZERO,
        grounded: false,
    }));
    app
}

fn probe_of(app: &mut App) -> Probe {
    let mut probes = app.world_mut().query::<&PlayerProbe>();
    probes
        .single(app.world_mut())
        .expect("exactly one probe body")
        .0
}

#[test]
fn the_ground_holds_a_falling_probe() {
    let mut app = probe_app(floor_only(), 0.0, Vec2::new(128.0, 96.0));
    for _ in 0..120 {
        app.update();
    }
    let landed = probe_of(&mut app);
    assert!(landed.grounded, "the floor holds the body");
    let resting_y = CELL + 8.0 + SEPARATION;
    assert!(
        (landed.center.y - resting_y).abs() < 1e-4,
        "rests a separation gap above the floor face: {}",
        landed.center.y
    );
    let y = landed.center.y;
    for _ in 0..3 {
        app.update();
        assert_eq!(probe_of(&mut app).center.y, y, "rest is bit-stable");
    }
    let level = app.world().resource::<Level>();
    let bounds = Aabb::from_center_half(landed.center, landed.half_size);
    assert!(
        level.0.solid_cells_overlapping(&bounds).next().is_none(),
        "a resting body never overlaps the floor"
    );
}

#[test]
fn the_wall_blocks_a_walking_probe() {
    let mut grid = TileGrid::new(Vec2::ZERO, CELL, 8, 4);
    for x in 0..8 {
        grid.set(IVec2::new(x, 0), CollisionMode::Solid);
    }
    for y in 1..3 {
        grid.set(IVec2::new(5, y), CollisionMode::Solid);
    }
    let mut app = probe_app(grid, WALK, Vec2::new(64.0, CELL + 8.0 + SEPARATION));
    for _ in 0..90 {
        app.update();
        // The walk's invariant, every frame: the wall never lets the body
        // overlap it.
        let probe = probe_of(&mut app);
        let bounds = Aabb::from_center_half(probe.center, probe.half_size);
        let level = app.world().resource::<Level>();
        assert!(
            level.0.solid_cells_overlapping(&bounds).next().is_none(),
            "the wall never lets the body overlap it"
        );
    }
    let probe = probe_of(&mut app);
    let parked = 5.0 * CELL - 8.0 - SEPARATION;
    assert!(
        (probe.center.x - parked).abs() < 1e-4,
        "parked one separation gap before the wall face: {} vs {parked}",
        probe.center.x
    );
    assert_eq!(
        probe.velocity.x, 0.0,
        "the blocked axis reads as zeroed after the step"
    );
    assert!(probe.grounded, "still standing on the floor");
}

#[test]
fn the_trigger_reports_a_crossing() {
    let mut grid = floor_only();
    grid.set(IVec2::new(6, 1), CollisionMode::Trigger);
    let mut app = probe_app(grid, WALK, Vec2::new(64.0, CELL + 8.0 + SEPARATION));
    for _ in 0..150 {
        app.update();
    }
    let census = app.world().resource::<TriggerCensus>();
    assert!(
        census.frames_inside >= 20,
        "the crossing reported the cell: {} frames",
        census.frames_inside
    );
    assert_eq!(census.inside, 0, "past the cell the report silences again");
    let probe = probe_of(&mut app);
    let bounds = Aabb::from_center_half(probe.center, probe.half_size);
    let level = app.world().resource::<Level>();
    assert!(
        probe.center.x > 7.0 * CELL,
        "the body crossed the trigger cell entirely"
    );
    assert!(
        level.0.trigger_cells_overlapping(&bounds).next().is_none(),
        "no trigger under the body at the end"
    );
}
