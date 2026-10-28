//! Repository-wide guards and smoke checks that scan the tree or the
//! running editor rather than exercising one feature.
//!
//! Each module below was its own test binary. Merged, the editor
//! links once for the theme rather than once per file.

#[path = "../util/mod.rs"]
mod util;

/// Serializes the modules that each boot a whole editor per test
/// (`play_current_scene`, `stop_restore`): in parallel they saturate the
/// machine enough to push this binary's timing-sensitive tests (the
/// journal write budget) over their limits, so the heavy modules take
/// turns — with each other, not just within themselves.
pub(crate) static HEAVY_EDITOR_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

mod asset_lifecycle;
mod atomic_writes;
mod batch_undo;
mod config_injection;
mod dirty_matrix;
mod editor_remote;
mod feathers_composition;
mod game_input;
mod game_ui;
mod keyframe_undo;
mod numeric_transform_undo;
mod physics_triggers;
mod play_current_scene;
mod player_controller;
mod record_counts;
mod recovery;
mod reference_audit;
mod reference_rewrite;
mod remote_debug_smoke;
mod scaffolded_component_flow;
mod session_journal;
mod stop_restore;
mod undo_history;
mod user_config;
mod widget_purity;
