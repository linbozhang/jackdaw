use std::collections::HashSet;

use bevy::math::{Vec2, Vec3};
use jackdaw_geometry::{BrushFaceData, compute_brush_topology, compute_face_tangent_axes};
use jackdaw_scene_types::{Brush, BrushTopology};

#[test]
fn cuboid_has_8_verts_12_edges_6_polys_24_loops() {
    let brush = Brush::cuboid(0.5, 0.5, 0.5);
    assert_eq!(brush.faces.len(), 6);
    assert_eq!(brush.topology.vertices.len(), 8);
    assert_eq!(brush.topology.edges.len(), 12);
    assert_eq!(brush.topology.polygons.len(), 6);
    assert_eq!(brush.topology.loops.len(), 24);
    assert_eq!(brush.faces.len(), brush.topology.polygons.len());
}

#[test]
fn prism_triangle_base_has_5_polys_5_faces() {
    let base = vec![
        Vec3::new(0.0, 0.0, 0.0),
        Vec3::new(1.0, 0.0, 0.0),
        Vec3::new(0.5, 1.0, 0.0),
    ];
    let brush = Brush::prism(&base, Vec3::Z, 1.0).expect("prism");
    assert_eq!(brush.faces.len(), 5); // 3 sides + top + bottom
    assert_eq!(brush.topology.polygons.len(), 5);
    assert_eq!(brush.topology.vertices.len(), 6); // 3 base + 3 top
}

#[test]
fn sphere_constructor_populates_topology() {
    // Icosahedral sphere: 20 triangular faces, 12 vertices, 30 edges, 60 loops.
    let brush = Brush::sphere(1.0);
    assert_eq!(brush.faces.len(), 20);
    assert!(
        !brush.topology.polygons.is_empty(),
        "sphere topology must be populated"
    );
    assert_eq!(brush.topology.polygons.len(), 20);
    assert_eq!(brush.topology.vertices.len(), 12);
    assert_eq!(brush.topology.edges.len(), 30);
    assert_eq!(brush.topology.loops.len(), 60);
}

#[test]
fn high_poly_sphere_has_642_verts_1920_edges_1280_polys_3840_loops() {
    let brush = Brush::sphere_high_poly(0.5);
    assert_eq!(brush.faces.len(), 1280);
    assert_eq!(brush.topology.vertices.len(), 642);
    assert_eq!(brush.topology.edges.len(), 1920);
    assert_eq!(brush.topology.polygons.len(), 1280);
    assert_eq!(brush.topology.loops.len(), 3840);
    assert!(brush.topology.polygons.iter().all(|p| p.loop_total == 3));
}

#[test]
fn high_poly_sphere_vertices_follow_positive_radius() {
    for radius in [0.01, 0.5, 1.0, 2.5, 100.0] {
        let brush = Brush::sphere_high_poly(radius);
        let tolerance = radius * 2e-6;
        let mut positions = HashSet::new();
        for vertex in &brush.topology.vertices {
            let p = vertex.position;
            assert!(p.is_finite());
            assert!((p.length() - radius).abs() < tolerance, "radius {radius}");
            assert!(
                positions.insert(p.to_array().map(f32::to_bits)),
                "duplicate vertex"
            );
        }
        let center = brush
            .topology
            .vertices
            .iter()
            .map(|v| v.position)
            .sum::<Vec3>()
            / brush.topology.vertices.len() as f32;
        assert!(
            center.length() < tolerance,
            "sphere must be centered at the origin"
        );
    }
}

#[test]
fn high_poly_sphere_winding_planes_and_uvs_face_outward() {
    let default_face = BrushFaceData::default();
    for radius in [0.01, 0.5, 2.5, 100.0] {
        let brush = Brush::sphere_high_poly(radius);
        let tolerance = radius * 2e-6;
        for (i, face) in brush.faces.iter().enumerate() {
            let ring: Vec<Vec3> = brush
                .topology
                .face_ring(i)
                .map(|v| brush.topology.vertices[v as usize].position)
                .collect();
            let normal = (ring[1] - ring[0]).cross(ring[2] - ring[0]).normalize();
            let center = (ring[0] + ring[1] + ring[2]) / 3.0;
            assert!(normal.dot(center) > 0.0, "face {i} winding must be outward");
            assert!(normal.dot(face.plane.normal) > 1.0 - 2e-6);
            assert!((face.plane.normal.length() - 1.0).abs() < 2e-6);
            assert!(face.plane.distance > 0.0);
            for p in &ring {
                assert!((face.plane.normal.dot(*p) - face.plane.distance).abs() < tolerance);
            }
            for vertex in &brush.topology.vertices {
                assert!(
                    face.plane.normal.dot(vertex.position) <= face.plane.distance + tolerance,
                    "vertex outside face {i} half-space"
                );
            }
            let (u, v) = compute_face_tangent_axes(face.plane.normal);
            assert_eq!(face.uv_u_axis, u);
            assert_eq!(face.uv_v_axis, v);
            assert!((u.length() - 1.0).abs() < 2e-6);
            assert!((v.length() - 1.0).abs() < 2e-6);
            assert!(u.dot(face.plane.normal).abs() < 2e-6);
            assert!(v.dot(face.plane.normal).abs() < 2e-6);
            assert_eq!(face.uv_scale, Vec2::ONE);
            assert_eq!(face.uv_offset, Vec2::ZERO);
            assert_eq!(face.uv_rotation, 0.0);
            assert_eq!(face.material, default_face.material);
            assert!(!face.is_cap);
        }
    }
}

#[test]
fn high_poly_sphere_is_closed_with_shared_canonical_edges() {
    let brush = Brush::sphere_high_poly(0.5);
    let topology = &brush.topology;
    let mut edges = HashSet::new();
    let mut vertex_used = vec![false; topology.vertices.len()];
    let mut edge_users = vec![Vec::new(); topology.edges.len()];
    for edge in &topology.edges {
        assert!(edge.v[0] < edge.v[1]);
        assert!((edge.v[1] as usize) < topology.vertices.len());
        assert!(edges.insert(edge.v), "duplicate edge");
        assert!(edge.flags.is_empty());
    }
    for (face_index, polygon) in topology.polygons.iter().enumerate() {
        assert_eq!(polygon.loop_start as usize, face_index * 3);
        assert_eq!(polygon.loop_total, 3);
        let start = polygon.loop_start as usize;
        for corner in 0..3 {
            let current = &topology.loops[start + corner];
            let next = &topology.loops[start + (corner + 1) % 3];
            vertex_used[current.vert as usize] = true;
            let mut endpoints = [current.vert, next.vert];
            endpoints.sort();
            assert_eq!(topology.edges[current.edge as usize].v, endpoints);
            edge_users[current.edge as usize].push([current.vert, next.vert]);
        }
    }
    assert!(vertex_used.into_iter().all(|used| used));
    for users in edge_users {
        assert_eq!(
            users.len(),
            2,
            "closed sphere edges have two incident faces"
        );
        assert_eq!(
            users[0],
            [users[1][1], users[1][0]],
            "adjacent winding must agree"
        );
    }
    assert_eq!(
        topology.vertices.len() + topology.polygons.len(),
        topology.edges.len() + 2
    );
}

#[cfg(feature = "render")]
#[test]
fn high_poly_sphere_evaluates_authored_topology_and_renders_flat_triangles() {
    use jackdaw_geometry::build_face_render_buffers;
    use jackdaw_scene_types::evaluate_brush_geometry;

    let brush = Brush::sphere_high_poly(0.5);
    let (vertices, rings, faces) = evaluate_brush_geometry(&brush, None);
    assert_eq!(vertices.len(), 642);
    assert_eq!(rings.len(), 1280);
    assert_eq!(faces.len(), 1280);
    let mut triangle_count = 0;
    for (i, (ring, face)) in rings.iter().zip(&faces).enumerate() {
        assert_eq!(
            *ring,
            brush
                .topology
                .face_ring(i)
                .map(|v| v as usize)
                .collect::<Vec<_>>()
        );
        let buffers = build_face_render_buffers(&vertices, ring, face);
        assert_eq!(buffers.positions.len(), 3);
        assert_eq!(buffers.normals, vec![face.plane.normal.to_array(); 3]);
        assert_eq!(buffers.uvs.len(), 3);
        assert_eq!(buffers.tangents.len(), 3);
        assert!(buffers.uvs.iter().flatten().all(|value| value.is_finite()));
        assert!(
            buffers
                .tangents
                .iter()
                .flatten()
                .all(|value| value.is_finite())
        );
        assert_eq!(buffers.tri_count(), 1);
        let [a, b, c] = buffers.indices.as_slice() else {
            panic!("expected one triangle")
        };
        let a = Vec3::from_array(buffers.positions[*a as usize]);
        let b = Vec3::from_array(buffers.positions[*b as usize]);
        let c = Vec3::from_array(buffers.positions[*c as usize]);
        assert!((b - a).cross(c - a).dot(face.plane.normal) > 0.0);
        triangle_count += buffers.tri_count();
    }
    assert_eq!(triangle_count, 1280);

    // Inconsistent planes must not trigger the legacy cubic plane-intersection
    // fallback when authored topology is present.
    let mut changed_planes = brush.clone();
    for face in &mut changed_planes.faces {
        face.plane.distance = 10.0;
    }
    let (cached_vertices, cached_rings, _) = evaluate_brush_geometry(&changed_planes, None);
    assert_eq!(cached_vertices, vertices);
    assert_eq!(cached_rings, rings);
}

#[cfg(feature = "render")]
#[test]
fn high_poly_sphere_modifier_evaluation_preserves_mirrored_winding_and_planes() {
    use jackdaw_geometry::{MeshMirror, Modifier, ModifierEntry, ModifierStack};
    use jackdaw_scene_types::evaluate_brush_geometry;

    let brush = Brush::sphere_high_poly(0.5);
    let stack = ModifierStack {
        modifiers: vec![ModifierEntry::new(Modifier::Mirror(MeshMirror {
            offset: Vec3::X,
            merge: false,
            ..Default::default()
        }))],
    };
    let (vertices, rings, faces) = evaluate_brush_geometry(&brush, Some(&stack));
    assert_eq!(vertices.len(), 1284);
    assert_eq!(rings.len(), 2560);
    assert_eq!(faces.len(), 2560);
    for (i, vertex) in brush.topology.vertices.iter().enumerate() {
        assert_eq!(vertices[i], vertex.position);
        let mut expected = vertex.position;
        expected.x = 2.0 - expected.x;
        assert!((vertices[642 + i] - expected).length() < 2e-6);
    }
    for (ring, face) in rings.iter().zip(&faces) {
        assert_eq!(ring.len(), 3);
        let [a, b, c] = [vertices[ring[0]], vertices[ring[1]], vertices[ring[2]]];
        assert!((b - a).cross(c - a).normalize().dot(face.plane.normal) > 1.0 - 2e-6);
        for p in [a, b, c] {
            assert!((face.plane.normal.dot(p) - face.plane.distance).abs() < 2e-6);
        }
    }
}

#[test]
fn every_primitive_constructor_populates_topology() {
    // Invariant: every primitive constructor returns a Brush with both
    // `faces` and `topology` populated, so downstream code never has
    // to branch on whether topology exists.
    let cuboid = Brush::cuboid(0.5, 0.5, 0.5);
    assert!(!cuboid.topology.polygons.is_empty(), "cuboid");

    let prism = Brush::prism(
        &[
            Vec3::new(0.0, 0.0, 0.0),
            Vec3::new(1.0, 0.0, 0.0),
            Vec3::new(0.5, 1.0, 0.0),
        ],
        Vec3::Z,
        1.0,
    )
    .expect("prism");
    assert!(!prism.topology.polygons.is_empty(), "prism");

    let sphere = Brush::sphere(1.0);
    assert!(!sphere.topology.polygons.is_empty(), "sphere");
}

#[test]
fn compute_brush_topology_populates_legacy_planes_only_brush() {
    // Simulate a deserialized legacy brush: faces only, empty topology.
    // The standalone helper should recover a valid topology.
    let template = Brush::cuboid(0.5, 0.5, 0.5);
    let legacy = Brush {
        faces: template.faces.clone(),
        topology: BrushTopology::default(),
    };
    assert!(
        legacy.topology.polygons.is_empty(),
        "starting point must have empty topology"
    );

    let recovered = compute_brush_topology(&legacy.faces);
    assert_eq!(
        recovered.polygons.len(),
        legacy.faces.len(),
        "topology poly count matches face count"
    );
    assert!(!recovered.vertices.is_empty());
    assert!(!recovered.edges.is_empty());
    assert!(!recovered.loops.is_empty());
}
