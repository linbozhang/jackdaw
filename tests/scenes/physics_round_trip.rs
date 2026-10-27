//! A scene's physics components survive an open and a save. Since the
//! physics extension ships builtin (T10-T1), the avian types register and
//! resolve in every editor session; before T10-T3's registration fix they
//! survived only as unresolved types, which is the fallback the document
//! keeps for types no loaded extension knows. Either way the components
//! round-trip through open and re-save unchanged.

use crate::util;

const SCENE: &str = "bevy_ecs::hierarchy::Children [
    #Crate
    avian3d::dynamics::rigid_body::RigidBody::Dynamic
    avian3d::dynamics::rigid_body::LinearDamping(0.25)
    jackdaw_avian_integration::AvianCollider(avian3d::collision::collider::constructor::ColliderConstructor::Cuboid {
        x_length: 1.5,
        y_length: 2.0,
        z_length: 3.0,
    })
]
";

#[test]
fn physics_components_survive_an_open_and_resave() {
    let mut app = util::editor_test_app();
    let dir = std::env::temp_dir().join(format!("jd_physics_resave_{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("scene dir");
    let path = dir.join("scene.bsn");
    std::fs::write(&path, SCENE).expect("write scene");

    jackdaw::scene_io::load_scene_from_file(app.world_mut(), &path);
    app.update();

    // The builtin physics extension registers avian's types, so they
    // resolve; anything the editor cannot resolve would ride the
    // UnresolvedTypes fallback instead, which the re-save below also
    // preserves.
    let unresolved = app
        .world()
        .resource::<jackdaw_bsn::UnresolvedTypes>()
        .types();
    assert!(
        !unresolved
            .iter()
            .any(|type_path| type_path.starts_with("avian3d::")),
        "the builtin physics extension resolves avian's types: {unresolved:?}"
    );

    let emitted = jackdaw::scene_io::emit_bsn_scene_with_inline_assets(app.world_mut(), &dir);
    for needle in [
        "avian3d::dynamics::rigid_body::RigidBody::Dynamic",
        "avian3d::dynamics::rigid_body::LinearDamping(0.25)",
        "jackdaw_avian_integration::AvianCollider",
        "ColliderConstructor::Cuboid",
        "x_length: 1.5",
        "z_length: 3.0",
    ] {
        assert!(
            emitted.contains(needle),
            "re-save dropped `{needle}`; got:\n{emitted}"
        );
    }

    let _ = std::fs::remove_dir_all(&dir);
}
