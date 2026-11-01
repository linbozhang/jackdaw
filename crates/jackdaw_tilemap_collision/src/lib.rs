//! The tile-grid collision kernel (T22 decision 2-A): pure, deterministic
//! functions over a square tile grid that carry the three acceptance
//! behaviors of the T22 round — a body comes to rest on `Solid` floors, is
//! clamped by `Solid` walls, and is reported while overlapping `Trigger`
//! cells.
//!
//! The crate is engine-agnostic (`glam` only), so the game-side wiring (the
//! T2 template module) can quote or depend on it, and every behavior is
//! headless testable — the platformer-shaped alternative to integrating a
//! full physics engine (the avian2d option was rejected as a T10-sized
//! project for three assertions; T22 plan fact 11).
//!
//! The [`CollisionMode`] tri-state ports the semantics of the upstream
//! `jackdaw_tilemap` kernel (`CollisionMode { Solid, Trigger, Passable }`,
//! nightly-2026-10-27 `setup.rs:77-82`) verbatim. Per controller decision 3-B
//! no upstream code is absorbed — six lines of meaning, doc-noted, and the
//! upstream kernel stays on its tag.
//!
//! Layout: a [`TileGrid`] stores one [`CollisionMode`] per cell (dense row
//! major — small levels are the plan's stated scale boundary), the point /
//! region / neighbor queries read it, and [`move_probe`] resolves an
//! axis-separated AABB sweep against `Solid` cells. Forces (gravity, input)
//! stay with the caller: the kernel only resolves, which keeps every step
//! deterministic and replayable.

use glam::{IVec2, Vec2};

/// The per-cell collision tri-state. `Solid` resolves movement, `Trigger`
/// reports overlap and lets movement pass, `Passable` is decorative or open.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum CollisionMode {
    /// Open or decorative: bodies pass through and nothing is reported.
    #[default]
    Passable,
    /// Floor and wall cells: [`move_probe`] never lets a body overlap one.
    Solid,
    /// Region cells (the acceptance round's "触发区"): bodies pass through
    /// while [`TileGrid::trigger_cells_overlapping`] reports them.
    Trigger,
}

/// The gap a resolver keeps between a body and a `Solid` face. Small enough
/// to be invisible at tile scales, big enough that the strict intersection
/// test of the next step no longer sees the touched face — which is what
/// makes resting positions bit-identical across steps.
pub const SEPARATION: f32 = 1e-3;

/// An axis-aligned box in world units, y-up like the editor's 2D scenes.
/// Touching edges (`max_a == min_b`) do not intersect — the resolver's
/// resting contact is not a penetration.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Aabb {
    /// Inclusive minimum corner.
    pub min: Vec2,
    /// Exclusive maximum corner.
    pub max: Vec2,
}

impl Aabb {
    /// A box from its two corners; components are ordered per axis.
    #[must_use]
    pub fn new(a: Vec2, b: Vec2) -> Self {
        Self {
            min: a.min(b),
            max: a.max(b),
        }
    }

    /// A box from a centre and per-axis half extents.
    #[must_use]
    pub fn from_center_half(center: Vec2, half: Vec2) -> Self {
        Self {
            min: center - half,
            max: center + half,
        }
    }

    /// The centre of the box.
    #[must_use]
    pub fn center(&self) -> Vec2 {
        (self.min + self.max) * 0.5
    }

    /// Strict overlap: any shared interior area. Edge touches are `false`.
    #[must_use]
    pub fn intersects(&self, other: &Aabb) -> bool {
        self.min.x < other.max.x
            && self.max.x > other.min.x
            && self.min.y < other.max.y
            && self.max.y > other.min.y
    }

    /// Whether a world point is inside the box.
    #[must_use]
    pub fn contains(&self, point: Vec2) -> bool {
        point.x >= self.min.x
            && point.x < self.max.x
            && point.y >= self.min.y
            && point.y < self.max.y
    }
}

/// The four cardinal neighbors of a cell, for the adjacent-cell query.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Direction {
    /// `+x`.
    East,
    /// `+y`.
    North,
    /// `-x`.
    West,
    /// `-y`.
    South,
}

impl Direction {
    /// The cell offset of this direction.
    #[must_use]
    pub fn offset(self) -> IVec2 {
        match self {
            Self::East => IVec2::new(1, 0),
            Self::North => IVec2::new(0, 1),
            Self::West => IVec2::new(-1, 0),
            Self::South => IVec2::new(0, -1),
        }
    }
}

/// A square-cell collision grid anchored at an world-space origin. Cell
/// `(0, 0)` spans `[origin, origin + cell_size]` per axis; `x` grows east,
/// `y` grows north (the editor's 2D convention).
#[derive(Clone, Debug, PartialEq)]
pub struct TileGrid {
    origin: Vec2,
    cell_size: f32,
    width: u32,
    height: u32,
    modes: Vec<CollisionMode>,
}

impl TileGrid {
    /// A grid where every cell starts [`CollisionMode::Passable`].
    #[must_use]
    pub fn new(origin: Vec2, cell_size: f32, width: u32, height: u32) -> Self {
        Self {
            origin,
            cell_size,
            width,
            height,
            modes: vec![CollisionMode::Passable; (width * height) as usize],
        }
    }

    /// The grid origin (cell `(0, 0)`'s minimum corner).
    #[must_use]
    pub fn origin(&self) -> Vec2 {
        self.origin
    }

    /// The edge length of one cell, in world units.
    #[must_use]
    pub fn cell_size(&self) -> f32 {
        self.cell_size
    }

    /// Cells along `x`.
    #[must_use]
    pub fn width(&self) -> u32 {
        self.width
    }

    /// Cells along `y`.
    #[must_use]
    pub fn height(&self) -> u32 {
        self.height
    }

    /// Whether a cell coordinate lies inside the grid.
    #[must_use]
    pub fn in_bounds(&self, cell: IVec2) -> bool {
        cell.x >= 0 && cell.y >= 0 && cell.x < self.width as i32 && cell.y < self.height as i32
    }

    /// Writes a cell's mode. Out-of-bounds writes panic: level tooling
    /// computes cells from this same grid, so a miss is an authoring bug.
    pub fn set(&mut self, cell: IVec2, mode: CollisionMode) {
        assert!(self.in_bounds(cell), "cell {cell:?} outside the grid");
        let index = self.index(cell);
        self.modes[index] = mode;
    }

    /// Reads a cell's mode; `None` outside the grid.
    #[must_use]
    pub fn mode(&self, cell: IVec2) -> Option<CollisionMode> {
        if self.in_bounds(cell) {
            Some(self.modes[self.index(cell)])
        } else {
            None
        }
    }

    /// The cell containing a world point (floor division; may be out of
    /// bounds — pair with [`TileGrid::in_bounds`] or [`TileGrid::mode`]).
    #[must_use]
    pub fn world_to_cell(&self, world: Vec2) -> IVec2 {
        let local = (world - self.origin) / self.cell_size;
        IVec2::new(local.x.floor() as i32, local.y.floor() as i32)
    }

    /// A cell's minimum corner in world space.
    #[must_use]
    pub fn cell_min_corner(&self, cell: IVec2) -> Vec2 {
        self.origin + cell.as_vec2() * self.cell_size
    }

    /// A cell's centre in world space.
    #[must_use]
    pub fn cell_center(&self, cell: IVec2) -> Vec2 {
        self.cell_min_corner(cell) + Vec2::splat(self.cell_size * 0.5)
    }

    /// A cell's world-space bounds.
    #[must_use]
    pub fn cell_bounds(&self, cell: IVec2) -> Aabb {
        let min = self.cell_min_corner(cell);
        Aabb {
            min,
            max: min + Vec2::splat(self.cell_size),
        }
    }

    /// Point query: the mode of the cell under a world point, `None` outside.
    #[must_use]
    pub fn mode_at_point(&self, world: Vec2) -> Option<CollisionMode> {
        self.mode(self.world_to_cell(world))
    }

    /// Region query: every in-bounds cell whose interior overlaps `bounds`,
    /// with its mode.
    pub fn cells_overlapping<'a>(
        &'a self,
        bounds: &'a Aabb,
    ) -> impl Iterator<Item = (IVec2, CollisionMode)> + 'a {
        let grid_max = IVec2::new(self.width as i32 - 1, self.height as i32 - 1);
        let first = self.world_to_cell(bounds.min).clamp(IVec2::ZERO, grid_max);
        let last =
            (self.world_to_cell(bounds.max - Vec2::splat(SEPARATION))).clamp(IVec2::ZERO, grid_max);
        let mut cursor = first;
        std::iter::from_fn(move || {
            while cursor.y <= last.y {
                let cell = cursor;
                cursor.x += 1;
                if cursor.x > last.x {
                    cursor.x = first.x;
                    cursor.y += 1;
                }
                if self.cell_bounds(cell).intersects(bounds) {
                    let mode = self.modes[self.index(cell)];
                    return Some((cell, mode));
                }
            }
            None
        })
    }

    /// Region query for one mode: the cells of `mode` overlapping `bounds`.
    pub fn cells_of_mode<'a>(
        &'a self,
        bounds: &'a Aabb,
        mode: CollisionMode,
    ) -> impl Iterator<Item = IVec2> + 'a {
        self.cells_overlapping(bounds)
            .filter_map(move |(cell, cell_mode)| (cell_mode == mode).then_some(cell))
    }

    /// The `Solid` cells a body's box overlaps (the resolver's read).
    pub fn solid_cells_overlapping<'a>(
        &'a self,
        bounds: &'a Aabb,
    ) -> impl Iterator<Item = IVec2> + 'a {
        self.cells_of_mode(bounds, CollisionMode::Solid)
    }

    /// The `Trigger` cells a body's box overlaps (the acceptance round's
    /// "触发区触发" read).
    pub fn trigger_cells_overlapping<'a>(
        &'a self,
        bounds: &'a Aabb,
    ) -> impl Iterator<Item = IVec2> + 'a {
        self.cells_of_mode(bounds, CollisionMode::Trigger)
    }

    /// Neighbor query: the mode of one cardinal neighbor, `None` outside.
    #[must_use]
    pub fn neighbor(&self, cell: IVec2, direction: Direction) -> Option<CollisionMode> {
        self.mode(cell + direction.offset())
    }

    /// Neighbor query: the modes of all four cardinal neighbors, in
    /// `[East, North, West, South]` order; `None` entries are outside.
    #[must_use]
    pub fn neighbors(&self, cell: IVec2) -> [Option<CollisionMode>; 4] {
        [
            self.neighbor(cell, Direction::East),
            self.neighbor(cell, Direction::North),
            self.neighbor(cell, Direction::West),
            self.neighbor(cell, Direction::South),
        ]
    }

    fn index(&self, cell: IVec2) -> usize {
        (cell.y as usize) * (self.width as usize) + (cell.x as usize)
    }
}

/// The 2D player probe body: a centred AABB with a velocity, plus the
/// `grounded` latch the movement loop reads.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Probe {
    /// Centre of the body in world units.
    pub center: Vec2,
    /// Per-axis half extents.
    pub half_size: Vec2,
    /// Current velocity; the caller integrates forces, the kernel resolves.
    pub velocity: Vec2,
    /// Whether the body is supported by a `Solid` face below it.
    pub grounded: bool,
}

/// The result of one resolved step.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct MoveOutcome {
    /// The resolved centre after the step.
    pub center: Vec2,
    /// The velocity after the step: a blocked axis is zeroed.
    pub velocity: Vec2,
    /// Whether the body rests on a `Solid` face (the "地面站得住" latch).
    pub grounded: bool,
    /// Whether the horizontal move was clamped by a wall (the "墙挡住" flag).
    pub hit_wall: bool,
}

/// Resolves one fixed step of `dt` for `probe` against the grid's `Solid`
/// cells. The move is axis-separated (horizontal first): each axis is
/// integrated, then clamped to the nearest blocking face with a
/// [`SEPARATION`] gap, so resting positions repeat bit-identically while a
/// body leans on a floor. `Trigger` cells never clamp. The body is expected
/// to start un-overlapped; a caller that spawns one inside a `Solid` cell
/// gets pushed to the nearest face along its motion on the next step.
#[must_use]
pub fn move_probe(grid: &TileGrid, probe: &Probe, dt: f32) -> MoveOutcome {
    let mut center = probe.center;
    let mut velocity = probe.velocity;

    let dx = velocity.x * dt;
    let (resolved_x, hit_wall) = sweep_axis(grid, center, probe.half_size, 0, dx);
    center.x = resolved_x;
    if hit_wall {
        velocity.x = 0.0;
    }

    let dy = velocity.y * dt;
    let (resolved_y, hit_y) = sweep_axis(grid, center, probe.half_size, 1, dy);
    center.y = resolved_y;
    if hit_y {
        velocity.y = 0.0;
    }

    let bounds = Aabb::from_center_half(center, probe.half_size);
    let grounded = is_supported(grid, &bounds);
    MoveOutcome {
        center,
        velocity,
        grounded,
        hit_wall,
    }
}

/// Whether a body's box has a `Solid` face just below its feet (x-inset so
/// a wall's top edge beside the body does not read as ground).
#[must_use]
pub fn is_supported(grid: &TileGrid, bounds: &Aabb) -> bool {
    let feet = Aabb {
        min: Vec2::new(bounds.min.x + SEPARATION, bounds.min.y - 2.0 * SEPARATION),
        max: Vec2::new(bounds.max.x - SEPARATION, bounds.min.y),
    };
    grid.solid_cells_overlapping(&feet).next().is_some()
}

/// Integrates one axis of the box by `delta` and clamps the centre against
/// any `Solid` cell the moved box enters, keeping a [`SEPARATION`] gap.
/// Returns the resolved centre coordinate on `axis` and whether it clamped.
fn sweep_axis(
    grid: &TileGrid,
    center: Vec2,
    half_size: Vec2,
    axis: usize,
    delta: f32,
) -> (f32, bool) {
    let start = if axis == 0 { center.x } else { center.y };
    if delta == 0.0 {
        return (start, false);
    }
    let moved = Aabb::from_center_half(
        center
            + if axis == 0 {
                Vec2::new(delta, 0.0)
            } else {
                Vec2::new(0.0, delta)
            },
        half_size,
    );
    let mut resolved = start + delta;
    let mut hit = false;
    let half = if axis == 0 { half_size.x } else { half_size.y };
    for (cell, mode) in grid.cells_overlapping(&moved) {
        if mode != CollisionMode::Solid {
            continue;
        }
        let face = if delta > 0.0 {
            (if axis == 0 {
                grid.cell_bounds(cell).min.x
            } else {
                grid.cell_bounds(cell).min.y
            }) - half
                - SEPARATION
        } else {
            (if axis == 0 {
                grid.cell_bounds(cell).max.x
            } else {
                grid.cell_bounds(cell).max.y
            }) + half
                + SEPARATION
        };
        resolved = if delta > 0.0 {
            resolved.min(face)
        } else {
            resolved.max(face)
        };
        hit = true;
    }
    (resolved, hit)
}

#[cfg(test)]
mod tests {
    use super::*;

    const CELL: f32 = 32.0;
    const DT: f32 = 1.0 / 60.0;
    const GRAVITY: f32 = 900.0;
    const WALK: f32 = 96.0;

    /// An 8x4 mix: solid floor row (y = 0), a solid wall column at x = 5
    /// (rows 1-2, so a floor-level body meets it at body height), and a
    /// trigger cell at (6, 1).
    fn level() -> TileGrid {
        let mut grid = TileGrid::new(Vec2::ZERO, CELL, 8, 4);
        for x in 0..8 {
            grid.set(IVec2::new(x, 0), CollisionMode::Solid);
        }
        for y in 1..3 {
            grid.set(IVec2::new(5, y), CollisionMode::Solid);
        }
        grid.set(IVec2::new(6, 1), CollisionMode::Trigger);
        grid
    }

    /// An 8x2 floor-only grid.
    fn floor_only() -> TileGrid {
        let mut grid = TileGrid::new(Vec2::ZERO, CELL, 8, 2);
        for x in 0..8 {
            grid.set(IVec2::new(x, 0), CollisionMode::Solid);
        }
        grid
    }

    /// A body resting on the floor row at `x`.
    fn resting(x: f32) -> Probe {
        Probe {
            center: Vec2::new(x, CELL + 8.0 + SEPARATION),
            half_size: Vec2::splat(8.0),
            velocity: Vec2::ZERO,
            grounded: true,
        }
    }

    /// One fixed step of the game loop: gravity, then the kernel resolves.
    fn step(grid: &TileGrid, probe: &mut Probe) -> MoveOutcome {
        probe.velocity.y -= GRAVITY * DT;
        let outcome = move_probe(grid, probe, DT);
        *probe = Probe {
            center: outcome.center,
            velocity: outcome.velocity,
            half_size: probe.half_size,
            grounded: outcome.grounded,
        };
        outcome
    }

    #[test]
    fn grid_math_round_trips_world_points_through_cells() {
        let grid = level();
        let cell = grid.world_to_cell(Vec2::new(100.0, 40.0));
        assert_eq!(cell, IVec2::new(3, 1), "100/32 floors to 3, 40/32 to 1");
        assert_eq!(grid.world_to_cell(grid.cell_center(cell)), cell);
        assert_eq!(grid.cell_min_corner(cell), Vec2::new(96.0, 32.0));
        assert_eq!(grid.cell_center(cell), Vec2::new(112.0, 48.0));
        assert_eq!(
            grid.world_to_cell(Vec2::new(-0.5, -0.5)),
            IVec2::new(-1, -1),
            "points below the origin floor-divide out of the grid"
        );
    }

    #[test]
    fn the_point_query_reads_the_cell_under_a_world_point() {
        let grid = level();
        assert_eq!(
            grid.mode_at_point(Vec2::new(80.0, 16.0)),
            Some(CollisionMode::Solid),
            "the centre of floor cell (2, 0)"
        );
        assert_eq!(
            grid.mode_at_point(grid.cell_center(IVec2::new(6, 1))),
            Some(CollisionMode::Trigger),
            "the centre of the trigger cell"
        );
        assert_eq!(
            grid.mode_at_point(Vec2::new(50.0, 80.0)),
            Some(CollisionMode::Passable),
            "open sky"
        );
        assert_eq!(grid.mode_at_point(Vec2::new(-5.0, 16.0)), None);
        assert_eq!(
            grid.mode_at_point(Vec2::new(300.0, 16.0)),
            None,
            "past the grid's east edge"
        );
    }

    #[test]
    fn the_neighbor_query_reports_the_four_adjacent_modes() {
        let grid = level();
        let cell = IVec2::new(4, 1);
        assert_eq!(
            grid.neighbors(cell),
            [
                Some(CollisionMode::Solid),
                Some(CollisionMode::Passable),
                Some(CollisionMode::Passable),
                Some(CollisionMode::Solid),
            ],
            "east is the wall column, south is the floor row"
        );
        assert_eq!(
            grid.neighbor(IVec2::new(0, 0), Direction::West),
            None,
            "west of the grid's first cell is nothing"
        );
    }

    #[test]
    fn the_region_query_census_of_a_box_finds_solid_and_trigger() {
        let grid = level();
        let at_the_wall = Aabb::from_center_half(Vec2::new(160.0, 40.0), Vec2::splat(8.0));
        assert_eq!(
            grid.cells_overlapping(&at_the_wall).collect::<Vec<_>>(),
            vec![
                (IVec2::new(4, 1), CollisionMode::Passable),
                (IVec2::new(5, 1), CollisionMode::Solid),
            ],
            "row-major order, open cell and wall cell"
        );
        assert_eq!(
            grid.solid_cells_overlapping(&at_the_wall)
                .collect::<Vec<_>>(),
            vec![IVec2::new(5, 1)]
        );
        let over_the_trigger =
            Aabb::from_center_half(grid.cell_center(IVec2::new(6, 1)), Vec2::splat(8.0));
        assert_eq!(
            grid.trigger_cells_overlapping(&over_the_trigger)
                .collect::<Vec<_>>(),
            vec![IVec2::new(6, 1)]
        );
        assert!(
            grid.trigger_cells_overlapping(&at_the_wall)
                .next()
                .is_none(),
            "solid cells never answer the trigger query"
        );
    }

    #[test]
    fn a_falling_probe_lands_on_the_floor_and_stays_put() {
        let grid = floor_only();
        let mut probe = resting(128.0);
        probe.center.y = 96.0;
        probe.grounded = false;
        for _ in 0..120 {
            step(&grid, &mut probe);
        }
        assert!(probe.grounded, "the floor holds the body");
        let resting_y = CELL + 8.0 + SEPARATION;
        assert!(
            (probe.center.y - resting_y).abs() < 1e-4,
            "the body rests a separation gap above the floor face: {} vs {resting_y}",
            probe.center.y
        );
        let y = probe.center.y;
        for _ in 0..3 {
            step(&grid, &mut probe);
            assert_eq!(probe.center.y, y, "resting repeats bit-identically");
            assert!(probe.grounded);
        }
        let bounds = Aabb::from_center_half(probe.center, probe.half_size);
        assert!(
            grid.solid_cells_overlapping(&bounds).next().is_none(),
            "a resting body never overlaps the floor"
        );
    }

    #[test]
    fn a_walking_probe_is_stopped_by_a_wall_column() {
        let grid = level();
        let mut probe = resting(64.0);
        let mut blocked_steps = 0;
        let mut previous_x = probe.center.x;
        let mut stable_steps = 0;
        for _ in 0..90 {
            probe.velocity.x = WALK;
            let outcome = step(&grid, &mut probe);
            if outcome.hit_wall {
                blocked_steps += 1;
            }
            if probe.center.x == previous_x {
                stable_steps += 1;
            }
            previous_x = probe.center.x;
        }
        assert!(
            blocked_steps >= 20,
            "the walk parks against the wall: {blocked_steps} blocked steps"
        );
        assert!(stable_steps >= 20, "the park position does not creep");
        let wall_face = 5.0 * CELL;
        let parked = wall_face - 8.0 - SEPARATION;
        assert!(
            (probe.center.x - parked).abs() < 1e-4,
            "parked one separation gap before the wall face: {} vs {parked}",
            probe.center.x
        );
        assert!(probe.center.x > 64.0 + 60.0, "the approach moved freely");
        let bounds = Aabb::from_center_half(probe.center, probe.half_size);
        assert!(
            grid.solid_cells_overlapping(&bounds).next().is_none(),
            "a parked body never overlaps the wall"
        );
    }

    #[test]
    fn a_trigger_cell_reports_while_overlapped_and_silences_after() {
        let mut grid = floor_only();
        grid.set(IVec2::new(6, 1), CollisionMode::Trigger);
        let mut probe = resting(64.0);
        let mut inside_steps = 0;
        let mut fired = false;
        for _ in 0..150 {
            probe.velocity.x = WALK;
            step(&grid, &mut probe);
            let bounds = Aabb::from_center_half(probe.center, probe.half_size);
            let hits = grid.trigger_cells_overlapping(&bounds).count();
            if hits > 0 {
                fired = true;
                inside_steps += 1;
            }
        }
        assert!(fired, "walking the trigger row reports the cell");
        assert!(
            (20..=40).contains(&inside_steps),
            "the report window spans only the crossing (48 px at 1.6 px/step): {inside_steps} steps"
        );
        let bounds = Aabb::from_center_half(probe.center, probe.half_size);
        assert_eq!(
            grid.trigger_cells_overlapping(&bounds).count(),
            0,
            "past the cell the report silences"
        );
    }

    #[test]
    fn solid_and_out_of_bounds_cells_never_answer_the_trigger_query() {
        let grid = level();
        let on_the_floor = Aabb::from_center_half(Vec2::new(128.0, 16.0), Vec2::splat(8.0));
        assert!(
            grid.trigger_cells_overlapping(&on_the_floor)
                .next()
                .is_none()
        );
        let outside = Aabb::from_center_half(Vec2::new(-32.0, 16.0), Vec2::splat(8.0));
        assert!(
            grid.solid_cells_overlapping(&outside).next().is_none(),
            "out-of-bounds boxes resolve to nothing"
        );
    }
}
