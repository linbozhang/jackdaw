//! The rows an animation card carries beyond its reflected fields: the graphs
//! a rig can be pointed at, the way from a set of clips to a graph, and the
//! references its author would otherwise only hear about at run time.

use bevy::picking::hover::Hovered;
use bevy::prelude::*;
use jackdaw_animation_runtime::{AnimationGraphRef, AnimationSet};
use jackdaw_api::op::Operator as _;
use jackdaw_feathers::{
    button::{ButtonOperatorCall, ButtonProps, ButtonSize, ButtonVariant, button},
    tokens,
    tooltip::Tooltip,
};

use jackdaw_editor_core::animation_mode::library::AnimationLibrary;
use jackdaw_editor_core::project::ProjectRoot;
use crate::graph_doc::graph_files;
use crate::graph_ops::{AnimationGraphAssignOp, AnimationGraphConvertSetOp};

/// List the project's graph files under an [`AnimationGraphRef`] card, so the
/// path is picked rather than typed, and say so when the held path names
/// none of them.
pub(super) fn fill_graph_reference_picker(world: &mut World, entity: Entity, body: Entity) {
    let held = world
        .get::<AnimationGraphRef>(entity)
        .map(|reference| reference.path.clone())
        .unwrap_or_default();
    let files = graph_files(world);
    if !held.is_empty() && !files.contains(&held) {
        spawn_error_row(
            world,
            body,
            &format!("no graph file named `{held}` in this project"),
        );
    }
    let column = world
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                row_gap: Val::Px(tokens::SPACING_XS),
                margin: UiRect::bottom(Val::Px(tokens::SPACING_XS)),
                ..default()
            },
            ChildOf(body),
        ))
        .id();
    if files.is_empty() {
        world.spawn((
            Text::new("No graph file in this project yet."),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..default()
            },
            TextColor(tokens::TEXT_SECONDARY),
            ChildOf(column),
        ));
        return;
    }
    for path in files {
        let variant = if path == held {
            ButtonVariant::Active
        } else {
            ButtonVariant::Ghost
        };
        let row = world
            .spawn((
                button(
                    ButtonProps::new(path.clone())
                        .with_variant(variant)
                        .with_size(ButtonSize::MD)
                        .align_left(),
                ),
                ButtonOperatorCall::new(AnimationGraphAssignOp::ID).with_param("path", path),
            ))
            .id();
        world.entity_mut(row).insert(ChildOf(column));
    }
}

/// Offer the way to a graph on an [`AnimationSet`] card that has none, and
/// badge the states whose clip references the project cannot keep.
pub(super) fn fill_animation_set_actions(world: &mut World, entity: Entity, body: Entity) {
    let Some(set) = world.get::<AnimationSet>(entity).cloned() else {
        return;
    };
    let assets = world
        .get_resource::<ProjectRoot>()
        .map(ProjectRoot::assets_dir);
    let problems = {
        let library = world.get_resource::<AnimationLibrary>();
        let clips_of = |path: &str| {
            library.and_then(|library| {
                library
                    .file(path)
                    .map(|file| file.clips.iter().map(|clip| clip.name.clone()).collect())
            })
        };
        let on_disk = |path: &str| {
            assets
                .as_deref()
                .is_some_and(|dir| dir.join(path).is_file())
        };
        set_reference_problems(&set, &clips_of, &on_disk)
    };
    for problem in problems {
        spawn_error_row(world, body, &problem);
    }
    if world.get::<AnimationGraphRef>(entity).is_some() {
        return;
    }
    let action = world
        .spawn((
            button(
                ButtonProps::new("Convert to graph")
                    .with_variant(ButtonVariant::Default)
                    .with_size(ButtonSize::MD),
            ),
            ButtonOperatorCall::new(AnimationGraphConvertSetOp::ID),
        ))
        .id();
    world.entity_mut(action).insert(ChildOf(body));
}

/// One error row, in the shape the bindings card badges a row with: the text
/// painted in the error color, the detail on hover. A badge, never a gate —
/// the set still plays what it can.
fn spawn_error_row(world: &mut World, body: Entity, problem: &str) {
    world
        .spawn((
            Text::new(problem.to_string()),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..default()
            },
            TextColor(tokens::TEXT_ERROR),
        ))
        .insert((
            // `Hovered` is opt-in and the tooltip renderer reads the pair.
            Hovered::default(),
            Tooltip::title(problem.to_string()),
            ChildOf(body),
        ));
}

/// What is wrong with a set's clip references, in reading order, one line per
/// state: a source index the set cannot name, a source file missing from the
/// project, or a clip the named file does not hold. A source the library has
/// not indexed yet but that is on disk draws nothing — the library answers
/// "which clips a file holds" only once it has read the file, and an answer
/// asked for too soon is not an error.
fn set_reference_problems(
    set: &AnimationSet,
    clips_of: &dyn Fn(&str) -> Option<Vec<String>>,
    on_disk: &dyn Fn(&str) -> bool,
) -> Vec<String> {
    let mut problems = Vec::new();
    for state in &set.states {
        let Some(path) = set.sources.get(state.source) else {
            problems.push(format!(
                "animation state `{}` names source {}, and the set lists {}",
                state.name,
                state.source,
                plural_sources(set.sources.len()),
            ));
            continue;
        };
        let Some(clips) = clips_of(path) else {
            if !on_disk(path) {
                problems.push(format!(
                    "animation state `{}` names source `{path}`, which is not in the project",
                    state.name
                ));
            }
            continue;
        };
        if !clips.iter().any(|clip| clip == &state.clip) {
            problems.push(format!(
                "animation state `{}` wants clip `{}`, and `{path}` holds {}",
                state.name,
                state.clip,
                list_names(&clips),
            ));
        }
    }
    problems
}

fn plural_sources(count: usize) -> String {
    match count {
        0 => "no sources".to_string(),
        1 => "1 source".to_string(),
        n => format!("{n} sources"),
    }
}

/// Names as a sentence list, or "none" for an empty file.
fn list_names(clips: &[String]) -> String {
    match clips {
        [] => "no clips".to_string(),
        [only] => format!("only `{only}`"),
        [rest @ .., last] => format!(
            "{}`{last}`",
            rest.iter()
                .map(|name| format!("`{name}`, "))
                .collect::<String>()
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use jackdaw_animation_runtime::AnimationStateDef;

    fn set(sources: &[&str], states: Vec<AnimationStateDef>) -> AnimationSet {
        AnimationSet {
            sources: sources.iter().map(ToString::to_string).collect(),
            states,
            ..Default::default()
        }
    }

    fn state(name: &str, source: usize, clip: &str) -> AnimationStateDef {
        AnimationStateDef {
            name: name.to_string(),
            source,
            clip: clip.to_string(),
            ..Default::default()
        }
    }

    /// The clips the library would answer for each file, by path.
    fn indexed(
        files: Vec<(&'static str, Vec<&'static str>)>,
    ) -> impl Fn(&str) -> Option<Vec<String>> {
        move |path: &str| {
            files
                .iter()
                .find(|(known, _)| *known == path)
                .map(|(_, clips)| clips.iter().map(ToString::to_string).collect())
        }
    }

    #[test]
    fn a_state_naming_a_clip_its_source_does_not_hold_is_reported_with_the_clips_it_holds() {
        let hero = indexed(vec![("models/hero.glb", vec!["Idle_Loop", "Walk_Loop"])]);
        let problems = set_reference_problems(
            &set(&["models/hero.glb"], vec![state("walk", 0, "Walk")]),
            &hero,
            &|_| true,
        );
        assert_eq!(
            problems,
            vec![
                "animation state `walk` wants clip `Walk`, and `models/hero.glb` holds \
                 `Idle_Loop`, `Walk_Loop`"
            ]
        );
    }

    #[test]
    fn a_source_out_of_range_and_a_file_missing_from_the_project_are_reported() {
        let problems = set_reference_problems(
            &set(
                &["models/nowhere.glb"],
                vec![state("jump", 3, "Jump"), state("idle", 0, "Idle_Loop")],
            ),
            &indexed(vec![]),
            &|_| false,
        );
        assert_eq!(
            problems,
            vec![
                "animation state `jump` names source 3, and the set lists 1 source",
                "animation state `idle` names source `models/nowhere.glb`, which is not \
                 in the project",
            ]
        );
    }

    #[test]
    fn a_set_whose_references_all_resolve_draws_nothing() {
        let hero = indexed(vec![("models/hero.glb", vec!["Idle_Loop", "Jump"])]);

        // Every state names a clip its indexed source holds.
        assert!(
            set_reference_problems(
                &set(
                    &["models/hero.glb"],
                    vec![state("idle", 0, "Idle_Loop"), state("jump", 0, "Jump")],
                ),
                &hero,
                &|_| true,
            )
            .is_empty()
        );

        // A file on disk that the library has not read yet is not an error
        // either: it may hold the clip, and the run time is the judge.
        assert!(
            set_reference_problems(
                &set(&["models/fresh.glb"], vec![state("walk", 0, "Walk_Loop")]),
                &indexed(vec![]),
                &|_| true,
            )
            .is_empty()
        );
    }
}
