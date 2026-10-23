//! Escape-to-cancel for modal operators: the hard guarantee.
//!
//! The modal context's `ModalCancel` action (Escape, priority 10,
//! `consume_input`) carries an `OperatorAction("modal.cancel")` tag, so its
//! `Fire` dispatches the cancel operator through
//! `dispatch_operator_actions`. Every running modal must therefore tear down
//! on Escape — including the ones that never polled `ModalInputs::cancel()`
//! themselves (measure, draw-brush Add, gizmo drags, terrain strokes,
//! sub-element drags), which before the tag existed were unreachable by
//! Escape while their context swallowed the key.
//!
//! The tests drive the real input stack: the synthetic `input.key` operator
//! queues genuine window key events, the action layer evaluates them, and
//! the dispatch must reach the operator framework and tear the modal down.

use crate::util;
use crate::util::OperatorResultExt as _;

use bevy::prelude::*;
use jackdaw::measure_tool::MeasureToolState;
use jackdaw::test_input::SyntheticInput;
use jackdaw_api::prelude::*;
use jackdaw_api_internal::lifecycle::ActiveModalOperator;
use jackdaw_api_internal::tools::ToolStatus;

/// True iff at least one entity in the world has `ActiveModalOperator`
/// attached. Matches the dispatcher's view of "modal is running."
fn modal_running(app: &mut App) -> bool {
    app.world_mut()
        .query::<&ActiveModalOperator>()
        .iter(app.world())
        .next()
        .is_some()
}

/// Run one `JACKDAW_RUN_OP` clause, then advance until its synthetic beats
/// have played out. Bounded, so a gesture that never drains fails the test
/// rather than hanging it.
fn run(app: &mut App, clause: &str) {
    jackdaw::boot_ops::run_op_clause(app.world_mut(), clause)
        .unwrap_or_else(|err| panic!("{clause}: dispatch errored: {err}"))
        .assert_finished();
    for _ in 0..600 {
        app.update();
        if app.world().resource::<SyntheticInput>().is_idle() {
            return;
        }
    }
    panic!("{clause}: the synthetic gesture never drained");
}

fn settle(app: &mut App) {
    for _ in 0..8 {
        app.update();
    }
}

/// Escape cancels the measure tool, whose body never polled cancel on its
/// own: the dispatch chain alone must tear the modal down and reset the
/// tool's state. The status line the tool raised must drop with it, and a
/// second Escape with nothing running must be a harmless no-op.
#[test]
fn escape_cancels_the_measure_modal_and_resets_it() {
    let mut app = util::editor_test_app();

    app.world_mut()
        .operator("tools.measure_distance")
        .call()
        .expect("measure dispatch errored")
        .assert_running();
    assert!(
        modal_running(&mut app),
        "the running measure modal owns the modal slot"
    );
    assert_eq!(
        app.world().resource::<ToolStatus>().0.as_deref(),
        Some("Measure: LMB sets points · Esc or RMB cancels"),
        "the tool announces how it is cancelled"
    );

    run(&mut app, "input.key key=Escape action=tap");

    assert!(
        !modal_running(&mut app),
        "Escape tore the measure modal down"
    );
    let measure = app.world().resource::<MeasureToolState>();
    assert!(
        !measure.active && !measure.initialized,
        "the cancel system reset the measure state"
    );
    assert!(
        app.world().resource::<ToolStatus>().0.is_none(),
        "the status line dropped once no modal runs"
    );

    // Nothing is running now; Escape must stay a quiet no-op rather than
    // panic or plant a phantom modal.
    run(&mut app, "input.key key=Escape action=tap");
    assert!(!modal_running(&mut app), "a bare Escape is a no-op");
}

/// Right-click leaves the measure tool the way every pointer-driven modal
/// gesture behaves, without Escape at all.
#[test]
fn right_click_cancels_the_measure_modal() {
    let mut app = util::editor_test_app();

    app.world_mut()
        .operator("tools.measure_distance")
        .call()
        .expect("measure dispatch errored")
        .assert_running();

    run(
        &mut app,
        "input.pointer x=400 y=300 action=press button=secondary",
    );
    run(
        &mut app,
        "input.pointer x=400 y=300 action=release button=secondary",
    );

    assert!(
        !modal_running(&mut app),
        "RMB cancelled the measure modal through its body"
    );
    let measure = app.world().resource::<MeasureToolState>();
    assert!(
        !measure.active && !measure.initialized,
        "the cancel system reset the measure state"
    );
}

/// The hard guarantee, swept over every modal operator: whichever modal is
/// running, one Escape cancels it. Operators whose availability gate refuses
/// the empty headless scene (they need a cursor over geometry or a fixture)
/// answer `Cancelled` and are skipped; everything that reaches `Running`
/// must come down on Escape.
#[test]
fn escape_cancels_every_running_modal_operator() {
    let mut app = util::editor_test_app();
    let modal_ids: Vec<&'static str> = app
        .world_mut()
        .query::<&jackdaw_api_internal::lifecycle::OperatorEntity>()
        .iter(app.world())
        .filter(|op| op.is_modal())
        .map(jackdaw_api_internal::lifecycle::OperatorEntity::id)
        .collect();
    assert!(
        !modal_ids.is_empty(),
        "expected at least one modal operator to be registered"
    );

    let mut cancelled = 0;
    for id in modal_ids {
        // Each iteration starts fresh: cancel any modal a previous one left.
        let _ = app.world_mut().operator("modal.cancel").call();
        app.update();

        let result = app
            .world_mut()
            .operator(id)
            .call()
            .unwrap_or_else(|err| panic!("{id}: dispatch errored: {err}"));
        match result {
            OperatorResult::Running => {}
            OperatorResult::Cancelled => continue,
            other => panic!("{id}: expected Running or Cancelled, got {other:?}"),
        }
        assert!(modal_running(&mut app), "{id}: Running but no active modal");

        run(&mut app, "input.key key=Escape action=tap");

        assert!(!modal_running(&mut app), "{id}: Escape cancelled the modal");
        cancelled += 1;
    }
    assert!(
        cancelled > 0,
        "the sweep must exercise at least one real modal"
    );
}

/// Escape held through a modal's start is swallowed once (`require_reset`):
/// the press that was already down when the modal context activated does not
/// fire, and the key must be released and pressed again to cancel. This is
/// the documented action-layer semantics, pinned here so the cancel chain is
/// not blamed for the swallow.
#[test]
fn escape_held_through_modal_start_needs_a_repress() {
    let mut app = util::editor_test_app();

    run(&mut app, "input.key key=Escape action=press");
    app.world_mut()
        .operator("tools.measure_distance")
        .call()
        .expect("measure dispatch errored")
        .assert_running();
    settle(&mut app);
    assert!(
        modal_running(&mut app),
        "the Escape held from before the modal started was swallowed"
    );

    run(&mut app, "input.key key=Escape action=release");
    run(&mut app, "input.key key=Escape action=tap");

    assert!(
        !modal_running(&mut app),
        "a fresh Escape after the release cancels the modal"
    );
}
