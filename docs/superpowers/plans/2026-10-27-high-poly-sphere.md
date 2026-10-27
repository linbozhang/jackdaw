# High-Poly Sphere Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or superpowers:executing-plans to implement these tasks. Do not commit unless the user requests it.

**Goal:** Add `Add > 3D Objects > Sphere (High Poly)` with 1,280 triangular faces while preserving the existing 20-face Sphere.

**Architecture:** Add a fixed-resolution `Brush::sphere_high_poly(radius: f32) -> Self` constructor with explicit topology. The editor creates an ordinary Brush through its existing undoable entity-creation path; the existing geometry serialization and runtime mesh rebuilding remain the source of truth.

**Tech Stack:** Rust, Bevy, Jackdaw Brush geometry, reflected BSN scene documents.

## Global Constraints

- Label: `Sphere (High Poly)`; radius: `0.5`, matching the original Sphere.
- Exactly 1,280 triangles, 642 welded vertices, 1,920 edges; vertices projected onto the sphere.
- Existing `Brush::sphere`, menu item and saved scenes remain unchanged.
- Build topology directly rather than recomputing it with plane intersections.
- Retain the Brush editing/material/physics path; no bare Mesh3d replacement or new serialized component.
- The new operator is `entity.add.sphere_high_poly`, records exactly one undo step through the existing spawn helper, and is registered in the core extension.
- No Inspector subdivision UI, automatic conversion of old objects or smooth-normal changes.
- Leave pre-existing `.gitignore`, `.mimosa/` and `buglist.md` changes untouched. The user subsequently requested a local merge into `main`: commit only this feature, excluding the physics branch's prior commits. Do not push.

## Task 1: Sphere geometry

**Files:** `crates/jackdaw_scene_types/src/types.rs`, `crates/jackdaw_jsn/tests/brush_constructors.rs`.

**Interface:** `pub fn sphere_high_poly(radius: f32) -> Self` on `Brush`.

- [x] Add constructor tests checking face/vertex/edge/loop counts, radii, outward winding, closed shared-edge topology and evaluated geometry. Include an assertion that the existing sphere remains 20 faces.
- [x] Run `cargo test --locked -p jackdaw_jsn --test brush_constructors` and record the missing-constructor failure.
- [x] Construct the icosphere at three subdivision levels. Reuse edge midpoint indices, normalize new vertices onto the radius, construct face planes/tangent axes and call `build_topology_from_face_polygons` directly.
- [x] Re-run the constructor suite; ensure deterministic geometry and finite coordinates at the editor radius.

## Task 2: Editor creation entry

**Files:** `src/entity_ops.rs`, `src/creation_taxonomy.rs`, `tests/guards/record_counts.rs`, `book/src/user-guide/brushes.md`.

**Interface:** `EntityTemplate::SphereHighPoly`, `EntityAddSphereHighPolyOp`.

- [x] Add a failing taxonomy test requiring both sphere entries and their distinct operator actions. Add a headless editor test calling the new operator, checking Brush topology and one history entry, undoing, redoing and checking restored geometry and scene text.
- [x] Verify the new entry test fails before editing production code.
- [x] Extend the enum and label match:

```rust
Self::SphereHighPoly => "Sphere (High Poly)",
```

- [x] Spawn through the existing material-aware creation path:

```rust
EntityTemplate::SphereHighPoly => {
    let id = commands.spawn((
        Name::new("Sphere (High Poly)"),
        crate::brush::Brush::sphere_high_poly(0.5),
        Transform::default(),
        Visibility::default(),
    )).id();
    commands.queue(apply_last_material(id));
    id
}
```

- [x] Add and register the operator:

```rust
#[operator(
    id = "entity.add.sphere_high_poly",
    label = "Sphere (High Poly)",
    description = "Add a sphere with a finer, rounder surface.",
    allows_undo = false
)]
pub(crate) fn entity_add_sphere_high_poly(
    _: In<OperatorParameters>,
    mut commands: Commands,
) -> OperatorResult {
    commands.queue(|world: &mut World| {
        create_entity_in_world(world, EntityTemplate::SphereHighPoly);
    });
    OperatorResult::Finished
}
```

- [x] Add `entry("geometry", "Sphere (High Poly)", op_action::<EntityAddSphereHighPolyOp>())` next to Sphere; include the new ID in the self-pushing history guard list.
- [x] Document both resolutions and the retained flat shading in the brush guide.
- [x] Run the entry/history tests and a root editor compile check.

## Task 3: Persistence and final verification

**Files:** Existing geometry/BSN integration test modules identified from their manifests; only add a focused round-trip test if constructor coverage does not already prove preservation.

- [x] Serialize and load a high-poly Brush through the same reflected scene path as other Brush tests; verify all topology and face geometry survives.
- [x] Run `cargo fmt --all -- --check`, focused geometry/scene tests and `cargo check --locked -p jackdaw --all-targets`.
- [x] Review the implementation diff for inward faces, duplicated vertices, expensive plane-intersection fallback, missing operator registration and undo/redo regressions.
- [x] Fix verified findings, re-run affected tests, and report exact commands and any environmental limitations.
