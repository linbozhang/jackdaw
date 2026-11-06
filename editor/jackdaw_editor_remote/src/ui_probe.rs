//! BRP methods that find a control on screen and drive it the way a person
//! does. `ui_tree` reports what is there; `ui_click`, `ui_drag` and `ui_input`
//! locate a target and queue the gesture into the same [`SyntheticInput`]
//! queue the `input.*` operators feed, so the click runs the real picking,
//! hover, focus and observer chain — nothing is triggered by hand.
//! `camera_state` is the read the look/pan assertions need, with the yaw and
//! pitch extraction the editor does instead of the caller.

use bevy::feathers::controls::{
    FeathersButton, FeathersCheckbox, FeathersSlider, FeathersTextInput,
};
use bevy::prelude::*;
use bevy::remote::{BrpError, BrpResult, error_codes};
use bevy::ui::{Checked, InteractionDisabled, UiGlobalTransform};
use bevy::ui_widgets::{SliderRange, SliderValue};
use jackdaw_feathers::button::{ButtonContentText, ButtonOperatorCall, EditorButton};
use jackdaw_feathers::dialog::EditorDialog;
use jackdaw_feathers::picker::Picker;
use jackdaw_scene_types::UiSceneRoot;
use serde_json::{Value, json};

use jackdaw_editor_core::operator_calls::invalid_params;
use jackdaw_editor_core::test_input::{
    SyntheticInput, click_gesture, drag_gesture, enter_gesture, select_all_gesture, typing_gesture,
};
use jackdaw_editor_core::viewport::{ActiveViewport, CameraFlyActive, CameraPanActive, MainViewportCamera};

use super::server::check_enabled;

/// How far up from a node the visibility and ancestor walks look before
/// deciding the chain is cyclic or endless.
const MAX_ANCESTRY: usize = 64;

// --- What a UI entity is, and where it is drawn ---

/// What a UI entity is, by the components it carries. The judgement order
/// matters: a checkbox is also a button, and a menu row is also a button, but
/// a caller means the narrower thing. `ButtonContentText` alone marks a
/// caption, not a control: it names the text a button or menu row draws.
fn kind_of(world: &World, entity: Entity) -> &'static str {
    if world.get::<EditorDialog>(entity).is_some() {
        return "dialog";
    }
    if world.get::<Picker>(entity).is_some() {
        return "picker";
    }
    if world.get::<FeathersCheckbox>(entity).is_some() {
        return "checkbox";
    }
    if world.get::<FeathersSlider>(entity).is_some() {
        return "slider";
    }
    if world.get::<FeathersTextInput>(entity).is_some() {
        return "text_input";
    }
    if world.get::<ButtonOperatorCall>(entity).is_some() {
        // A row that carries its action and its own caption text is a menu
        // row; the editor's own buttons reach the operator through a
        // `FeathersButton`.
        return if world.get::<ButtonContentText>(entity).is_some() {
            "menu_item"
        } else {
            "button"
        };
    }
    if world.get::<FeathersButton>(entity).is_some() || world.get::<EditorButton>(entity).is_some()
    {
        return "button";
    }
    if world.get::<Text>(entity).is_some() {
        return "text";
    }
    "node"
}

/// Whether clicking `entity` is clicking a control, rather than the layout or
/// the glyphs around it. Besides the widgets, a node somebody hung a pointer
/// observer on counts: the launcher and a few older surfaces hand-roll their
/// buttons as plain nodes with `On<PointerClick>` observers, and `ObservedBy`
/// is the one thing that marks them.
fn is_actionable(world: &World, entity: Entity) -> bool {
    world.get::<ButtonOperatorCall>(entity).is_some()
        || world.get::<FeathersButton>(entity).is_some()
        || world.get::<EditorButton>(entity).is_some()
        || world.get::<FeathersCheckbox>(entity).is_some()
        || world.get::<FeathersSlider>(entity).is_some()
        || world.get::<FeathersTextInput>(entity).is_some()
        || world.get::<Picker>(entity).is_some()
        || world.get::<EditorDialog>(entity).is_some()
        || world
            .get::<bevy::ecs::observer::ObservedBy>(entity)
            .is_some_and(|observers| !observers.get().is_empty())
}

/// Whether a control reacts, as `InteractionDisabled` spells it. The marker
/// may sit on the control or on an ancestor that disables a whole section.
fn disabled_by_ancestor(world: &World, mut entity: Entity) -> bool {
    for _ in 0..MAX_ANCESTRY {
        if world.get::<InteractionDisabled>(entity).is_some() {
            return true;
        }
        match world.get::<ChildOf>(entity) {
            Some(parent) => entity = parent.parent(),
            None => return false,
        }
    }
    false
}

/// Whether the node is drawn: nothing up its chain hides it. `Visibility`
/// rather than a render check, so a headless run answers the same as a live
/// one.
fn visible_through_ancestors(world: &World, mut entity: Entity) -> bool {
    for _ in 0..MAX_ANCESTRY {
        if matches!(world.get::<Visibility>(entity), Some(Visibility::Hidden)) {
            return false;
        }
        match world.get::<ChildOf>(entity) {
            Some(parent) => entity = parent.parent(),
            None => return true,
        }
    }
    true
}

/// Where an entity is drawn: its centre and size in the window logical pixels
/// `input.pointer` takes, plus the same as a physical-pixel rect for a caller
/// comparing against a screenshot.
struct Placement {
    centre: Vec2,
    size: Vec2,
    rect: [f32; 4],
}

/// The placement of a laid-out UI entity, or `None` when it has no box (not
/// yet laid out, or not a UI node at all).
fn placement_of(world: &World, entity: Entity) -> Option<Placement> {
    let transform = world.get::<UiGlobalTransform>(entity)?;
    let computed = world.get::<ComputedNode>(entity)?;
    let ui_scale = world.get_resource::<UiScale>().map_or(1.0, |scale| scale.0);
    let centre = transform.translation * computed.inverse_scale_factor() * ui_scale;
    let size = computed.size() * computed.inverse_scale_factor() * ui_scale;
    let physical = computed.size() / computed.inverse_scale_factor();
    let top_left = transform.translation - physical / 2.0;
    Some(Placement {
        centre,
        size,
        rect: [top_left.x, top_left.y, physical.x, physical.y],
    })
}

/// The box a gesture actually aims at: the entity's own when it has one, and
/// otherwise the nearest sized descendant, then the nearest sized ancestor —
/// a widget's logical entity is often a zero-size carrier whose frame or
/// track holds the box a user sees.
fn sized_placement(world: &World, entity: Entity) -> Option<Placement> {
    if let Some(own) = placement_of(world, entity)
        && own.size != Vec2::ZERO
    {
        return Some(own);
    }
    // Breadth-first into the subtree: the frame or track is usually close.
    let mut queue = std::collections::VecDeque::from([entity]);
    let mut budget = 64usize;
    while let Some(current) = queue.pop_front() {
        if budget == 0 {
            break;
        }
        budget -= 1;
        let Some(children) = world.get::<Children>(current) else {
            continue;
        };
        for kid in children.iter() {
            if let Some(placement) = placement_of(world, kid)
                && placement.size != Vec2::ZERO
            {
                return Some(placement);
            }
            queue.push_back(kid);
        }
    }
    // Up the chain: a row's own box stands in for a control that never
    // measured itself.
    let mut current = entity;
    for _ in 0..MAX_ANCESTRY {
        let Some(parent) = world.get::<ChildOf>(current).map(ChildOf::parent) else {
            break;
        };
        if let Some(placement) = placement_of(world, parent)
            && placement.size != Vec2::ZERO
        {
            return Some(placement);
        }
        current = parent;
    }
    None
}

/// The label a tree node reports: its own `Text`, or the
/// `ButtonContentText` descendant a button keeps its caption on. Deliberately
/// not "any text inside": a tree where every container echoes its first
/// descendant says less, not more.
fn own_label(world: &World, entity: Entity) -> Option<String> {
    if let Some(text) = world.get::<Text>(entity) {
        return Some(text.0.clone());
    }
    if !matches!(
        kind_of(world, entity),
        "button" | "menu_item" | "checkbox" | "slider"
    ) {
        return None;
    }
    // A caption hides somewhere in the widget's clipping slots; the search is
    // bounded so a pathological subtree cannot hold the walk.
    let mut stack = vec![entity];
    let mut budget = 64usize;
    while let Some(current) = stack.pop() {
        if budget == 0 {
            return None;
        }
        budget -= 1;
        if world.get::<ButtonContentText>(current).is_some() {
            return world.get::<Text>(current).map(|text| text.0.clone());
        }
        if let Some(kids) = world.get::<Children>(current) {
            stack.extend(kids.iter());
        }
    }
    None
}

/// The label a *locator* matches against: [`own_label`], or — for the
/// surfaces that hand-roll their rows, like the menu bar and the launcher
/// cards — the first text the control contains.
fn label_of(world: &World, entity: Entity) -> Option<String> {
    if let Some(marked) = own_label(world, entity) {
        return Some(marked);
    }
    if !matches!(kind_of(world, entity), "button" | "menu_item" | "node") {
        return None;
    }
    let mut stack = vec![entity];
    let mut budget = 64usize;
    while let Some(current) = stack.pop() {
        if budget == 0 {
            return None;
        }
        budget -= 1;
        if current != entity
            && world
                .get::<Text>(current)
                .is_some_and(|text| !text.0.trim().is_empty())
        {
            return world.get::<Text>(current).map(|text| text.0.clone());
        }
        if let Some(kids) = world.get::<Children>(current) {
            stack.extend(kids.iter());
        }
    }
    None
}

// --- Locating a control ---

/// The control a locator named.
struct Target {
    entity: Entity,
    kind: &'static str,
    label: Option<String>,
    operator: Option<String>,
}

/// The `Target` a `ui_click`-shaped parameter object names: an `entity` id, an
/// `operator` prefix, or a `text` substring disambiguated by `index`.
///
/// Anything ambiguous is a refusal that lists the candidates, the way
/// `entity_from_params` refuses a name two entities answer to: a caller that
/// cannot tell which control it clicked has learned nothing.
fn locate(world: &mut World, params: &Value) -> Result<Target, BrpError> {
    if let Some(bits) = params.get("entity").and_then(Value::as_u64) {
        let entity = Entity::try_from_bits(bits)
            .filter(|entity| world.get_entity(*entity).is_ok())
            .ok_or_else(|| invalid_params(format!("no entity with id {bits}")))?;
        if world.get::<ComputedNode>(entity).is_none() {
            return Err(invalid_params(format!(
                "entity {bits} is not a UI node; pass one `ui_tree` reported"
            )));
        }
        return Ok(target_of(world, entity));
    }

    let wanted = params.get("text").and_then(Value::as_str);
    let operator = params.get("operator").and_then(Value::as_str);
    if wanted.is_none() && operator.is_none() {
        return Err(invalid_params(
            "expected one of \"entity\", \"operator\" or \"text\" (+ \"index\")",
        ));
    }

    let mut candidates: Vec<Entity> = Vec::new();
    if let Some(operator) = operator {
        let mut calls = world.query_filtered::<Entity, With<ButtonOperatorCall>>();
        for entity in calls.iter(world) {
            let call = world.get::<ButtonOperatorCall>(entity);
            if call.is_some_and(|call| call.id.starts_with(operator))
                && !candidates.contains(&entity)
            {
                candidates.push(entity);
            }
        }
    }
    if let Some(wanted) = wanted {
        let needle = wanted.to_ascii_lowercase();
        let mut texts = world.query_filtered::<Entity, With<Text>>();
        let entities: Vec<Entity> = texts.iter(world).collect();
        for text_entity in entities {
            let Some(text) = world.get::<Text>(text_entity) else {
                continue;
            };
            if !text.0.to_ascii_lowercase().contains(&needle) {
                continue;
            }
            if let Some(mut hit) = actionable_ancestor(world, text_entity) {
                // Text the picker or a dialog itself answers to — a category
                // header, an inert label — aims at the text, not at the modal
                // it lives in: a click at the modal's centre lands on
                // whatever happens to sit there.
                if matches!(kind_of(world, hit), "picker" | "dialog")
                    && world.get::<ComputedNode>(text_entity).is_some()
                {
                    hit = text_entity;
                }
                if !candidates.contains(&hit) {
                    candidates.push(hit);
                }
            }
        }
        // An exact label wins over a substring: "Add" means the Add button,
        // not every "Add …" row beside it.
        let exact: Vec<Entity> = candidates
            .iter()
            .copied()
            .filter(|entity| {
                label_of(world, *entity).is_some_and(|label| label.to_ascii_lowercase() == needle)
            })
            .collect();
        if !exact.is_empty() {
            candidates = exact;
        }
    }

    match candidates.len() {
        0 => Err(invalid_params(format!(
            "no control matches {}",
            describe_locator(wanted, operator)
        ))),
        1 => Ok(target_of(world, candidates[0])),
        _ => {
            // Spawn order, so `index` means the same thing on every call.
            candidates.sort_by_key(|entity| entity.index());
            candidates.dedup();
            let index = params.get("index").and_then(Value::as_u64);
            let Some(index) = index else {
                return Err(ambiguous(world, &candidates));
            };
            candidates
                .get(index as usize)
                .map(|entity| target_of(world, *entity))
                .ok_or_else(|| {
                    invalid_params(format!(
                        "index {index} is past the {} candidates; 0 is the first",
                        candidates.len()
                    ))
                })
        }
    }
}

/// The nearest ancestor-or-self a caller would mean by clicking this text:
/// the control the text labels, not the glyphs.
fn actionable_ancestor(world: &World, mut entity: Entity) -> Option<Entity> {
    for _ in 0..MAX_ANCESTRY {
        if is_actionable(world, entity) {
            return Some(entity);
        }
        entity = world.get::<ChildOf>(entity)?.parent();
    }
    None
}

/// The refusal for a locator that named more than one control.
fn ambiguous(world: &World, candidates: &[Entity]) -> BrpError {
    let listed: Vec<Value> = candidates
        .iter()
        .take(8)
        .map(|entity| {
            json!({
                "entity": entity.to_bits(),
                "kind": kind_of(world, *entity),
                "text": label_of(world, *entity),
                "rect": placement_of(world, *entity).map(|placement| placement.rect),
            })
        })
        .collect();
    BrpError {
        code: error_codes::INVALID_PARAMS,
        message: format!(
            "{} candidates; pass \"index\" to pick one (0 is the first)",
            candidates.len()
        ),
        data: Some(json!({ "candidates": listed })),
    }
}

/// The `Target` record for an entity. The operator a click will dispatch
/// lives on the row the button sits in as often as on the button itself, so
/// the search reaches up rather than reporting nothing.
fn target_of(world: &mut World, entity: Entity) -> Target {
    let mut operator = None;
    let mut current = entity;
    for _ in 0..MAX_ANCESTRY {
        if let Some(call) = world.get::<ButtonOperatorCall>(current) {
            operator = Some(call.id.to_string());
            break;
        }
        match world.get::<ChildOf>(current) {
            Some(parent) => current = parent.parent(),
            None => break,
        }
    }
    Target {
        entity,
        kind: kind_of(world, entity),
        label: label_of(world, entity),
        operator,
    }
}

/// How a refusal names what the caller asked for.
fn describe_locator(text: Option<&str>, operator: Option<&str>) -> String {
    match (text, operator) {
        (Some(text), Some(operator)) => format!("text {text:?} and operator {operator:?}"),
        (Some(text), None) => format!("text {text:?}"),
        (None, Some(operator)) => format!("operator {operator:?}"),
        (None, None) => "nothing".to_string(),
    }
}

/// Refuse a target that cannot take the gesture, saying why: better a named
/// refusal than a click the caller cannot tell landed.
fn check_target(world: &World, target: &Target) -> Result<Placement, BrpError> {
    if disabled_by_ancestor(world, target.entity) {
        return Err(invalid_params(format!(
            "the control is disabled ({} {})",
            target.kind,
            target.label.as_deref().unwrap_or_default()
        )));
    }
    if !visible_through_ancestors(world, target.entity) {
        return Err(invalid_params(format!(
            "the control is hidden ({} {})",
            target.kind,
            target.label.as_deref().unwrap_or_default()
        )));
    }
    sized_placement(world, target.entity).ok_or_else(|| {
        invalid_params(format!(
            "the control has no box to click ({} {}); it may not be laid out",
            target.kind,
            target.label.as_deref().unwrap_or_default()
        ))
    })
}

// --- The methods ---

/// The panel and control tree as the screen shows it: kinds, labels, boxes,
/// state. Filters narrow a walk that would otherwise report a thousand nodes.
pub fn ui_tree_handler(In(params): In<Option<Value>>, world: &mut World) -> BrpResult {
    check_enabled(world)?;
    let params = params.unwrap_or(Value::Null);
    let depth = params.get("depth").and_then(Value::as_u64).unwrap_or(6) as u32;
    let wanted_text = params.get("text").and_then(Value::as_str);
    let operator = params.get("operator").and_then(Value::as_str);
    let kind = params.get("kind").and_then(Value::as_str);
    let visible_only = params
        .get("visible_only")
        .and_then(Value::as_bool)
        .unwrap_or(false);

    // A filter narrows the walk to the nodes that match (and their subtrees);
    // without one the walk starts from the UI roots, editor chrome and scene
    // screens alike.
    let roots: Vec<Entity> = if wanted_text.is_some() || operator.is_some() || kind.is_some() {
        locate_for_tree(world, wanted_text, operator, kind)
    } else if let Some(bits) = params.get("root").and_then(Value::as_u64) {
        let entity = Entity::try_from_bits(bits)
            .filter(|entity| world.get_entity(*entity).is_ok())
            .ok_or_else(|| invalid_params(format!("no entity with id {bits}")))?;
        vec![entity]
    } else {
        ui_roots(world)
    };

    let mut index = 0u64;
    let mut nodes: Vec<Value> = Vec::with_capacity(roots.len());
    for root in roots {
        if visible_only
            && (!visible_through_ancestors(world, root)
                || placement_of(world, root).is_none_or(|placement| placement.size == Vec2::ZERO))
        {
            continue;
        }
        nodes.push(ui_node_json(world, root, depth, visible_only, &mut index));
    }
    Ok(json!({ "nodes": nodes }))
}

/// The entities a filtered `ui_tree` starts from.
fn locate_for_tree(
    world: &mut World,
    text: Option<&str>,
    operator: Option<&str>,
    kind: Option<&str>,
) -> Vec<Entity> {
    let mut found: Vec<Entity> = Vec::new();
    if let Some(operator) = operator {
        let mut calls = world.query_filtered::<Entity, With<ButtonOperatorCall>>();
        for entity in calls.iter(world) {
            let call = world.get::<ButtonOperatorCall>(entity);
            if call.is_some_and(|call| call.id.starts_with(operator)) && !found.contains(&entity) {
                found.push(entity);
            }
        }
    }
    if let Some(text) = text {
        let needle = text.to_ascii_lowercase();
        let mut texts = world.query_filtered::<Entity, With<Text>>();
        let entities: Vec<Entity> = texts.iter(world).collect();
        for text_entity in entities {
            let Some(content) = world.get::<Text>(text_entity).map(|t| t.0.clone()) else {
                continue;
            };
            if !content.to_ascii_lowercase().contains(&needle) {
                continue;
            }
            let mut hit = actionable_ancestor(world, text_entity).unwrap_or(text_entity);
            // As in `locate`: text only the picker or dialog itself answers
            // to reports as the text, not as the whole modal.
            if matches!(kind_of(world, hit), "picker" | "dialog")
                && world.get::<ComputedNode>(text_entity).is_some()
            {
                hit = text_entity;
            }
            if !found.contains(&hit) {
                found.push(hit);
            }
        }
    }
    if let Some(kind) = kind {
        if found.is_empty() {
            // `kind` alone lists every node of that kind.
            let mut nodes = world.query_filtered::<Entity, With<Node>>();
            found = nodes.iter(world).collect();
        }
        found.retain(|entity| kind_of(world, *entity) == kind);
    }
    found.sort_by_key(|entity| entity.index());
    found.dedup();
    found
}

/// The top of the UI: the editor's own chrome and the screens the open scene
/// holds, either of which a caller may be driving.
fn ui_roots(world: &mut World) -> Vec<Entity> {
    let mut roots = world.query_filtered::<Entity, (With<Node>, Without<ChildOf>)>();
    let mut found: Vec<Entity> = roots.iter(world).collect();
    let mut screens = world.query_filtered::<Entity, With<UiSceneRoot>>();
    let scene_screens: Vec<Entity> = screens.iter(world).collect();
    for screen in scene_screens {
        if !found.contains(&screen) {
            found.push(screen);
        }
    }
    found.sort_by_key(|entity| entity.index());
    found
}

/// One `ui_tree` node, with its subtree. `index` numbers the nodes of this
/// walk in report order, so a caller can name "the third match".
fn ui_node_json(
    world: &mut World,
    entity: Entity,
    depth: u32,
    visible_only: bool,
    index: &mut u64,
) -> Value {
    let kind = kind_of(world, entity);
    let node_index = *index;
    *index += 1;
    let children: Vec<Value> = if depth == 0 {
        Vec::new()
    } else {
        let kids: Vec<Entity> = world
            .get::<Children>(entity)
            .map(|children| children.iter().collect())
            .unwrap_or_default();
        let mut subtree = Vec::with_capacity(kids.len());
        for kid in kids {
            if world.get::<ComputedNode>(kid).is_none() {
                continue;
            }
            if visible_only && !visible_through_ancestors(world, kid) {
                continue;
            }
            subtree.push(ui_node_json(
                world,
                kid,
                depth.saturating_sub(1),
                visible_only,
                index,
            ));
        }
        subtree
    };

    let node = json!({
        "entity": entity.to_bits(),
        "kind": kind,
        "text": own_label(world, entity),
        "operator": world
            .get::<ButtonOperatorCall>(entity)
            .map(|call| call.id.to_string()),
        "disabled": disabled_by_ancestor(world, entity),
        "checked": world.get::<Checked>(entity).is_some(),
        "visible": visible_through_ancestors(world, entity),
        "index": node_index,
        "scene": world.get::<UiSceneRoot>(entity).is_some(),
        "rect": placement_of(world, entity).map(|placement| placement.rect),
        "children": children,
    });
    let mut node = node;
    if kind == "slider" && placement_of(world, entity).is_some() {
        if let Some(value) = world.get::<SliderValue>(entity) {
            node["value"] = json!(value.0);
        }
        if let Some(range) = world.get::<SliderRange>(entity) {
            node["min"] = json!(range.start());
            node["max"] = json!(range.end());
        }
    }
    node
}

/// Click a control: locate it, work out where it is drawn, and queue the
/// gesture through the real picking chain. The click lands where the control
/// is; whether the control itself is what ends up hit is the truth of the
/// screen (an overlay above it would take the click, as it would a user's).
pub fn ui_click_handler(In(params): In<Option<Value>>, world: &mut World) -> BrpResult {
    check_enabled(world)?;
    let params = params.ok_or_else(|| {
        invalid_params("expected {\"entity\"} or {\"operator\"} or {\"text\" (+ \"index\")}")
    })?;
    let double = params
        .get("double")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let target = locate(world, &params)?;
    let placement = check_target(world, &target)?;

    world
        .get_resource_or_init::<SyntheticInput>()
        .queue(click_gesture(placement.centre, double, 1));

    Ok(json!({
        "clicked": true,
        "target": {
            "entity": target.entity.to_bits(),
            "kind": target.kind,
            "text": target.label,
            "operator": target.operator,
        },
        "at": [placement.centre.x, placement.centre.y],
    }))
}

/// Drag within a control, from one fraction of its box to another: the shape
/// a slider thumb, a number scrub and a split bar all read.
pub fn ui_drag_handler(In(params): In<Option<Value>>, world: &mut World) -> BrpResult {
    check_enabled(world)?;
    let params = params.ok_or_else(|| invalid_params("expected {\"entity\", \"from\", \"to\"}"))?;
    let bits = params
        .get("entity")
        .and_then(Value::as_u64)
        .ok_or_else(|| invalid_params("expected an \"entity\" to drag within"))?;
    let entity = Entity::try_from_bits(bits)
        .filter(|entity| world.get_entity(*entity).is_ok())
        .ok_or_else(|| invalid_params(format!("no entity with id {bits}")))?;
    let target = target_of(world, entity);
    let placement = check_target(world, &target)?;

    let from = fraction_point(&params, "from", &placement)?;
    let to = fraction_point(&params, "to", &placement)?;
    let steps = params
        .get("steps")
        .and_then(Value::as_u64)
        .unwrap_or(8)
        .clamp(1, 512) as u32;

    world
        .get_resource_or_init::<SyntheticInput>()
        .queue(drag_gesture(from, to, steps, 1));

    Ok(json!({
        "dragged": true,
        "entity": entity.to_bits(),
        "from": [from.x, from.y],
        "to": [to.x, to.y],
    }))
}

/// A `[fx, fy]` in `0..1` across the control's box, as a window-logical
/// position. Fractions may exceed the range for a drag that leaves the
/// control, the way a real drag can.
fn fraction_point(params: &Value, key: &str, placement: &Placement) -> Result<Vec2, BrpError> {
    let point = params
        .get(key)
        .and_then(Value::as_array)
        .and_then(|items| {
            let x = items.first()?.as_f64()?;
            let y = items.get(1)?.as_f64()?;
            #[expect(
                clippy::cast_possible_truncation,
                reason = "a pixel position is an f32 everywhere downstream"
            )]
            Some(Vec2::new(x as f32, y as f32))
        })
        .ok_or_else(|| {
            invalid_params(format!("`{key}` is two fractions in 0..1, e.g. [0.5, 0.5]"))
        })?;
    let top_left = placement.centre - placement.size / 2.0;
    Ok(top_left + point * placement.size)
}

/// Type into a control: click it focused, type the text one key at a time,
/// and commit — Enter by default (the keyboard commit chain), or `blur`
/// (a click beside the field), or `none`.
pub fn ui_input_handler(In(params): In<Option<Value>>, world: &mut World) -> BrpResult {
    check_enabled(world)?;
    let params = params
        .ok_or_else(|| invalid_params("expected a locator, \"text\" and an optional \"commit\""))?;
    let commit = params
        .get("commit")
        .and_then(Value::as_str)
        .unwrap_or("enter");
    if !matches!(commit, "enter" | "blur" | "none") {
        return Err(invalid_params("`commit` is enter (default), blur or none"));
    }
    let text = params
        .get("text")
        .and_then(Value::as_str)
        .ok_or_else(|| invalid_params("expected a \"text\" to type"))?
        .to_string();

    // `text` is what gets typed here, so it cannot also locate the field:
    // the locator is built from `entity`/`operator` (+ `index`) alone.
    let mut locator = serde_json::Map::new();
    for key in ["entity", "operator", "index"] {
        if let Some(given) = params.get(key) {
            locator.insert(key.to_string(), given.clone());
        }
    }
    let target = locate(world, &Value::Object(locator))?;
    let placement = check_target(world, &target)?;

    // One queue, one gesture: the focus click, a select-all (the click
    // positions the caret rather than selecting, so typing after one would
    // append), the typing, and the commit — in order, with no window for a
    // script's timing to miss.
    let mut beats = click_gesture(placement.centre, false, 1);
    beats.extend(select_all_gesture(1));
    beats.extend(typing_gesture(&text, 1));
    match commit {
        "enter" => beats.extend(enter_gesture(1)),
        "blur" => {
            // A click beside the field, on its own row: far enough out to be
            // past the input's hit box, near enough to stay on the row's
            // label rather than opening some other control.
            let beside = placement.centre - Vec2::new(placement.size.x / 2.0 + 8.0, 0.0);
            let beside = Vec2::new(beside.x.max(1.0), beside.y);
            beats.extend(click_gesture(beside, false, 1));
        }
        _ => {}
    }
    world.get_resource_or_init::<SyntheticInput>().queue(beats);

    Ok(json!({
        "typed": true,
        "focused": target.entity.to_bits(),
        "text": text,
        "commit": commit,
    }))
}

/// The active viewport's camera, as the look and pan assertions read it: the
/// yaw and pitch the editor itself derives, rather than a quaternion every
/// caller has to unpack.
pub fn camera_state_handler(In(_): In<Option<Value>>, world: &mut World) -> BrpResult {
    check_enabled(world)?;
    let camera = world.resource::<ActiveViewport>().camera.or_else(|| {
        let mut cameras = world.query_filtered::<Entity, With<MainViewportCamera>>();
        let mut found = cameras.iter(world);
        let first = found.next();
        first.filter(|_| found.next().is_none())
    });
    let Some(camera) = camera else {
        return Ok(json!({
            "camera": Value::Null,
            "fly": world.get_resource::<CameraFlyActive>().is_some_and(|fly| fly.0),
            "pan": world.get_resource::<CameraPanActive>().is_some_and(|pan| pan.0),
        }));
    };

    let transform = world.get::<Transform>(camera).copied();
    let projection = world.get::<Projection>(camera).cloned();
    let Some(transform) = transform else {
        return Err(invalid_params(format!(
            "the active camera {camera:?} carries no Transform"
        )));
    };

    // Compass yaw and pitch above the ground, the shapes `view.orbit` takes:
    // derived from where the camera looks, the way the scripts used to.
    let forward = transform.forward();
    let pitch = (-forward.y).asin();
    let yaw = (-forward.x).atan2(-forward.z);
    let answer = json!({
        "camera": camera.to_bits(),
        "translation": [
            transform.translation.x,
            transform.translation.y,
            transform.translation.z,
        ],
        "yaw": f64::from(yaw.to_degrees()),
        "pitch": f64::from(pitch.to_degrees()),
        "projection": match projection.as_ref() {
            Some(Projection::Orthographic(_)) => "ortho",
            _ => "perspective",
        },
        "fly": world.get_resource::<CameraFlyActive>().is_some_and(|fly| fly.0),
        "pan": world.get_resource::<CameraPanActive>().is_some_and(|pan| pan.0),
    });
    let mut answer = answer;
    if let Some(Projection::Orthographic(ortho)) = projection.as_ref() {
        answer["ortho_scale"] = json!(ortho.scale);
    }
    Ok(answer)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A laid-out node answers with a box; the formula is the one
    /// `tests/controls/synthetic_click.rs` pinned end to end.
    #[test]
    fn a_hidden_node_is_reported_invisible() {
        let mut world = World::new();
        let parent = world.spawn((Node::default(), Visibility::Hidden)).id();
        let child = world.spawn((Node::default(), ChildOf(parent))).id();
        assert!(!visible_through_ancestors(&world, child));
        assert!(!visible_through_ancestors(&world, parent));

        world.entity_mut(parent).insert(Visibility::Inherited);
        assert!(visible_through_ancestors(&world, child));
        let bare = world.spawn_empty().id();
        assert!(visible_through_ancestors(&world, bare));
    }

    /// The disable marker counts from an ancestor: a section that disables
    /// itself disables every control in it.
    #[test]
    fn a_disabled_ancestor_disables_the_control() {
        let mut world = World::new();
        let section = world.spawn((Node::default(), InteractionDisabled)).id();
        let row = world.spawn((Node::default(), ChildOf(section))).id();
        assert!(disabled_by_ancestor(&world, row));
        let plain = world.spawn(Node::default()).id();
        assert!(!disabled_by_ancestor(&world, plain));
    }

    /// The kind a node reports is the narrowest thing it is.
    #[test]
    fn a_node_reports_its_narrowest_kind() {
        let mut world = World::new();
        let plain = world.spawn((Node::default(),)).id();
        let text = world.spawn((Node::default(), Text::new("Hello"))).id();
        let slider = world
            .spawn((
                Node::default(),
                FeathersSlider,
                SliderValue(0.4),
                SliderRange::new(0.0, 1.0),
            ))
            .id();
        assert_eq!(kind_of(&world, plain), "node");
        assert_eq!(kind_of(&world, text), "text");
        assert_eq!(kind_of(&world, slider), "slider");
        assert_eq!(
            world.get::<SliderRange>(slider).map(SliderRange::end),
            Some(1.0)
        );
    }

    /// Yaw and pitch come out in the compass shapes `view.orbit` takes, from
    /// an orientation built the same way that operator builds one.
    #[test]
    fn yaw_and_pitch_read_back_compass_degrees() {
        let mut world = World::new();
        let yaw = 135.0_f32.to_radians();
        let pitch = 30.0_f32.to_radians();
        let offset = Vec3::new(
            yaw.sin() * pitch.cos(),
            pitch.sin(),
            yaw.cos() * pitch.cos(),
        );
        let camera = world
            .spawn(Transform::from_translation(offset * 10.0).looking_at(Vec3::ZERO, Vec3::Y))
            .id();
        let transform = world.get::<Transform>(camera).copied().unwrap();
        let forward = transform.forward();
        let read_pitch = (-forward.y).asin().to_degrees();
        let read_yaw = (-forward.x).atan2(-forward.z).to_degrees();
        assert!((read_yaw - 135.0).abs() < 0.01, "yaw read {read_yaw}");
        assert!((read_pitch - 30.0).abs() < 0.01, "pitch read {read_pitch}");
    }

    /// The builder smoke: a world with a placement answers centre and rect.
    #[test]
    fn a_fraction_maps_onto_the_controls_box() {
        let placement = Placement {
            centre: Vec2::new(100.0, 60.0),
            size: Vec2::new(80.0, 20.0),
            rect: [60.0, 50.0, 80.0, 20.0],
        };
        let params = json!({ "from": [0.0, 0.5], "to": [1.0, 0.5] });
        assert_eq!(
            fraction_point(&params, "from", &placement).unwrap(),
            Vec2::new(60.0, 60.0)
        );
        assert_eq!(
            fraction_point(&params, "to", &placement).unwrap(),
            Vec2::new(140.0, 60.0)
        );
        assert!(fraction_point(&json!({}), "from", &placement).is_err());
    }
}
