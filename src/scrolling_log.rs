//! Reusable scrolling log widget.
//!
//! Fixed-height text panel that displays accumulating text and
//! auto-pins to the bottom whenever its content grows. Consumers
//! mutate [`ScrollingLog::content`]; [`refresh_scrolling_logs`]
//! propagates the change into the inner text child and snaps
//! [`ScrollPosition`] to the bottom on the next layout pass. When
//! `auto_hide_when_empty` is set, the panel collapses entirely
//! ([`Display::None`]) so consumers don't have to manage visibility.

use bevy::prelude::*;
use bevy::text::FontSize;
use jackdaw_feathers::tokens;

pub struct ScrollingLogPlugin;

impl Plugin for ScrollingLogPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, refresh_scrolling_logs);
    }
}

#[derive(Component, Default)]
pub struct ScrollingLog {
    pub content: String,
    pub auto_hide_when_empty: bool,
}

/// Marker on the inner [`Text`] entity refreshed from the parent's
/// [`ScrollingLog::content`].
#[derive(Component)]
pub struct ScrollingLogText;

pub struct ScrollingLogProps {
    pub max_height: Val,
    pub margin: UiRect,
    pub font: Handle<Font>,
    pub font_size: FontSize,
    pub text_color: Color,
    pub background: Color,
    /// Collapse the panel when [`ScrollingLog::content`] is empty
    /// (the typical "show once we have something to show" pattern).
    pub auto_hide_when_empty: bool,
}

impl Default for ScrollingLogProps {
    fn default() -> Self {
        Self {
            max_height: Val::Px(220.0),
            margin: UiRect::all(Val::Px(5.0)),
            font: Handle::default(),
            font_size: tokens::TEXT_SIZE_SM,
            text_color: Color::WHITE,
            background: Color::NONE,
            auto_hide_when_empty: false,
        }
    }
}

/// Spawn a scrolling-log widget as a child of `parent`. Returns the
/// container entity; mutate its [`ScrollingLog`] to update the text.
pub fn spawn(world: &mut World, parent: Entity, props: ScrollingLogProps) -> Entity {
    let initial_display = if props.auto_hide_when_empty {
        Display::None
    } else {
        Display::Flex
    };
    let container = world
        .spawn((
            ScrollingLog {
                content: String::new(),
                auto_hide_when_empty: props.auto_hide_when_empty,
            },
            Node {
                width: Val::Percent(100.0),
                max_height: props.max_height,
                margin: props.margin,
                overflow: Overflow::scroll_y(),
                padding: UiRect::all(Val::Px(8.0)),
                display: initial_display,
                ..Default::default()
            },
            BackgroundColor(props.background),
            // The refresh query matches on this component; spelled out
            // here rather than left to `Node`'s required components so
            // the widget's own contract is visible — and survives bevy
            // changing what Node requires (bug R9's shape).
            ScrollPosition::default(),
            ChildOf(parent),
        ))
        .id();
    world.spawn((
        ScrollingLogText,
        Text::new(String::new()),
        TextFont {
            font: props.font.into(),
            font_size: props.font_size,
            ..Default::default()
        },
        TextColor(props.text_color),
        ChildOf(container),
    ));
    container
}

pub fn refresh_scrolling_logs(
    mut logs: Query<
        (&ScrollingLog, &Children, &mut ScrollPosition, &mut Node),
        Changed<ScrollingLog>,
    >,
    mut texts: Query<&mut Text, With<ScrollingLogText>>,
) {
    for (log, children, mut scroll, mut node) in &mut logs {
        if log.auto_hide_when_empty {
            let desired = if log.content.is_empty() {
                Display::None
            } else {
                Display::Flex
            };
            if node.display != desired {
                node.display = desired;
            }
        }
        for child in children.iter() {
            let Ok(mut text) = texts.get_mut(child) else {
                continue;
            };
            if text.0 != log.content {
                text.0 = log.content.clone();
                // Bevy clamps to the layout-computed extent next
                // frame, so f32::MAX pins to bottom.
                scroll.y = f32::MAX;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::ecs::system::RunSystemOnce;

    /// The widget must actually display its content: a changed
    /// `ScrollingLog::content` reaches the inner text child and pins
    /// the scroll position to the bottom. The refresh query requires a
    /// `ScrollPosition` on the container, so a `spawn` that leaves it
    /// out never matches — the Build panel shows an empty log forever
    /// (bug R9). Driven headless: the widget spawned as in the panel,
    /// the content set as the panel sets it, the refresh system run
    /// once as the schedule would.
    #[test]
    fn changed_content_reaches_the_inner_text_and_pins_to_the_bottom() {
        let mut world = World::new();
        let parent = world.spawn(Node::default()).id();
        let widget = spawn(&mut world, parent, ScrollingLogProps::default());
        {
            let mut log = world.get_mut::<ScrollingLog>(widget).unwrap();
            log.content = "error[E0560]: no field `x` (src/lib.rs:40:13)".to_string();
        }

        world.run_system_once(refresh_scrolling_logs).unwrap();

        let children: Vec<Entity> = world.get::<Children>(widget).unwrap().iter().collect();
        let text = world.get::<Text>(children[0]).unwrap();
        assert_eq!(
            text.0, "error[E0560]: no field `x` (src/lib.rs:40:13)",
            "the changed content is what the widget displays"
        );
        let scroll = world
            .get::<ScrollPosition>(widget)
            .expect("the container carries a scroll position");
        assert!(scroll.y > 0.0, "new content pins the panel to the bottom");
    }
}
