//! The Graphics panel: one dockable surface over the two layers that already
//! decide picture quality.
//!
//! The Viewport section drives the editor-only preview through the
//! `viewport.*` operators ([`crate::viewport_settings`]): no undo, kept per
//! user in `viewport.json`, never in the scene. The Scene section is a UI skin
//! over `environment.set` ([`crate::environment_ops`]): every control is one
//! field of the scene's `Environment.post`, one undo entry each, saved with
//! the scene. The panel adds no storage of its own.
//!
//! Realtime global illumination stays as a disabled row: bevy's Solari is
//! experimental, needs hardware ray tracing and its own cargo feature, and
//! jackdaw has not adopted it. The tooltip names the substitutes that exist.

use bevy::feathers::controls::FeathersCheckbox;
use bevy::feathers::theme::ThemedText;
use bevy::picking::hover::Hovered;
use bevy::prelude::*;
use bevy::ui::{Checked, InteractionDisabled};
use bevy::ui_widgets::{SliderValue, ValueChange};
use jackdaw_api::prelude::*;
use jackdaw_api_internal::operator::{CallOperatorSettings, ExecutionContext};
use jackdaw_feathers::combobox::{
    ComboBoxChangeEvent, ComboBoxOptionData, ComboBoxSelectedIndex, combobox_with_selected,
};
use jackdaw_feathers::field_row::{FieldRow, FieldRowProps, spawn_field_row};
use jackdaw_feathers::options_bar::spawn_checkbox;
use jackdaw_feathers::segmented;
use jackdaw_feathers::slider_row::{FieldKind, SliderRowProps, spawn_slider_row};
use jackdaw_feathers::tokens;
use jackdaw_feathers::tooltip::Tooltip;
use jackdaw_feathers::utils::set_marker_if_alive;
use jackdaw_localization::Localization;
use jackdaw_scene_types::{Environment, PostProcess, Tonemapper};

use crate::environment_ops::EnvironmentSetOp;
use crate::viewport_settings::{
    AntiAliasing, MIN_RENDER_SCALE, QualityPreset, SsaoQuality, ViewportQualityPresetOp,
    ViewportQualitySetOp, ViewportSettings, ViewportSharpenSetOp, ViewportShowToggleOp,
    ViewportSsaoSetOp,
};

/// Dock window id, used for registration and presence checks.
pub const GRAPHICS_WINDOW_ID: &str = "jackdaw.graphics";

/// The tonemappers the Scene section offers, in dropdown order. The variant
/// names are what `environment.set` matches `post.tonemapper` against.
const TONEMAPPERS: [Tonemapper; 9] = [
    Tonemapper::TonyMcMapface,
    Tonemapper::None,
    Tonemapper::Reinhard,
    Tonemapper::ReinhardLuminance,
    Tonemapper::AcesFitted,
    Tonemapper::AgX,
    Tonemapper::SomewhatBoringDisplayTransform,
    Tonemapper::BlenderFilmic,
    Tonemapper::KhronosPbrNeutral,
];

/// The exposure slider's range, in EV100.
const EXPOSURE_RANGE: std::ops::Range<f32> = -5.0..20.0;
/// The bloom sliders' range.
const BLOOM_RANGE: std::ops::Range<f32> = 0.0..1.0;
/// The sharpening strength slider's range.
const SHARPEN_RANGE: std::ops::Range<f32> = 0.0..1.0;

pub(crate) fn plugin(app: &mut App) {
    app.add_systems(
        Update,
        (
            populate_graphics_panel,
            sync_viewport_fields,
            sync_scene_fields,
            update_opt_out_hint,
            update_scene_empty_hint,
        ),
    )
    .add_observer(on_segment_pick)
    .add_observer(on_toggle)
    .add_observer(on_slider)
    .add_observer(on_tonemapper_pick);
}

pub(crate) fn add_to_extension(ctx: &mut ExtensionContext) {
    ctx.register_operator::<GraphicsOpenOp>();
}

/// Open the Graphics panel, or bring its tab to the front.
#[operator(
    id = "graphics.open",
    label = "Open Graphics Panel",
    description = "Open the graphics quality panel: the viewport's preview settings beside the \
                   scene's post-processing.",
    allows_undo = false
)]
pub(crate) fn graphics_open(_params: In<OperatorParameters>, world: &mut World) -> OperatorResult {
    crate::open_window_in_default_area_if_absent(world, GRAPHICS_WINDOW_ID);
    OperatorResult::Finished
}

/// How a user-facing dispatch asks for an operator: like a menu row, allowed
/// to ask for undo. The `viewport.*` family opts out on its own
/// (`allows_undo = false`), and `environment.set` makes its own single entry,
/// so nothing here can double up the history.
fn user_action() -> CallOperatorSettings {
    CallOperatorSettings {
        execution_context: ExecutionContext::Invoke,
        creates_history_entry: true,
    }
}

/// Marker on the panel's content root, laid out in the window's tab.
#[derive(Component)]
pub struct GraphicsPanel;

/// One segment of a segmented row, and the choice it stands for.
#[derive(Component, Clone, Copy, Debug, PartialEq, Eq)]
pub enum GraphicsSegment {
    Preset(QualityPreset),
    AntiAlias(AntiAliasing),
    SsaoQuality(SsaoQuality),
}

/// One checkbox row. [`GraphicsToggle::PostProcessing`] is the Scene
/// section's; the rest are the Viewport section's.
#[derive(Component, Clone, Copy, Debug, PartialEq, Eq)]
pub enum GraphicsToggle {
    AmbientOcclusion,
    SunShadows,
    PointShadows,
    Fog,
    Sharpening,
    PostProcessing,
}

impl GraphicsToggle {
    /// The `viewport.show.toggle` flag this row flips, if it is one.
    fn show_flag(self) -> Option<&'static str> {
        match self {
            Self::SunShadows => Some("sun_shadows"),
            Self::PointShadows => Some("point_shadows"),
            Self::Fog => Some("fog"),
            _ => None,
        }
    }
}

/// One slider row. The Scene sliders are the ones that must commit on
/// release; the Viewport sliders are editor-only preferences with no undo to
/// protect, so they write live.
#[derive(Component, Clone, Copy, Debug, PartialEq, Eq)]
pub enum GraphicsSlider {
    RenderScale,
    SharpenStrength,
    Exposure,
    BloomIntensity,
    BloomThreshold,
}

impl GraphicsSlider {
    /// The `environment.set` field path this slider drives, if it is one.
    fn scene_path(self) -> Option<&'static str> {
        match self {
            Self::Exposure => Some("post.exposure"),
            Self::BloomIntensity => Some("post.bloom_intensity"),
            Self::BloomThreshold => Some("post.bloom_threshold"),
            _ => None,
        }
    }
}

/// The Scene section's tonemapper dropdown.
#[derive(Component)]
pub struct GraphicsTonemapperField;

/// The note that the viewport is not previewing the scene's post-processing,
/// shown while the Viewport section opts out of it.
#[derive(Component)]
pub struct GraphicsOptOutHint;

/// The note that the scene carries no `Environment`, so the Scene section's
/// controls have nothing to write — shown instead of them sitting silently
/// inert, and hidden once an environment exists.
#[derive(Component)]
pub struct GraphicsSceneEmptyHint;

/// The disabled Realtime GI row.
#[derive(Component)]
pub struct GraphicsRealtimeGi;

/// The panel's content root, which the window's tab builds and the
/// `Added<GraphicsPanel>` pass fills in.
pub fn graphics_panel_root() -> impl Bundle {
    (
        GraphicsPanel,
        Node {
            flex_direction: FlexDirection::Column,
            width: percent(100),
            height: percent(100),
            flex_grow: 1.0,
            row_gap: px(tokens::SPACING_LG),
            padding: UiRect::all(px(tokens::SPACING_MD)),
            overflow: Overflow::scroll_y(),
            ..default()
        },
    )
}

/// Resolve `key` from the active locale, or hand back the key itself so a
/// missing entry is readable rather than blank.
fn text(localization: &Localization, key: &str) -> String {
    localization.content(key).unwrap_or_else(|| key.to_string())
}

/// Fill a freshly built panel: the Viewport section from the user's settings,
/// the Scene section from the open scene's environment (or the defaults while
/// no scene carries one), then the disabled GI row.
fn populate_graphics_panel(
    panels: Query<Entity, Added<GraphicsPanel>>,
    localization: Res<Localization>,
    settings: Res<ViewportSettings>,
    environments: Query<&Environment>,
    mut commands: Commands,
) {
    for panel in &panels {
        let scene_environment = environments.iter().next();
        let post = scene_environment.map_or_else(PostProcess::default, |env| env.post.clone());
        build_viewport_section(&mut commands, panel, &settings, &localization);
        build_scene_section(
            &mut commands,
            panel,
            &post,
            scene_environment.is_some(),
            &localization,
        );
        build_realtime_gi_row(&mut commands, panel, &localization);
    }
}

/// A section heading with a one-line note under it.
fn spawn_section(commands: &mut Commands, parent: Entity, title: String, note: String) -> Entity {
    let section = commands
        .spawn((
            Node {
                flex_direction: FlexDirection::Column,
                width: percent(100),
                row_gap: px(tokens::SPACING_XS),
                ..default()
            },
            ChildOf(parent),
        ))
        .id();
    commands.spawn((
        Text::new(title),
        TextFont {
            font_size: tokens::TEXT_SIZE_SM,
            weight: FontWeight::SEMIBOLD,
            ..default()
        },
        TextColor(tokens::TEXT_PRIMARY),
        ChildOf(section),
    ));
    commands.spawn((
        Text::new(note),
        TextFont {
            font_size: tokens::TEXT_SIZE_XS,
            ..default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        ChildOf(section),
    ));
    section
}

/// A labeled row whose control is a segmented bar, one segment per choice.
/// The current choice is seeded (`Checked`, filled background, primary label)
/// so the row is right before any setting ever changes.
fn spawn_segmented_row(
    commands: &mut Commands,
    parent: Entity,
    label: String,
    choices: impl IntoIterator<Item = (GraphicsSegment, &'static str)>,
    is_current: impl Fn(&GraphicsSegment) -> bool,
) {
    let FieldRow { control, .. } = spawn_field_row(commands, parent, FieldRowProps::new(label));
    let bar = commands
        .spawn((segmented::segmented_bar(), ChildOf(control)))
        .id();
    for (segment, name) in choices {
        let current = is_current(&segment);
        let node = commands
            .spawn((
                segment,
                segmented::segment_node(),
                segmented::segment_chrome(),
                ChildOf(bar),
            ))
            .id();
        if current {
            commands.entity(node).insert((
                Checked,
                BackgroundColor(segmented::segment_background(true)),
            ));
        }
        commands.spawn((
            Text::new(name),
            TextFont {
                font_size: tokens::TEXT_SIZE_SM,
                ..default()
            },
            TextColor(if current {
                tokens::TEXT_PRIMARY
            } else {
                tokens::TEXT_SECONDARY
            }),
            ChildOf(node),
        ));
    }
}

/// The Viewport section: the editor's own preview of the scene.
fn build_viewport_section(
    commands: &mut Commands,
    panel: Entity,
    settings: &ViewportSettings,
    localization: &Localization,
) {
    let section = spawn_section(
        commands,
        panel,
        text(localization, "graphics-viewport-section"),
        text(localization, "graphics-viewport-note"),
    );
    let quality = settings.quality;
    let preset = settings.preset();

    spawn_segmented_row(
        commands,
        section,
        text(localization, "graphics-preset"),
        QualityPreset::ALL.map(|preset| (GraphicsSegment::Preset(preset), preset.label())),
        |segment| matches!(segment, GraphicsSegment::Preset(choice) if Some(*choice) == preset),
    );
    spawn_slider_row(
        commands,
        section,
        SliderRowProps::new(
            text(localization, "graphics-render-scale"),
            quality.render_scale as f32,
            MIN_RENDER_SCALE as f32..100.0,
        )
        .with_kind(FieldKind::Count),
        GraphicsSlider::RenderScale,
    );
    spawn_segmented_row(
        commands,
        section,
        text(localization, "graphics-anti-aliasing"),
        AntiAliasing::ALL.map(|choice| (GraphicsSegment::AntiAlias(choice), choice.label())),
        |segment| matches!(segment, GraphicsSegment::AntiAlias(choice) if *choice == quality.anti_aliasing),
    );

    spawn_checkbox(
        commands,
        section,
        &text(localization, "graphics-ssao"),
        quality.ambient_occlusion,
        GraphicsToggle::AmbientOcclusion,
    );
    spawn_segmented_row(
        commands,
        section,
        text(localization, "graphics-ssao-quality"),
        SsaoQuality::ALL.map(|choice| (GraphicsSegment::SsaoQuality(choice), choice.label())),
        |segment| matches!(segment, GraphicsSegment::SsaoQuality(choice) if *choice == quality.ssao_quality),
    );

    for (toggle, key) in [
        (GraphicsToggle::SunShadows, "graphics-sun-shadows"),
        (GraphicsToggle::PointShadows, "graphics-point-shadows"),
        (GraphicsToggle::Fog, "graphics-fog"),
    ] {
        let on = match toggle {
            GraphicsToggle::SunShadows => quality.sun_shadows,
            GraphicsToggle::PointShadows => quality.point_shadows,
            _ => quality.fog,
        };
        spawn_checkbox(commands, section, &text(localization, key), on, toggle);
    }

    spawn_checkbox(
        commands,
        section,
        &text(localization, "graphics-sharpen"),
        settings.sharpen,
        GraphicsToggle::Sharpening,
    );
    spawn_slider_row(
        commands,
        section,
        SliderRowProps::new(
            text(localization, "graphics-sharpen-strength"),
            settings.sharpen_strength,
            SHARPEN_RANGE,
        )
        .indented(1),
        GraphicsSlider::SharpenStrength,
    );
}

/// The Scene section: the environment every camera in the game is dressed by.
/// `scene_has_environment` seeds the empty note's visibility so it is right on
/// the first frame; `update_scene_empty_hint` keeps it right afterwards.
fn build_scene_section(
    commands: &mut Commands,
    panel: Entity,
    post: &PostProcess,
    scene_has_environment: bool,
    localization: &Localization,
) {
    let section = spawn_section(
        commands,
        panel,
        text(localization, "graphics-scene-section"),
        text(localization, "graphics-scene-note"),
    );

    spawn_checkbox(
        commands,
        section,
        &text(localization, "graphics-post-processing"),
        post.enabled,
        GraphicsToggle::PostProcessing,
    );

    let FieldRow { control, .. } = spawn_field_row(
        commands,
        section,
        FieldRowProps::new(text(localization, "graphics-tonemapper")),
    );
    let selected = TONEMAPPERS
        .iter()
        .position(|choice| *choice == post.tonemapper)
        .unwrap_or(0);
    let options = TONEMAPPERS
        .iter()
        .map(|choice| {
            ComboBoxOptionData::new(variant_name(*choice)).with_value(variant_name(*choice))
        })
        .collect::<Vec<_>>();
    commands.spawn((
        GraphicsTonemapperField,
        combobox_with_selected(options, selected),
        ChildOf(control),
    ));

    for (slider, key, value, range) in [
        (
            GraphicsSlider::Exposure,
            "graphics-exposure",
            post.exposure,
            EXPOSURE_RANGE,
        ),
        (
            GraphicsSlider::BloomIntensity,
            "graphics-bloom-intensity",
            post.bloom_intensity,
            BLOOM_RANGE,
        ),
        (
            GraphicsSlider::BloomThreshold,
            "graphics-bloom-threshold",
            post.bloom_threshold,
            BLOOM_RANGE,
        ),
    ] {
        spawn_slider_row(
            commands,
            section,
            SliderRowProps::new(text(localization, key), value, range),
            slider,
        );
    }

    let empty_display = if scene_has_environment {
        Display::None
    } else {
        Display::Flex
    };
    commands.spawn((
        GraphicsSceneEmptyHint,
        Text::new(text(localization, "graphics-scene-empty-hint")),
        TextFont {
            font_size: tokens::TEXT_SIZE_XS,
            ..default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        Node {
            display: empty_display,
            width: percent(100),
            ..default()
        },
        ChildOf(section),
    ));

    commands.spawn((
        GraphicsOptOutHint,
        Text::new(text(localization, "graphics-opt-out-hint")),
        TextFont {
            font_size: tokens::TEXT_SIZE_XS,
            ..default()
        },
        TextColor(tokens::TEXT_SECONDARY),
        Node {
            display: Display::None,
            width: percent(100),
            ..default()
        },
        ChildOf(section),
    ));
}

/// The Realtime GI row: named but disabled, with the tooltip saying why and
/// what stands in for it.
fn build_realtime_gi_row(commands: &mut Commands, panel: Entity, localization: &Localization) {
    let caption = text(localization, "graphics-realtime-gi");
    let FieldRow { row, control } =
        spawn_field_row(commands, panel, FieldRowProps::new(caption.clone()));
    let hint = text(localization, "graphics-realtime-gi-tooltip");
    commands.entity(row).insert((
        GraphicsRealtimeGi,
        Tooltip::title(caption.clone()).with_description(hint),
        Hovered::default(),
    ));
    commands
        .spawn_scene(bsn! {
            @FeathersCheckbox { @caption: bsn! { Text(caption) ThemedText } }
        })
        .insert((InteractionDisabled, ChildOf(control)));
}

/// A segment picked in one of the panel's segmented rows.
fn on_segment_pick(
    event: On<ValueChange<Entity>>,
    segments: Query<&GraphicsSegment>,
    mut commands: Commands,
) {
    let Ok(&segment) = segments.get(event.value) else {
        return;
    };
    let call = match segment {
        GraphicsSegment::Preset(preset) => commands
            .operator(ViewportQualityPresetOp::ID)
            .param("preset", preset.label().to_ascii_lowercase()),
        GraphicsSegment::AntiAlias(choice) => commands
            .operator(ViewportQualitySetOp::ID)
            .param("anti_aliasing", choice.label().to_ascii_lowercase()),
        GraphicsSegment::SsaoQuality(quality) => commands
            .operator(ViewportSsaoSetOp::ID)
            .param("quality", quality.label().to_ascii_lowercase()),
    };
    call.settings(user_action()).call();
}

/// A checkbox toggled: reflect the new state onto the widget (`FeathersCheckbox`
/// does not self-manage `Checked`), then dispatch the operator behind it.
fn on_toggle(
    event: On<ValueChange<bool>>,
    toggles: Query<&GraphicsToggle>,
    mut commands: Commands,
) {
    let target = event.event_target();
    let Ok(&toggle) = toggles.get(target) else {
        return;
    };
    set_marker_if_alive::<Checked>(&mut commands, target, event.value);
    let call = match toggle {
        GraphicsToggle::AmbientOcclusion => commands
            .operator(ViewportSsaoSetOp::ID)
            .param("on", event.value),
        GraphicsToggle::Sharpening => commands
            .operator(ViewportSharpenSetOp::ID)
            .param("on", event.value),
        GraphicsToggle::PostProcessing => commands
            .operator(EnvironmentSetOp::ID)
            .param("post.enabled", event.value),
        flagged => {
            let Some(flag) = flagged.show_flag() else {
                return;
            };
            commands
                .operator(ViewportShowToggleOp::ID)
                .param("flag", flag)
                .param("on", event.value)
        }
    };
    call.settings(user_action()).call();
}

/// A slider moved. The Viewport sliders are editor preferences: every tick
/// goes straight through. The Scene sliders hold scene data, so only the
/// release (`is_final`) dispatches, keeping one drag one undo entry; the
/// ticks re-insert `SliderValue` so the fill and digits follow the gesture.
fn on_slider(event: On<ValueChange<f32>>, sliders: Query<&GraphicsSlider>, mut commands: Commands) {
    let target = event.event_target();
    let Ok(&slider) = sliders.get(target) else {
        return;
    };
    let Some(path) = slider.scene_path() else {
        let call = match slider {
            GraphicsSlider::RenderScale => commands
                .operator(ViewportQualitySetOp::ID)
                .param("render_scale", event.value.round() as i64),
            GraphicsSlider::SharpenStrength => commands
                .operator(ViewportSharpenSetOp::ID)
                .param("strength", f64::from(event.value)),
            _ => return,
        };
        call.settings(user_action()).call();
        return;
    };
    if !event.is_final {
        commands.entity(target).insert(SliderValue(event.value));
        return;
    }
    commands
        .operator(EnvironmentSetOp::ID)
        .param(path, f64::from(event.value))
        .settings(user_action())
        .call();
}

/// The Scene section's tonemapper dropdown picked.
fn on_tonemapper_pick(
    event: On<ComboBoxChangeEvent>,
    fields: Query<(), With<GraphicsTonemapperField>>,
    mut commands: Commands,
) {
    if !fields.contains(event.entity) {
        return;
    }
    let Some(name) = event.value.clone() else {
        return;
    };
    commands
        .operator(EnvironmentSetOp::ID)
        .param("post.tonemapper", name)
        .settings(user_action())
        .call();
}

/// Reflect the user's viewport settings onto the panel whenever they change
/// from elsewhere: a preset picked in the viewport menu, a scripted call, a
/// fresh panel built after the settings already stood somewhere else.
fn sync_viewport_fields(
    settings: Res<ViewportSettings>,
    mut segments: Query<(Entity, &GraphicsSegment, &mut BackgroundColor, &Children)>,
    mut labels: Query<&mut TextColor>,
    toggles: Query<(Entity, &GraphicsToggle)>,
    sliders: Query<(Entity, &GraphicsSlider)>,
    mut commands: Commands,
) {
    if !settings.is_changed() {
        return;
    }
    let preset = settings.preset();
    let active = |segment: &GraphicsSegment| match *segment {
        GraphicsSegment::Preset(choice) => preset == Some(choice),
        GraphicsSegment::AntiAlias(choice) => settings.quality.anti_aliasing == choice,
        GraphicsSegment::SsaoQuality(choice) => settings.quality.ssao_quality == choice,
    };
    for (entity, segment, mut background, children) in &mut segments {
        let is_active = active(segment);
        background.0 = segmented::segment_background(is_active);
        segmented::set_segment_checked(&mut commands, entity, is_active);
        for child in children {
            if let Ok(mut color) = labels.get_mut(*child) {
                color.0 = if is_active {
                    tokens::TEXT_PRIMARY
                } else {
                    tokens::TEXT_SECONDARY
                };
            }
        }
    }
    for (entity, toggle) in &toggles {
        let on = match *toggle {
            GraphicsToggle::AmbientOcclusion => settings.quality.ambient_occlusion,
            GraphicsToggle::SunShadows => settings.quality.sun_shadows,
            GraphicsToggle::PointShadows => settings.quality.point_shadows,
            GraphicsToggle::Fog => settings.quality.fog,
            GraphicsToggle::Sharpening => settings.sharpen,
            GraphicsToggle::PostProcessing => continue,
        };
        set_marker_if_alive::<Checked>(&mut commands, entity, on);
    }
    for (entity, slider) in &sliders {
        let value = match *slider {
            GraphicsSlider::RenderScale => settings.quality.render_scale as f32,
            GraphicsSlider::SharpenStrength => settings.sharpen_strength,
            _ => continue,
        };
        commands.entity(entity).insert(SliderValue(value));
    }
}

/// Reflect the scene's environment onto the Scene section whenever it changes:
/// an undo, a redo, a scripted `environment.set`, a scene opened.
fn sync_scene_fields(
    environments: Query<&Environment, Changed<Environment>>,
    toggles: Query<(Entity, &GraphicsToggle)>,
    sliders: Query<(Entity, &GraphicsSlider)>,
    tonemappers: Query<Entity, With<GraphicsTonemapperField>>,
    mut commands: Commands,
) {
    let Some(post) = environments.iter().next().map(|env| env.post.clone()) else {
        return;
    };
    for (entity, toggle) in &toggles {
        if matches!(toggle, GraphicsToggle::PostProcessing) {
            set_marker_if_alive::<Checked>(&mut commands, entity, post.enabled);
        }
    }
    for (entity, slider) in &sliders {
        let value = match *slider {
            GraphicsSlider::Exposure => post.exposure,
            GraphicsSlider::BloomIntensity => post.bloom_intensity,
            GraphicsSlider::BloomThreshold => post.bloom_threshold,
            _ => continue,
        };
        commands.entity(entity).insert(SliderValue(value));
    }
    if let Some(index) = TONEMAPPERS
        .iter()
        .position(|choice| *choice == post.tonemapper)
    {
        for entity in &tonemappers {
            commands.entity(entity).insert(ComboBoxSelectedIndex(index));
        }
    }
}

/// Show the opt-out note while the viewport is not previewing the scene's
/// post-processing, and hide it again once it is.
fn update_opt_out_hint(
    settings: Res<ViewportSettings>,
    mut hints: Query<&mut Node, With<GraphicsOptOutHint>>,
) {
    let wanted = if settings.quality.post_processing {
        Display::None
    } else {
        Display::Flex
    };
    for mut node in &mut hints {
        if node.display != wanted {
            node.display = wanted;
        }
    }
}

/// Show the empty note while no environment exists for the Scene section to
/// write, and hide it again once one does — however it came to be.
fn update_scene_empty_hint(
    environments: Query<(), With<Environment>>,
    mut hints: Query<&mut Node, With<GraphicsSceneEmptyHint>>,
) {
    let wanted = if environments.is_empty() {
        Display::Flex
    } else {
        Display::None
    };
    for mut node in &mut hints {
        if node.display != wanted {
            node.display = wanted;
        }
    }
}

/// The name `environment.set` matches a tonemapper against: the variant's own
/// reflect name, spelt out here so a rename in the scene type fails this
/// panel's tests rather than silently missing.
fn variant_name(choice: Tonemapper) -> &'static str {
    match choice {
        Tonemapper::None => "None",
        Tonemapper::Reinhard => "Reinhard",
        Tonemapper::ReinhardLuminance => "ReinhardLuminance",
        Tonemapper::AcesFitted => "AcesFitted",
        Tonemapper::AgX => "AgX",
        Tonemapper::SomewhatBoringDisplayTransform => "SomewhatBoringDisplayTransform",
        Tonemapper::TonyMcMapface => "TonyMcMapface",
        Tonemapper::BlenderFilmic => "BlenderFilmic",
        Tonemapper::KhronosPbrNeutral => "KhronosPbrNeutral",
    }
}
