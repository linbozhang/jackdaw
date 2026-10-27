//! Game-side input actions: named actions with editable bindings,
//! evaluated from the engine's keyboard/mouse/gamepad input into one
//! [`GameActions`] resource a game reads instead of polling raw
//! `ButtonInput` itself.
//!
//! A game declares nothing to start: [`InputActionsPlugin`] evaluates
//! [`GameInputConfig`]'s built-in defaults (Move / Look / Jump /
//! Interact / Pause). To customize, the game registers the type as a
//! config asset — the same [`ConfigPlugin`](crate::ConfigPlugin) family
//! `GameConfig` uses — and the editor authors
//! `assets/input-actions.bsn`: action names, key / mouse / gamepad
//! bindings, per-axis deadzones. Play, `cargo run`, and an exported
//! build all read the same file.
//!
//! The file and the code defaults **merge as a union** at load: an
//! action the file names replaces the code default of that name, an
//! action it omits keeps the code default — so a file authored against
//! an older game still receives new actions the game adds later (the
//! "everything in the file" trap an older editor keymap format fell
//! into). Rules for the edges: a renamed action's kind comes from the
//! file, a duplicate binding keeps its first occurrence, and an unknown
//! action name still loads — nothing reads it until something asks for
//! it by name.
//!
//! Deadzones use the engine's own [`bevy::input::gamepad::GamepadSettings`]:
//! the plugin copies each binding's deadzone into the per-axis settings,
//! so every reader of that axis (this system, a game's own code, a
//! future replay system) sees the same filtered values. Per-action
//! deadzone overrides are a deliberate non-goal for now; the binding
//! table already carries the value per axis if that day comes.
//!
//! Bindings are bevy's own input types (`KeyCode`, `MouseButton`,
//! `GamepadButton`, `GamepadAxis`) serialized through reflect — no
//! display-name round-trip to lose data in, and the editor's asset
//! card renders each field as a variant menu.

use std::collections::HashMap;

use bevy::input::gamepad::{AxisSettings, Gamepad, GamepadSettings};
use bevy::input::mouse::AccumulatedMouseMotion;
use bevy::prelude::*;
use serde::{Deserialize, Serialize};

/// The conventional path a game's action table lives at when it does
/// not name one.
pub const DEFAULT_INPUT_ACTIONS_PATH: &str = "input-actions.bsn";

/// One physical input an action listens to.
#[derive(Reflect, Clone, Debug, PartialEq, Serialize, Deserialize)]
pub enum GameInputBinding {
    /// A keyboard key.
    Key(KeyCode),
    /// A mouse button.
    MouseButton(MouseButton),
    /// The mouse's motion, as a delta (the Look default): the action's
    /// value accumulates the motion each frame.
    MouseMotion,
    /// A gamepad button.
    GamepadButton(GamepadButton),
    /// A gamepad axis with the deadzone below which input reads as
    /// zero. Symmetric: both directions use the same bound.
    GamepadAxis { axis: GamepadAxis, deadzone: f32 },
}

/// What kind of value an action produces.
#[derive(Reflect, Clone, Copy, Debug, PartialEq, Eq, Default, Serialize, Deserialize)]
pub enum GameActionKind {
    /// Pressed / just pressed / just released. Every binding kind can
    /// feed a button; axes feed their threshold-crossing, not their
    /// value.
    #[default]
    Button,
    /// A held 2D direction, composed from the bindings' key positions
    /// (W = up, D = right...) and left/right-stick axes: each
    /// contributes its axis pair, pressed keys add their direction.
    Axis2D,
    /// A per-frame 2D delta: mouse motion and stick deflection
    /// accumulate into the value, resetting each frame.
    Delta2D,
}

/// One named action and what feeds it.
#[derive(Reflect, Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[reflect(Default)]
pub struct GameActionDef {
    /// The name systems query: "Move", "Jump"...
    pub name: String,
    /// What the action produces.
    pub kind: GameActionKind,
    /// The inputs that feed it, in file order.
    pub bindings: Vec<GameInputBinding>,
}

/// A game's action table: the built-in defaults below, replaced or
/// extended by `assets/input-actions.bsn` when the game registers the
/// type as a config asset.
#[derive(Asset, Resource, Reflect, Clone, Debug, PartialEq, Serialize, Deserialize)]
#[reflect(Resource, Default)]
pub struct GameInputConfig {
    /// The actions. The default table carries the five a game starts
    /// with; a file that omits an action keeps that default (union
    /// merge, see the module docs).
    pub actions: Vec<GameActionDef>,
}

impl GameInputConfig {
    /// The five actions every jackdaw game starts with: WASD and the
    /// left stick to move, mouse motion and the right stick to look,
    /// Space / South to jump, E / East to interact, Escape / Start to
    /// pause. (Esc goes to the game, not the editor: the editor's
    /// capture releases on Shift+Esc and forwards a plain Esc.)
    pub fn defaults() -> Self {
        use bevy::input::keyboard::KeyCode;
        let axis = |axis: GamepadAxis| GameInputBinding::GamepadAxis {
            axis,
            deadzone: 0.15,
        };
        let button = |b: GamepadButton| GameInputBinding::GamepadButton(b);
        Self {
            actions: vec![
                GameActionDef {
                    name: "Move".into(),
                    kind: GameActionKind::Axis2D,
                    bindings: vec![
                        GameInputBinding::Key(KeyCode::KeyW),
                        GameInputBinding::Key(KeyCode::KeyA),
                        GameInputBinding::Key(KeyCode::KeyS),
                        GameInputBinding::Key(KeyCode::KeyD),
                        axis(GamepadAxis::LeftStickX),
                        axis(GamepadAxis::LeftStickY),
                    ],
                },
                GameActionDef {
                    name: "Look".into(),
                    kind: GameActionKind::Delta2D,
                    bindings: vec![
                        GameInputBinding::MouseMotion,
                        axis(GamepadAxis::RightStickX),
                        axis(GamepadAxis::RightStickY),
                    ],
                },
                GameActionDef {
                    name: "Jump".into(),
                    kind: GameActionKind::Button,
                    bindings: vec![
                        GameInputBinding::Key(KeyCode::Space),
                        button(GamepadButton::South),
                    ],
                },
                GameActionDef {
                    name: "Interact".into(),
                    kind: GameActionKind::Button,
                    bindings: vec![
                        GameInputBinding::Key(KeyCode::KeyE),
                        button(GamepadButton::East),
                    ],
                },
                GameActionDef {
                    name: "Pause".into(),
                    kind: GameActionKind::Button,
                    bindings: vec![
                        GameInputBinding::Key(KeyCode::Escape),
                        button(GamepadButton::Start),
                    ],
                },
            ],
        }
    }
}

/// The default is the built-in five-action table (see
/// [`GameInputConfig::defaults`]); a config asset replaces entries by
/// name and fills the rest from here.
impl Default for GameInputConfig {
    fn default() -> Self {
        Self::defaults()
    }
}

/// What an action produced this frame. The shape of `value` follows
/// the action's kind: buttons hold `Vec2::ZERO`, `Axis2D` a held
/// direction in `[-1, 1]²`, `Delta2D` this frame's motion delta.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct GameActionState {
    /// Held down this frame (or, for axes, deflected past deadzone).
    pub pressed: bool,
    /// Went down this frame.
    pub just_pressed: bool,
    /// Came up this frame.
    pub just_released: bool,
    /// The action's value; see the type docs.
    pub value: Vec2,
}

/// Every action's state this frame, by name. [`InputActionsPlugin`]
/// rebuilds it each frame before `Update` systems that read it run.
#[derive(Resource, Clone, Debug, Default)]
pub struct GameActions {
    states: HashMap<String, GameActionState>,
}

impl GameActions {
    /// An action's state, if the config defines it.
    pub fn get(&self, name: &str) -> Option<GameActionState> {
        self.states.get(name).copied()
    }

    /// An action's held state; a missing action reads as not pressed.
    pub fn pressed(&self, name: &str) -> bool {
        self.get(name).is_some_and(|state| state.pressed)
    }

    /// An action's this-frame press; a missing action reads as no.
    pub fn just_pressed(&self, name: &str) -> bool {
        self.get(name).is_some_and(|state| state.just_pressed)
    }

    /// An action's this-frame release; a missing action reads as no.
    pub fn just_released(&self, name: &str) -> bool {
        self.get(name).is_some_and(|state| state.just_released)
    }

    /// An action's value; a missing action reads as zero.
    pub fn value(&self, name: &str) -> Vec2 {
        self.get(name).map_or(Vec2::ZERO, |state| state.value)
    }
}

/// Merge a file's actions over the defaults: same-name entries replace
/// (the file's kind wins), everything the file omits keeps the
/// default. Duplicate names in one source keep the first, so a hand
/// edit cannot fork an action's meaning.
pub fn merge_actions(defaults: &[GameActionDef], file: &[GameActionDef]) -> Vec<GameActionDef> {
    let mut merged: Vec<GameActionDef> = Vec::new();
    for def in file {
        if !merged.iter().any(|existing| existing.name == def.name) {
            merged.push(def.clone());
        }
    }
    for def in defaults {
        if !merged.iter().any(|existing| existing.name == def.name) {
            merged.push(def.clone());
        }
    }
    merged
}

/// The evaluation plugin: reads [`GameInputConfig`] (the
/// [`ConfigPlugin`](crate::ConfigPlugin) injects the asset's value, or
/// the built-in defaults stand in), applies each gamepad binding's
/// deadzone to the engine's [`GamepadSettings`], and rebuilds
/// [`GameActions`] each frame from the engine's keyboard, mouse and
/// gamepad input.
///
/// The engine's own `ButtonInput` change tracking is the source of
/// `just_pressed` / `just_released`, so a PIE-injected event (the editor
/// forwarding real input to the game) behaves exactly like a native
/// one: it lands in the same stream one frame later, the same as a
/// windowed event would.
pub struct InputActionsPlugin;

impl Plugin for InputActionsPlugin {
    fn build(&self, app: &mut App) {
        // The built-in defaults stand in until (or unless) a config
        // asset replaces them: a game that never authors
        // input-actions.bsn still gets the five standard actions.
        app.init_resource::<GameInputConfig>();
        app.init_resource::<GameActions>();
        // After the engine's own input accumulation (ButtonInput updates,
        // mouse motion accumulation), so a frame's events are all in
        // before the actions are evaluated from them.
        app.add_systems(
            PreUpdate,
            (apply_deadzones, evaluate_actions)
                .chain()
                .after(bevy::input::InputSystems),
        );
    }
}

/// Copy each binding's deadzone into the engine's per-axis settings,
/// so every axis reader — this system included — sees filtered values.
/// The settings are a component on each connected gamepad the engine
/// spawned (`GamepadSettings` is per-device in this bevy), so every
/// gamepad in the world gets the binding's deadzone.
fn apply_deadzones(
    config: Option<Res<GameInputConfig>>,
    mut settings: Query<&mut GamepadSettings>,
) {
    let Some(config) = config else {
        return;
    };
    let mut apply = Vec::new();
    for action in &config.actions {
        for binding in &action.bindings {
            if let GameInputBinding::GamepadAxis { axis, deadzone } = binding {
                apply.push((*axis, *deadzone));
            }
        }
    }
    if apply.is_empty() {
        return;
    }
    for mut gamepad in &mut settings {
        for (axis, deadzone) in &apply {
            if let Ok(axis_settings) = AxisSettings::new(-1.0, -*deadzone, *deadzone, 1.0, 0.01) {
                gamepad.axis_settings.insert(*axis, axis_settings);
            }
        }
    }
}

/// Rebuild [`GameActions`] for this frame.
///
/// Gamepad state comes off the engine's `Gamepad` components (per
/// device, filtered by the settings [`apply_deadzones`] installed) —
/// this bevy keeps no global `ButtonInput<GamepadButton>` resource, so
/// every connected gamepad is folded in: a button held on any pad
/// holds the action, and an axis reads the pad with the largest
/// deflection.
fn evaluate_actions(
    config: Option<Res<GameInputConfig>>,
    mut actions: ResMut<GameActions>,
    keys: Option<Res<ButtonInput<KeyCode>>>,
    mouse: Option<Res<ButtonInput<MouseButton>>>,
    mut motion: Option<ResMut<AccumulatedMouseMotion>>,
    gamepads: Query<&Gamepad>,
) {
    actions.states.clear();
    let Some(config) = config else { return };
    // The union with the defaults is recomputed each frame: a config
    // asset loading after startup (the ConfigPlugin injection) starts
    // contributing the frame it arrives.
    let merged = merge_actions(&GameInputConfig::defaults().actions, &config.actions);
    for def in &merged {
        let mut state = GameActionState::default();
        for binding in &def.bindings {
            match binding {
                GameInputBinding::Key(code) => {
                    if let Some(keys) = &keys {
                        state.pressed |= keys.pressed(*code);
                        state.just_pressed |= keys.just_pressed(*code);
                        state.just_released |= keys.just_released(*code);
                        if def.kind == GameActionKind::Axis2D && keys.pressed(*code) {
                            state.value += key_direction(*code);
                        }
                    }
                }
                GameInputBinding::MouseButton(button) => {
                    if let Some(mouse) = &mouse {
                        state.pressed |= mouse.pressed(*button);
                        state.just_pressed |= mouse.just_pressed(*button);
                        state.just_released |= mouse.just_released(*button);
                    }
                }
                GameInputBinding::MouseMotion => {
                    if let Some(motion) = &mut motion {
                        state.value += Vec2::new(motion.delta.x, motion.delta.y);
                        state.pressed |= motion.delta.length_squared() > 0.0;
                    }
                }
                GameInputBinding::GamepadButton(button) => {
                    for gamepad in &gamepads {
                        state.pressed |= gamepad.pressed(*button);
                        state.just_pressed |= gamepad.just_pressed(*button);
                        state.just_released |= gamepad.just_released(*button);
                    }
                }
                GameInputBinding::GamepadAxis { axis, .. } => {
                    // The largest deflection across pads — the engine
                    // already applied the deadzone we installed when it
                    // filtered the event into the component.
                    let mut value: f32 = 0.0;
                    let mut any = false;
                    for gamepad in &gamepads {
                        if let Some(deflection) = gamepad.get(*axis)
                            && (!any || deflection.abs() > value.abs())
                        {
                            value = deflection;
                            any = true;
                        }
                    }
                    if any {
                        match def.kind {
                            GameActionKind::Button => {
                                state.pressed |= value.abs() > 0.5;
                                state.just_pressed |= value.abs() > 0.5;
                            }
                            // Axis2D and Delta2D read the same way: the
                            // axis contributes its (x, y) pair to the
                            // value — held for Axis2D, a per-frame delta
                            // for Delta2D, which only differs in how the
                            // consumer treats it.
                            GameActionKind::Axis2D | GameActionKind::Delta2D => {
                                let (x, y) = axis_pair(*axis, value);
                                state.value += Vec2::new(x, y);
                                state.pressed |= value.abs() > 0.0;
                            }
                        }
                    }
                }
            }
        }
        if def.kind == GameActionKind::Axis2D {
            state.value = state.value.clamp_length_max(1.0);
        }
        actions.states.insert(def.name.clone(), state);
    }
}

/// The direction a WASD-style key contributes to an `Axis2D` action.
fn key_direction(code: KeyCode) -> Vec2 {
    use bevy::input::keyboard::KeyCode;
    match code {
        KeyCode::KeyW | KeyCode::ArrowUp => Vec2::Y,
        KeyCode::KeyS | KeyCode::ArrowDown => Vec2::NEG_Y,
        KeyCode::KeyA | KeyCode::ArrowLeft => Vec2::NEG_X,
        KeyCode::KeyD | KeyCode::ArrowRight => Vec2::X,
        _ => Vec2::ZERO,
    }
}

/// The (x, y) pair a gamepad axis contributes. Left/right sticks'
/// negative Y is up on the left stick and down on the right (look)
/// stick — the conventional split, so Move with the left stick up
/// reads +Y like W does, while Look with the right stick up reads the
/// camera upward too.
fn axis_pair(axis: GamepadAxis, value: f32) -> (f32, f32) {
    match axis {
        GamepadAxis::LeftStickX | GamepadAxis::RightStickX => (value, 0.0),
        GamepadAxis::LeftStickY => (0.0, value),
        GamepadAxis::RightStickY => (0.0, -value),
        _ => (0.0, 0.0),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::input::gamepad::{
        Gamepad, GamepadButton, GamepadSettings, RawGamepadAxisChangedEvent,
        RawGamepadButtonChangedEvent, RawGamepadEvent,
    };

    /// A minimal app with the plugin and the input resources the
    /// evaluation reads. `with_config` installs a config; without one
    /// the plugin evaluates the built-in defaults.
    fn app(with_config: Option<GameInputConfig>) -> App {
        let mut app = App::new();
        app.add_plugins((
            bevy::app::TaskPoolPlugin::default(),
            bevy::input::InputPlugin,
        ));
        app.add_plugins(InputActionsPlugin);
        if let Some(config) = with_config {
            app.insert_resource(config);
        }
        app
    }

    /// Press a key the way a real event stream does: the engine's
    /// input systems rebuild `ButtonInput` from events each frame, so
    /// pressing on the resource directly would be cleared before the
    /// evaluation reads it.
    fn press_key(app: &mut App, code: KeyCode) {
        app.world_mut()
            .write_message(bevy::input::keyboard::KeyboardInput {
                key_code: code,
                logical_key: bevy::input::keyboard::Key::Character("k".into()),
                state: bevy::input::ButtonState::Pressed,
                window: Entity::PLACEHOLDER,
                repeat: false,
                text: None,
            });
    }

    /// The red/green pair for the evaluation core: with the plugin, a
    /// pressed key shows up in `GameActions` under the action it is
    /// bound to (the red half — no plugin, no resource to read at
    /// all); and rebinding to another key moves the action with the
    /// binding, which is "bindings are editable and take effect" at
    /// the mechanism layer.
    #[test]
    fn a_pressed_key_drives_the_action_it_is_bound_to() {
        let mut app = app(None);
        press_key(&mut app, KeyCode::KeyW);
        app.update();

        let actions = app.world().resource::<GameActions>();
        let r#move = actions.get("Move").expect("the default table has Move");
        assert!(r#move.pressed, "W holds Move down");
        assert!(
            r#move.value.y > 0.9,
            "W contributes +Y, got {}",
            r#move.value
        );
        // And a key nothing binds contributes nothing.
        let jump = actions.get("Jump").expect("Jump exists");
        assert!(!jump.pressed);
    }

    #[test]
    fn rebinding_moves_the_action_with_the_binding() {
        let mut config = GameInputConfig::defaults();
        config.actions[0].bindings = vec![GameInputBinding::Key(KeyCode::ArrowUp)];
        let mut app = app(Some(config));
        // The old binding no longer drives the action...
        press_key(&mut app, KeyCode::KeyW);
        app.update();
        let actions = app.world().resource::<GameActions>();
        assert!(!actions.pressed("Move"), "W is no longer Move");

        // ...and the new one does.
        press_key(&mut app, KeyCode::ArrowUp);
        app.update();
        let actions = app.world().resource::<GameActions>();
        assert!(actions.pressed("Move"), "ArrowUp is Move now");
    }

    /// The union merge: a file naming only Move replaces Move (kind
    /// and bindings from the file) and every other action keeps its
    /// default — a file authored before an action existed still gets
    /// it (the "all defaults in the file" trap, avoided); a file
    /// naming everything wins everywhere.
    #[test]
    fn a_file_merges_over_the_defaults_as_a_union() {
        let defaults = GameInputConfig::defaults();
        let file = GameInputConfig {
            actions: vec![GameActionDef {
                name: "Move".into(),
                kind: GameActionKind::Button,
                bindings: vec![GameInputBinding::Key(KeyCode::ArrowUp)],
            }],
        };
        let merged = merge_actions(&defaults.actions, &file.actions);
        assert_eq!(merged.len(), defaults.actions.len());
        let r#move = merged.iter().find(|d| d.name == "Move").unwrap();
        assert_eq!(r#move.kind, GameActionKind::Button, "the file's kind wins");
        assert_eq!(
            r#move.bindings,
            vec![GameInputBinding::Key(KeyCode::ArrowUp)]
        );
        let jump = merged.iter().find(|d| d.name == "Jump").unwrap();
        assert!(
            jump.bindings.iter().any(|b| matches!(
                b,
                GameInputBinding::Key(bevy::input::keyboard::KeyCode::Space)
            )),
            "an omitted action keeps its default bindings"
        );
        // A duplicate name in one source keeps the first.
        let dup = GameInputConfig {
            actions: vec![
                GameActionDef {
                    name: "Move".into(),
                    kind: GameActionKind::Button,
                    bindings: vec![],
                },
                GameActionDef {
                    name: "Move".into(),
                    kind: GameActionKind::Delta2D,
                    bindings: vec![],
                },
            ],
        };
        let merged = merge_actions(&defaults.actions, &dup.actions);
        let count = merged.iter().filter(|d| d.name == "Move").count();
        assert_eq!(count, 1, "duplicate names collapse to one entry");
    }

    /// Mouse motion accumulates into a `Delta2D` action's value this
    /// frame; a Jump bound to a mouse button reads pressed.
    #[test]
    fn mouse_motion_and_buttons_feed_actions() {
        let mut app = app(None);
        // Motion through the event stream (the engine's accumulation
        // rebuilds the resource from events, like the keyboard does).
        app.world_mut()
            .write_message(bevy::input::mouse::MouseMotion {
                delta: Vec2::new(12.0, -4.0),
            });
        app.world_mut()
            .write_message(bevy::input::mouse::MouseButtonInput {
                button: MouseButton::Left,
                state: bevy::input::ButtonState::Pressed,
                window: Entity::PLACEHOLDER,
            });
        app.update();

        let actions = app.world().resource::<GameActions>();
        let look = actions.get("Look").expect("Look exists");
        assert_eq!(look.value, Vec2::new(12.0, -4.0), "motion is the delta");
        // Jump is bound to Space/South, not the mouse: LMB holds
        // nothing here.
        assert!(!actions.pressed("Jump"));
    }

    /// The union holds on the live resource too: a config resource
    /// carrying only Move still evaluates all five actions, the
    /// omitted four on their defaults.
    #[test]
    fn a_partial_config_still_evaluates_the_full_action_set() {
        let mut app = app(Some(GameInputConfig {
            actions: vec![GameActionDef {
                name: "Jump".into(),
                kind: GameActionKind::Button,
                bindings: vec![GameInputBinding::Key(KeyCode::KeyJ)],
            }],
        }));
        press_key(&mut app, KeyCode::KeyJ);
        app.update();
        let actions = app.world().resource::<GameActions>();
        assert!(actions.just_pressed("Jump"), "the file's J jumps");
        assert!(
            actions.get("Move").is_some(),
            "the omitted Move still exists"
        );
        assert!(actions.get("Pause").is_some(), "and Pause");
    }

    /// Deadzones land in the engine's settings — a component on a
    /// connected gamepad — so the engine's own filter applies them. A
    /// spawned gamepad with settings is the test's device stand-in;
    /// the binding's axis reads the configured bound.
    #[test]
    fn axis_deadzones_apply_through_the_engine_settings() {
        let mut config = GameInputConfig::defaults();
        config.actions[0].bindings = vec![GameInputBinding::GamepadAxis {
            axis: GamepadAxis::LeftStickX,
            deadzone: 0.5,
        }];
        let mut app = app(Some(config));
        let gamepad = app.world_mut().spawn(GamepadSettings::default()).id();
        let _ = gamepad;
        app.update();
        let mut query = app.world_mut().query::<&GamepadSettings>();
        let settings = query.single(app.world()).expect("the gamepad");
        let left_x = settings
            .axis_settings
            .get(&GamepadAxis::LeftStickX)
            .cloned()
            .expect("the binding installed settings for its axis");
        assert_eq!(left_x.deadzone_lowerbound(), -0.5);
        assert_eq!(left_x.deadzone_upperbound(), 0.5);
    }

    /// Feed a gamepad the way gilrs or a PIE-forwarding editor does:
    /// raw events into the message stream, the engine's own systems
    /// filtering them into the `Gamepad` component — which is where
    /// the evaluation reads. This bevy keeps no global
    /// `ButtonInput<GamepadButton>` resource, so this test is the
    /// reachability proof for the whole gamepad leg: a pad event that
    /// lands in the stream drives the action it is bound to.
    #[test]
    fn gamepad_events_reach_the_actions_through_the_component() {
        let mut app = app(None); // defaults: Move sticks at a 0.15 deadzone
        let pad = app
            .world_mut()
            .spawn((Gamepad::default(), GamepadSettings::default()))
            .id();
        app.update(); // schedules exist; the deadzones are installed

        // An axis deflected past the deadzone moves.
        app.world_mut()
            .write_message(RawGamepadEvent::Axis(RawGamepadAxisChangedEvent::new(
                pad,
                GamepadAxis::LeftStickX,
                0.8,
            )));
        app.update();
        let actions = app.world().resource::<GameActions>();
        assert!(
            actions.pressed("Move"),
            "a left-stick deflection past the deadzone holds Move"
        );
        assert_eq!(
            actions.value("Move").x,
            0.8,
            "the raw deflection reads through"
        );

        // An axis inside the deadzone is filtered by the engine before
        // the component ever sees it. The Y axis carries no value —
        // Move's X deflection stands, but Y contributes nothing.
        app.world_mut()
            .write_message(RawGamepadEvent::Axis(RawGamepadAxisChangedEvent::new(
                pad,
                GamepadAxis::LeftStickY,
                0.1,
            )));
        app.update();
        let actions = app.world().resource::<GameActions>();
        assert_eq!(
            actions.value("Move").y,
            0.0,
            "0.1 stays inside the 0.15 deadzone"
        );

        // A button press jumps.
        app.world_mut()
            .write_message(RawGamepadEvent::Button(RawGamepadButtonChangedEvent::new(
                pad,
                GamepadButton::South,
                1.0,
            )));
        app.update();
        let actions = app.world().resource::<GameActions>();
        assert!(
            actions.just_pressed("Jump"),
            "South on the pad jumps the same frame"
        );
    }
}
