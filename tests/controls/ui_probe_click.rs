//! The remote UI methods (`jackdaw/ui_click` and friends) drive controls the
//! way a person does: locating them, queueing the gesture, and letting the
//! real picking and observer chain do the rest. Where
//! `synthetic_click.rs` pins the coordinates, this pins the whole call:
//! locate by text, click, and the operator the button names fires.

use crate::util;
use crate::util::OperatorResultExt as _;

use bevy::input::mouse::AccumulatedMouseMotion;
use bevy::prelude::*;
use bevy::remote::BrpResult;
use bevy::ui::UiGlobalTransform;
use bevy::window::{PrimaryWindow, WindowResolution};
use jackdaw::remote::ui_probe::{
    camera_state_handler, ui_click_handler, ui_drag_handler, ui_input_handler,
};
use jackdaw::test_input::SyntheticInput;
use jackdaw::view_modes::ViewModeSettings;
use jackdaw_feathers::button::{ButtonOperatorCall, ButtonProps, button};
use serde_json::{Value, json};

const TOGGLE_WIREFRAME: &str = "view.toggle_wireframe";

fn editor_window() -> App {
    let mut app = util::editor_test_app();
    {
        let mut windows = app
            .world_mut()
            .query_filtered::<&mut Window, With<PrimaryWindow>>();
        let mut window = windows
            .single_mut(app.world_mut())
            .expect("headless apps still have a primary window");
        window.resolution = WindowResolution::new(1600, 1000);
    }
    app
}

/// Run one BRP handler and unwrap its answer.
#[track_caller]
fn call<M>(
    app: &mut App,
    handler: impl bevy::ecs::system::IntoSystem<In<Option<Value>>, BrpResult, M> + 'static,
    params: Value,
) -> Value {
    app.world_mut()
        .run_system_cached_with(handler, Some(params))
        .expect("the handler ran")
        .unwrap_or_else(|err| panic!("the handler refused: {}", err.message))
}

/// Advance until the queued gesture has been delivered, then settle.
fn play(app: &mut App) {
    for _ in 0..200 {
        app.update();
        if app.world().resource::<SyntheticInput>().is_idle() {
            break;
        }
    }
    for _ in 0..8 {
        app.update();
    }
}

/// A click through `jackdaw/ui_click` reaches the button under it: the whole
/// chain from the locator, through the queue, to the operator the button
/// names — with nothing triggered by hand along the way.
#[test]
fn a_ui_click_located_by_text_activates_the_button() {
    let mut app = editor_window();
    let entity = app
        .world_mut()
        .spawn((
            button(ButtonProps::new("Toggle Wireframe")),
            ButtonOperatorCall::new(TOGGLE_WIREFRAME),
        ))
        .id();
    for _ in 0..8 {
        app.update();
    }
    let before = app.world().resource::<ViewModeSettings>().wireframe;

    let answer = call(&mut app, ui_click_handler, json!({ "text": "wireframe" }));
    assert_eq!(answer["clicked"], json!(true), "{answer}");
    // The locator names the caption's button, and the operator that fires is
    // the one the row carrying it declares.
    assert_eq!(answer["target"]["kind"], json!("button"));
    assert_eq!(answer["target"]["operator"], json!(TOGGLE_WIREFRAME));
    let clicked_bits = answer["target"]["entity"].as_u64().expect("an entity");
    let clicked = Entity::try_from_bits(clicked_bits).expect("a live entity id");
    assert!(
        clicked_bits == entity.to_bits()
            || app
                .world()
                .get::<ChildOf>(clicked)
                .is_some_and(|child| child.parent() == entity),
        "the located control is neither the row nor its button: {answer}"
    );
    // The position is in the same window-logical space `input.pointer` takes,
    // and inside the window the test laid out.
    let at_x = answer["at"][0].as_f64().expect("an x") as f32;
    let at_y = answer["at"][1].as_f64().expect("a y") as f32;
    let drawn = app
        .world()
        .get::<UiGlobalTransform>(entity)
        .expect("the button is placed");
    assert!(
        (at_x - drawn.translation.x).abs() < 1600.0 && (0.0..1000.0).contains(&at_y),
        "the click is aimed outside the window: {answer}"
    );

    assert!(
        !app.world().resource::<SyntheticInput>().is_idle(),
        "the click returned before its gesture was queued"
    );
    play(&mut app);

    assert_eq!(
        app.world().resource::<ViewModeSettings>().wireframe,
        !before,
        "the ui_click never reached the button's operator",
    );
}

/// The refusals say why: a disabled control refuses rather than clicking into
/// the void, and a locator two controls answer to lists both.
#[test]
fn a_ui_click_refuses_what_it_cannot_honestly_click() {
    let mut app = editor_window();
    // The disabled button carries no operator: the availability driver owns
    // `InteractionDisabled` on every operator button and re-enables one
    // whose operator is available, so a disabled operator button does not
    // stay disabled. A plain button keeps its marker for good.
    app.world_mut().spawn((
        button(ButtonProps::new("Save World")),
        bevy::ui::InteractionDisabled,
    ));
    app.world_mut().spawn((
        button(ButtonProps::new("Save World")),
        ButtonOperatorCall::new(TOGGLE_WIREFRAME),
    ));
    for _ in 0..8 {
        app.update();
    }

    // Ambiguous: both buttons read "Save World".
    let error = app
        .world_mut()
        .run_system_cached_with(ui_click_handler, Some(json!({ "text": "Save World" })))
        .expect("the handler ran")
        .expect_err("an ambiguous locator is a refusal");
    assert!(
        error.message.contains("candidates"),
        "the refusal does not list what matched: {}",
        error.message
    );
    let listed = error
        .data
        .as_ref()
        .and_then(|data| data.get("candidates"))
        .and_then(Value::as_array)
        .expect("the candidates ride along");
    assert_eq!(listed.len(), 2, "{error:?}");

    // `index` picks between them; 1 is the enabled one.
    let picked = call(
        &mut app,
        ui_click_handler,
        json!({ "text": "Save World", "index": 1 }),
    );
    assert_eq!(picked["clicked"], json!(true), "{picked}");
    play(&mut app);

    // The disabled one refuses with the reason.
    let disabled = app
        .world_mut()
        .run_system_cached_with(
            ui_click_handler,
            Some(json!({ "text": "Save World", "index": 0 })),
        )
        .expect("the handler ran")
        .expect_err("a disabled control is a refusal");
    assert!(
        disabled.message.contains("disabled"),
        "the refusal does not say why: {}",
        disabled.message
    );

    // Nothing matched the gesture at all: the queue is empty.
    let _ = app
        .world_mut()
        .run_system_cached_with(ui_click_handler, Some(json!({ "text": "No Such Thing" })))
        .expect("the handler ran")
        .expect_err("nothing matches");
    assert!(
        app.world()
            .get_resource::<SyntheticInput>()
            .is_none_or(SyntheticInput::is_idle),
        "a refused click queued a gesture anyway"
    );
}

/// `ui_input` is one gesture: the click that focuses the field, the typing,
/// and the Enter that commits, so no script's timing can land between them.
/// The field is located by `entity` here — `text` is what gets typed, so it
/// cannot also be the locator.
#[test]
fn a_ui_input_types_and_commits_in_one_gesture() {
    use bevy::feathers::controls::FeathersTextInput;
    use jackdaw_feathers::text_edit::{TextEditProps, TextEditValue, text_edit};

    let mut app = editor_window();
    // A row with room in it: a field squeezed into an auto-sized corner never
    // lays out an input wide enough to click.
    let host = app
        .world_mut()
        .spawn(Node {
            width: px(400.0),
            padding: UiRect::all(px(40)),
            ..default()
        })
        .id();
    let root = app
        .world_mut()
        .spawn((
            text_edit(TextEditProps::default().with_default_value("0")),
            ChildOf(host),
        ))
        .id();
    for _ in 0..8 {
        app.update();
    }
    // The input a caller reads off `ui_tree` (kind `text_input`), found the
    // way this suite finds things rather than by reaching into the widget.
    let mut stack = vec![root];
    let mut input = None;
    while let Some(current) = stack.pop() {
        if app.world().get::<FeathersTextInput>(current).is_some() {
            input = Some(current);
            break;
        }
        if let Some(children) = app.world().get::<Children>(current) {
            stack.extend(children.iter());
        }
    }
    let input = input.expect("the field holds a text input");

    let answer = call(
        &mut app,
        ui_input_handler,
        json!({ "entity": input.to_bits(), "text": "entity: 42", "commit": "enter" }),
    );
    assert_eq!(answer["typed"], json!(true), "{answer}");
    play(&mut app);

    let typed = app
        .world()
        .get::<TextEditValue>(root)
        .map(|value| value.0.clone())
        .unwrap_or_default();
    assert_eq!(
        typed, "entity: 42",
        "the typed text did not reach the focused field (got {typed:?})"
    );
}

/// A slider drag moves the value: `ui_drag` moves onto the control, presses,
/// and interpolates across its box. The widget's answer is its `ValueChange`
/// ramp — the editor's panels, not the widget, keep `SliderValue` in step.
#[test]
fn a_ui_drag_moves_a_slider() {
    use bevy::feathers::controls::FeathersSlider;
    use bevy::ui_widgets::{SliderValue, ValueChange};

    #[derive(Resource, Default)]
    struct Ramp(Vec<f32>);

    let mut app = editor_window();
    app.init_resource::<Ramp>();
    app.add_observer(|change: On<ValueChange<f32>>, mut ramp: ResMut<Ramp>| {
        ramp.0.push(change.value);
    });

    let column = app.world_mut().spawn(Node::default()).id();
    let slider = app
        .world_mut()
        .spawn_scene(bsn! {
            @FeathersSlider { @min: 0.0, @max: 1.0 }
            SliderValue(0.0)
            Node {
                width: px(200.0),
                height: px(24.0),
            }
        })
        .expect("the slider spawns")
        .id();
    app.world_mut().entity_mut(slider).insert(ChildOf(column));
    for _ in 0..8 {
        app.update();
    }

    let answer = call(
        &mut app,
        ui_drag_handler,
        json!({ "entity": slider.to_bits(), "from": [0.05, 0.5], "to": [0.95, 0.5] }),
    );
    assert_eq!(answer["dragged"], json!(true), "{answer}");
    play(&mut app);

    let ramp = app.world().resource::<Ramp>().0.clone();
    assert!(
        !ramp.is_empty(),
        "the drag raised no ValueChange; the gesture never reached the widget"
    );
    let last = ramp.last().copied().unwrap_or_default();
    assert!(
        last > 0.8,
        "the drag ended at {last} rather than near the right end: {ramp:?}"
    );
    assert!(
        ramp[0] < ramp[ramp.len() - 1],
        "the ramp never climbed: {ramp:?}"
    );
}

/// Raw motion accumulates the frame it is injected: the `First`-to-
/// `PreUpdate` hand-off a real `DeviceEvent` has, which is what makes
/// `input.motion` able to turn a camera.
#[test]
fn injected_motion_accumulates_the_frame_it_is_queued() {
    let mut app = util::editor_test_app();
    jackdaw::boot_ops::run_op_clause(app.world_mut(), "input.motion dx=40 dy=-10 steps=4")
        .expect("the clause dispatches")
        .assert_finished();

    let mut seen = Vec2::ZERO;
    for _ in 0..40 {
        app.update();
        seen += app
            .world()
            .get_resource::<AccumulatedMouseMotion>()
            .map_or(Vec2::ZERO, |motion| motion.delta);
        if app.world().resource::<SyntheticInput>().is_idle() {
            break;
        }
    }
    assert_eq!(seen, Vec2::new(40.0, -10.0));
}

/// `camera_state` reports the compass yaw and pitch `view.orbit` would take,
/// from a camera placed the way that operator places one.
#[test]
fn camera_state_reports_compass_yaw_and_pitch() {
    let mut app = util::editor_test_app();
    let yaw = 135.0_f32.to_radians();
    let pitch = 30.0_f32.to_radians();
    let offset = Vec3::new(
        yaw.sin() * pitch.cos(),
        pitch.sin(),
        yaw.cos() * pitch.cos(),
    );
    let camera = app
        .world_mut()
        .spawn((
            jackdaw::viewport::MainViewportCamera,
            Transform::from_translation(offset * 10.0).looking_at(Vec3::ZERO, Vec3::Y),
            Projection::Perspective(default()),
        ))
        .id();
    app.world_mut()
        .resource_mut::<jackdaw::viewport::ActiveViewport>()
        .camera = Some(camera);

    let state = call(&mut app, camera_state_handler, json!({}));
    assert_eq!(state["camera"], json!(camera.to_bits()), "{state}");
    let read_yaw = state["yaw"].as_f64().expect("a yaw");
    let read_pitch = state["pitch"].as_f64().expect("a pitch");
    assert!((read_yaw - 135.0).abs() < 0.01, "yaw read {read_yaw}");
    assert!((read_pitch - 30.0).abs() < 0.01, "pitch read {read_pitch}");
    assert_eq!(state["projection"], json!("perspective"), "{state}");
    assert_eq!(state["fly"], json!(false), "{state}");
}
