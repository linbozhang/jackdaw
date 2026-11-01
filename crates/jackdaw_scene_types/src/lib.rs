//! Editor display metadata as Bevy reflect custom attributes.
//! The picker reads them via
//! `type_info.custom_attributes().get::<T>()` and falls back to
//! the type's reflected doc comment (workspace bevy
//! `reflect_documentation` feature).
//!
//! ```ignore
//! use bevy::prelude::*;
//! use jackdaw_scene_types::EditorCategory;
//!
//! /// Spawns the player entity.
//! #[derive(Component, Reflect, Default)]
//! #[reflect(Component, Default, @EditorCategory("Actor"))]
//! pub struct PlayerSpawn;
//! ```
//!
//! `jackdaw_runtime` and `jackdaw` re-export these newtypes
//! through their preludes.

pub mod asset_path;
pub mod brush_chunks;
pub mod environment;
#[cfg(feature = "render")]
pub mod lod_generate;
#[cfg(feature = "render")]
pub mod mesh_rebuild;
#[cfg(feature = "render")]
pub mod model_import;
#[cfg(feature = "render")]
pub mod model_parts;
pub mod node_id;
#[cfg(feature = "render")]
pub mod render_assets;
pub mod types;

pub use asset_path::to_asset_path;
pub use brush_chunks::{MeshChunk, build_brush_chunks};
pub use environment::{
    Ambient, AmbientMode, Antialiasing, Environment, Fog, FogMode, Multisampling, PostProcess,
    Reflections, ShadowFiltering, Sky, Tonemapper,
};
#[cfg(feature = "render")]
pub use mesh_rebuild::evaluate_brush_geometry;
pub use node_id::{SCENE_NODE_ID_TYPE_PATH, SPARSE_MIN, SceneNodeId};
pub use types::{
    Brush, BrushFaceData, BrushPlane, BrushTopology, CustomProperties, DerivedFaceMesh,
    DetailLayer, DetailMesh, DetailPresser, DetailVariety, GltfSource, HIDDEN_IN_GAME_TYPE_PATH,
    HiddenInGame, InstanceMaterialOverrides, LodFade, LodGroup, LodLevel, LodOverride,
    MaterialOverrides, NAVMESH_EXCLUDE_TYPE_PATH, NavmeshExclude, NavmeshIgnored, PrefabBaseline,
    PropertyValue, ReflectionProbe, ScatterGroup, ScatterInstance, SceneRootTag, SceneWind,
    Terrain, TerrainChannel, TerrainChannelElement, TerrainNavmesh, TerrainPaletteEntry,
    TerrainQuantization, Wind,
};

use bevy::prelude::*;
use std::borrow::Cow;

/// Registers every scene component type for reflection. With the `render`
/// feature this also covers the asset reflection a headless app needs to
/// deserialize material handles, plus the optional brush mesh rebuild.
pub struct SceneTypesPlugin {
    /// Whether to run the built-in runtime mesh rebuild for brushes.
    /// Defaults to `true`. Set to `false` if your app has its own mesh rebuild
    /// (e.g. the editor's per-face material palette system).
    pub runtime_mesh_rebuild: bool,
}

impl Default for SceneTypesPlugin {
    fn default() -> Self {
        Self {
            runtime_mesh_rebuild: true,
        }
    }
}

impl Plugin for SceneTypesPlugin {
    fn build(&self, app: &mut App) {
        use jackdaw_geometry::{
            AttributeData, AttributeStack, MeshEdge, MeshLoop, MeshMirror, MeshPoly, MeshVert,
            Modifier, ModifierEntry, ModifierStack,
        };
        app.register_type::<Brush>()
            .register_type::<SceneRootTag>()
            .register_type::<BrushFaceData>()
            .register_type::<BrushPlane>()
            .register_type::<BrushTopology>()
            .register_type::<MeshVert>()
            .register_type::<MeshEdge>()
            .register_type::<MeshPoly>()
            .register_type::<MeshLoop>()
            .register_type::<AttributeStack>()
            .register_type::<AttributeData>()
            .register_type::<CustomProperties>()
            .register_type::<PropertyValue>()
            .register_type::<SceneNodeId>()
            .register_type::<GltfSource>()
            .register_type::<MaterialOverrides>()
            .register_type::<LodGroup>()
            .register_type::<LodLevel>()
            .register_type::<LodOverride>()
            .register_type::<LodFade>()
            .register_type::<InstanceMaterialOverrides>()
            .register_type::<Terrain>()
            .register_type::<TerrainChannel>()
            .register_type::<TerrainChannelElement>()
            .register_type::<TerrainNavmesh>()
            .register_type::<DetailLayer>()
            .register_type::<DetailMesh>()
            .register_type::<DetailVariety>()
            .register_type::<DetailPresser>()
            .register_type::<Wind>()
            .register_type::<Environment>()
            .register_type::<Sky>()
            .register_type::<Fog>()
            .register_type::<FogMode>()
            .register_type::<Ambient>()
            .register_type::<AmbientMode>()
            .register_type::<Reflections>()
            .register_type::<PostProcess>()
            .register_type::<Tonemapper>()
            .register_type::<Antialiasing>()
            .register_type::<Multisampling>()
            .register_type::<ShadowFiltering>()
            .register_type::<NavmeshExclude>()
            .register_type::<HiddenInGame>()
            .register_type::<ReflectionProbe>()
            .register_type::<ScatterGroup>()
            .register_type::<ScatterInstance>()
            .register_type::<TerrainPaletteEntry>()
            .register_type::<TerrainQuantization>()
            .register_type::<MeshMirror>()
            .register_type::<ModifierStack>()
            .register_type::<ModifierEntry>()
            .register_type::<Modifier>()
            .register_type::<UiSceneRoot>()
            .register_type::<Scene2dRoot>()
            .register_type::<CanvasGuides>()
            .register_type::<TilemapLayer>()
            .register_type::<TileGridCell>()
            .register_type::<TileCollisionMode>()
            .register_type::<Locked>();

        app.init_resource::<SceneWind>()
            .add_systems(First, follow_the_scene_wind);

        #[cfg(feature = "render")]
        {
            // With `render`, `BrushFaceData::material` is a `Handle<StandardMaterial>`.
            // A dedicated server builds with `render` for these types but adds no
            // rendering plugins, so material/image asset reflection is never set up and
            // the deserializer (which keys these handles off `ReflectHandle`) drops any
            // brush with an unassigned `material: null` face. Register it only when the
            // render plugins are absent; when they are present (the editor, a windowed
            // client) they own this, and re-registering corrupts the asset storage.
            if !app
                .world()
                .contains_resource::<bevy::asset::Assets<bevy::pbr::StandardMaterial>>()
            {
                use bevy::asset::AssetApp;
                app.init_asset::<bevy::pbr::StandardMaterial>()
                    .register_asset_reflect::<bevy::pbr::StandardMaterial>()
                    .init_asset::<bevy::image::Image>()
                    .register_asset_reflect::<bevy::image::Image>();
            }

            if self.runtime_mesh_rebuild {
                app.add_plugins(mesh_rebuild::MeshRebuildPlugin);
            }
        }
    }
}

/// Hand the render side the wind the scene is blowing by: the first [`Wind`]
/// in it, or still air while it holds none.
fn follow_the_scene_wind(mut blowing: ResMut<SceneWind>, winds: Query<&Wind>) {
    let scene_wind = SceneWind(winds.iter().next().copied().unwrap_or(Wind::STILL));
    if *blowing != scene_wind {
        *blowing = scene_wind;
    }
}

/// Root of an authored UI scene. The 2D UI viewport keys on this
/// component; `reference_size` is the design resolution the authored
/// layout is measured against.
#[derive(Component, Clone, Copy, Debug, Reflect)]
#[reflect(Component, Default)]
pub struct UiSceneRoot {
    pub reference_size: UVec2,
}

impl Default for UiSceneRoot {
    fn default() -> Self {
        Self {
            reference_size: UVec2::new(1280, 720),
        }
    }
}

/// Root of an authored 2D world scene.
///
/// A 2D scene has no seeded contents of its own -- sprites are the author's
/// to add -- so this marker is what a saved document carries to say which
/// kind it is, the way [`UiSceneRoot`] does for a UI scene. Reopening a
/// document that declares it recognises the scene as 2D again.
#[derive(Component, Clone, Copy, Debug, Default, Reflect)]
#[reflect(Component, Default)]
pub struct Scene2dRoot;

/// Guide lines an author pulled off the 2D canvas's rulers, on the root
/// of an authored UI scene or of a 2D world scene.
///
/// On a UI scene positions are authored pixels from the canvas's top-left
/// corner; on a 2D world scene they are world units, y up. Either way it is
/// the measure the scene itself is written in, so a guide stays where the
/// author put it whatever the panel is doing.
///
/// Editor-only in effect -- a running game never reads it -- but it
/// lives here rather than in the editor because the save filter drops
/// every type path under `jackdaw::`, and a guide has to survive the
/// document it was drawn on.
///
/// The component is absent rather than empty when a scene has no guides.
/// A saved component equal to its default emits as a bare type path, so
/// an empty one would sit in every document that ever had a guide.
#[derive(Component, Clone, Debug, Default, PartialEq, Reflect)]
#[reflect(Component, Default, @EditorHidden)]
pub struct CanvasGuides {
    /// Lines across the canvas, each fixing a y coordinate.
    pub horizontal: Vec<f32>,
    /// Lines down the canvas, each fixing an x coordinate.
    pub vertical: Vec<f32>,
}

/// A node the canvas will not pick up.
///
/// A locked node is still there, still drawn, still in the outliner and
/// still selectable from it; what it stops doing is answering a press on
/// the canvas. A background image or a frame that everything else is
/// placed against is the case for it: without a lock, every click aimed at
/// what sits on top of it lands on the thing underneath.
///
/// Editor-only in effect -- a running game never reads it -- but it lives
/// here rather than in the editor because the save filter drops every type
/// path under `jackdaw::`, and a lock has to survive the document it was
/// set on.
#[derive(Component, Clone, Copy, Debug, Default, PartialEq, Eq, Reflect)]
#[reflect(Component, Default, @EditorHidden)]
pub struct Locked;

/// Reflect type path for [`Locked`], for the paths that name a component
/// by its path rather than by its type.
pub const LOCKED_TYPE_PATH: &str = "jackdaw_scene_types::Locked";

/// One authored tile-grid layer (T22 route C): a parent entity whose
/// children are the tiles, each a `Sprite` cut from the layer's sheet with
/// a [`TileGridCell`] naming its cell and sheet tile.
///
/// The layer carries the grid the tiles sit on — cell size, sheet cut and
/// the sheet itself — and [`TileCollisionMode`], the per-layer collision
/// tri-state the game resolves against. Lives here (rather than in the
/// editor) for the same reason [`CanvasGuides`] does: the save filter drops
/// every type path under `jackdaw::`, and a tilemap has to survive the
/// document it was authored in — and a game's tilemap module builds its
/// collision grid from it.
#[derive(Component, Clone, Debug, Reflect, PartialEq)]
#[reflect(Component, Default, @EditorCategory::new("Tilemap"))]
pub struct TilemapLayer {
    /// Edge length of one cell, in world units.
    pub cell_size: Vec2,
    /// Sheet columns; tile index `i` cuts `rect` at
    /// `(i % columns, i / columns)`.
    pub columns: u32,
    /// Sheet rows.
    pub rows: u32,
    /// The sheet the tiles cut from.
    pub image: Handle<Image>,
    /// Draw order: tiles render at this z, so layers stack by it.
    pub order: i32,
}

impl Default for TilemapLayer {
    fn default() -> Self {
        Self {
            cell_size: Vec2::splat(32.0),
            columns: 8,
            rows: 4,
            image: Handle::default(),
            order: 0,
        }
    }
}

impl TilemapLayer {
    /// The sheet rectangle tile `tile` cuts, in the sheet's pixels.
    #[must_use]
    pub fn tile_rect(&self, tile: u32) -> Rect {
        let column = tile % self.columns;
        let row = tile / self.columns;
        Rect::new(
            column as f32 * self.cell_size.x,
            row as f32 * self.cell_size.y,
            (column + 1) as f32 * self.cell_size.x,
            (row + 1) as f32 * self.cell_size.y,
        )
    }

    /// A cell's centre in the layer's local space (y up: cell row 0 at the
    /// bottom, matching the collision grid the kernel builds from this).
    #[must_use]
    pub fn cell_center(&self, cell: IVec2) -> Vec2 {
        (cell.as_vec2() + Vec2::splat(0.5)) * self.cell_size
    }

    /// The cell a point of the layer's local space falls in (floor
    /// division, so it answers out-of-range cells too; the caller bounds).
    #[must_use]
    pub fn world_to_cell(&self, world: Vec2) -> IVec2 {
        let local = world / self.cell_size;
        IVec2::new(local.x.floor() as i32, local.y.floor() as i32)
    }
}

/// One tile of a [`TilemapLayer`]: the cell it sits in and the sheet tile
/// it cuts. Sits on the tile's `Sprite` child entity, next to
/// `EditorHidden` and `Locked` — a tile is redrawn from the palette, not
/// picked or gizmo'd (plan decision 5-A).
#[derive(Component, Clone, Copy, Debug, Default, Reflect, PartialEq, Eq)]
#[reflect(Component, Default, @EditorHidden)]
pub struct TileGridCell {
    /// Grid cell, layer-local; `(0, 0)` at the layer origin, y up.
    pub cell: IVec2,
    /// Index into the sheet cut: `row * columns + column`.
    pub tile: u32,
}

/// The per-layer collision tri-state. Ports the semantics of the upstream
/// `jackdaw_tilemap` kernel (`CollisionMode { Solid, Trigger, Passable }`,
/// nightly-2026-10-27 `setup.rs:77-82`) and matches
/// `jackdaw_tilemap_collision::CollisionMode` variant for variant — the
/// game module converts one to the other when it builds its grid.
///
/// Sits on the [`TilemapLayer`] parent: one mode per layer, not per tile.
#[derive(Component, Clone, Copy, Debug, Default, Reflect, PartialEq, Eq, Hash)]
#[reflect(Component, Default, @EditorCategory::new("Tilemap"))]
pub enum TileCollisionMode {
    /// Open or decorative: bodies pass through, nothing is reported.
    #[default]
    Passable,
    /// Floor and wall cells: the game's sweep never lets a body overlap.
    Solid,
    /// Region cells: bodies pass through while the game reports overlap.
    Trigger,
}

/// Picker grouping for a component. Attach via
/// `#[reflect(@EditorCategory("Your Group"))]`.
#[derive(Reflect, Clone, Debug, PartialEq, Eq)]
pub struct EditorCategory(pub Cow<'static, str>);

impl EditorCategory {
    pub const fn new(name: &'static str) -> Self {
        EditorCategory(Cow::Borrowed(name))
    }
}

impl From<&'static str> for EditorCategory {
    fn from(value: &'static str) -> Self {
        EditorCategory(Cow::Borrowed(value))
    }
}

impl From<String> for EditorCategory {
    fn from(value: String) -> Self {
        EditorCategory(Cow::Owned(value))
    }
}

/// Picker tooltip override. Falls back to the reflected doc
/// comment when absent.
#[derive(Reflect, Clone, Debug, PartialEq, Eq)]
pub struct EditorDescription(pub Cow<'static, str>);

impl EditorDescription {
    pub const fn new(text: &'static str) -> Self {
        EditorDescription(Cow::Borrowed(text))
    }
}

impl From<&'static str> for EditorDescription {
    fn from(value: &'static str) -> Self {
        EditorDescription(Cow::Borrowed(value))
    }
}

impl From<String> for EditorDescription {
    fn from(value: String) -> Self {
        EditorDescription(Cow::Owned(value))
    }
}

/// The asset kind a `String` field, or the elements of a `Vec<String>`
/// field, names by path. Attach via
/// `#[reflect(@AssetRef("my_game::content::ItemDef"))]`.
///
/// The editor gives such a field the asset row from the start, whether or
/// not it names a file yet, offers only files of that kind, and refuses a
/// drop of anything else.
///
/// ```ignore
/// #[derive(Asset, Reflect, Default)]
/// #[reflect(Default)]
/// pub struct QuestDef {
///     #[reflect(@AssetRef("my_game::content::ItemDef"))]
///     pub reward: String,
/// }
/// ```
#[derive(Reflect, Clone, Copy, Debug, PartialEq, Eq)]
pub struct AssetRef(pub &'static str);

/// Viewport preview for a marker component. Attach via
/// `#[reflect(@EditorPreview::gltf("models/rifle.glb"))]`.
#[derive(Reflect, Clone, Debug, PartialEq)]
pub struct EditorPreview(pub Cow<'static, str>);

impl EditorPreview {
    pub const fn gltf(path: &'static str) -> Self {
        EditorPreview(Cow::Borrowed(path))
    }
}

/// Hides things from editor-facing surfaces. Used in two ways:
///
/// - As a Bevy `Component` on an entity: hides that entity from
///   the hierarchy panel.
/// - As a `#[reflect(@EditorHidden)]` attribute on a Component
///   type: hides the type from the Add Component picker. Used by
///   jackdaw's own scene types (brushes, terrain, node
///   graph, animation graph) and available to extension and game
///   crates with helper Components.
///
/// ```ignore
/// #[derive(Component, Reflect, Default)]
/// #[reflect(Component, Default, @EditorHidden)]
/// pub struct InternalRig;
/// ```
#[derive(Component, Reflect, Default, Clone, Copy, Debug)]
#[reflect(Component, Default)]
pub struct EditorHidden;

/// Marker for entities that exist as editor-time visual
/// indicators. The save filter skips this entity (and its
/// subtree) so the helper never lands in `.jsn`; the editor
/// viewport still renders it.
///
/// Pattern: under your scene-authored marker (e.g. `PlayerSpawn`),
/// spawn a child carrying `SkipSerialization` plus a `Mesh3d` +
/// `MeshMaterial3d`. The editor renders the helper; the saved
/// scene never includes it.
#[derive(Component, Reflect, Default, Clone, Copy, Debug)]
#[reflect(Component, Default)]
pub struct SkipSerialization;
