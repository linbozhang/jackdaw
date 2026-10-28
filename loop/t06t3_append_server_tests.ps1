# Append T3 tests to the server.rs test module.
$target = 'E:\Project\rust\jackdaw\src\remote\server.rs'
$append = @'

    // ------------------------------------------------- T3: pie + selection --

    /// A world with the resources the new faces read: a selection, a PIE
    /// projection with one ephemeral and one mapped authored entity, a
    /// pending live edit, and a session that never launched anything.
    fn pie_face_world() -> World {
        let mut world = World::new();
        world.init_resource::<crate::selection::Selection>();
        world.init_resource::<crate::pie_projection::PieProjection>();
        world.init_resource::<crate::pie_mirror::PieInstances>();
        world.init_resource::<crate::pie_mirror::PieViewMode>();
        world.init_resource::<crate::live_edits::LiveEditLog>();

        let authored = world
            .spawn((bevy::prelude::Name::new("Authored"), bevy::prelude::Transform::default()))
            .id();
        world
            .spawn((
                crate::pie_projection::PieEphemeral,
                bevy::prelude::Name::new("GameActor"),
            ));
        let mut projection = world
            .resource_mut::<crate::pie_projection::PieProjection>();
        projection.by_bits.insert(0xA0, authored);
        world.insert_non_send(crate::pie::PieSession::default());
        world
    }

    /// The face over a stopped session: stopped, no instances, and the
    /// projection's shape counted from the world itself.
    #[test]
    fn pie_face_reports_a_stopped_session() {
        let mut world = pie_face_world();

        // One pending live edit, so the count is exercised.
        {
            let key = crate::live_edits::LiveEditKey {
                bits: 0xA0,
                type_path: "T".to_string(),
                field_path: String::new(),
            };
            let entry = crate::live_edits::LiveEditEntry {
                node_id: None,
                baseline: None,
                live_value: serde_json::json!(null),
                label: "probe".to_string(),
            };
            world
                .resource_mut::<crate::live_edits::LiveEditLog>()
                .entries
                .push((key, entry));
        }

        let answer = pie_handler(In(None), &mut world).expect("the face answers");
        let face = answer.as_object().expect("an object");
        assert_eq!(face["status"], "stopped");
        assert_eq!(face["instances"].as_array().map(Vec::len), Some(0));
        assert_eq!(face["live_edits"], 1);
        let projection = face["projection"].as_object().expect("an object");
        assert_eq!(projection["entities"], 1, "one mapped preview entity");
        assert_eq!(projection["authored"], 1, "the mapped one is authored");
        assert_eq!(projection["ephemeral"], 1, "one ephemeral, unmapped");
        assert_eq!(face["view_mode"], "scene");
    }

    /// The selection face: set by bits, by name, and clear.
    #[test]
    fn selection_set_takes_bits_names_and_clears() {
        let mut world = pie_face_world();
        let entity = world
            .query_filtered::<Entity, With<bevy::prelude::Name>>()
            .iter(&world)
            .find(|e| world.get::<bevy::prelude::Name>(*e).is_some_and(|n| n.as_str() == "Authored"))
            .expect("the authored entity");

        // By bits: the id `scene_tree` would report.
        let answer = selection_set_handler(
            In(Some(json!({ "entities": [entity.to_bits()] }))),
            &mut world,
        )
        .expect("set by bits");
        assert_eq!(
            answer["selection"][0]["name"], "Authored",
            "the answer names what it selected"
        );
        assert_eq!(
            world.resource::<crate::selection::Selection>().entities,
            vec![entity]
        );
        assert!(world.get::<crate::selection::Selected>(entity).is_some());

        // By name.
        selection_set_handler(
            In(Some(json!({ "names": ["Authored"] }))),
            &mut world,
        )
        .expect("set by name");
        assert_eq!(
            world.resource::<crate::selection::Selection>().entities,
            vec![entity]
        );

        // Clear: the resource empties and the marker goes.
        selection_set_handler(In(Some(json!({ "clear": true }))), &mut world)
            .expect("cleared");
        assert!(world.resource::<crate::selection::Selection>().entities.is_empty());
        assert!(world.get::<crate::selection::Selected>(entity).is_none());

        // A dead id is refused, not silently dropped.
        let refused = selection_set_handler(
            In(Some(json!({ "entities": [1u64 << 40] }))),
            &mut world,
        );
        assert!(refused.is_err(), "an unknown id must refuse");
    }

    /// The `pie_stopped` wait over a session that began and ended entirely
    /// between two polls: the launch count moved, so the wait satisfies
    /// immediately — the race the live QA worked around by polling the
    /// status face (T1 deviation 1, closed here).
    #[test]
    fn a_pie_stopped_wait_satisfies_when_the_session_already_ended() {
        let mut world = pie_face_world();
        // The session launched once (and is gone again): the count moved.
        {
            let mut session = world.non_send_mut::<crate::pie::PieSession>();
            session.launches += 1;
        }

        let answer = pie_wait(&mut world, &json!({ "until": "pie_stopped" }), "pie_stopped", 1)
            .expect("the wait answers");
        assert!(
            answer.is_some(),
            "a stopped status over a counted session satisfies immediately"
        );
    }

    /// The same wait over a world where nothing ever launched still holds:
    /// the count is the proof, and it did not move.
    #[test]
    fn a_pie_stopped_wait_holds_when_nothing_ever_ran() {
        let mut world = pie_face_world();
        let answer = pie_wait(&mut world, &json!({ "until": "pie_stopped" }), "pie_stopped", 1)
            .expect("the wait answers");
        assert!(answer.is_none(), "nothing ran: the wait keeps holding");
    }
'@
[IO.File]::WriteAllText($target, [IO.File]::ReadAllText($target) + $append, (New-Object System.Text.UTF8Encoding($false)))
Write-Host 'appended'
