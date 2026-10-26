//! Repository-wide guards and smoke checks that scan the tree or the
//! running editor rather than exercising one feature.
//!
//! Each module below was its own test binary. Merged, the editor
//! links once for the theme rather than once per file.

#[path = "../util/mod.rs"]
mod util;

mod atomic_writes;
mod batch_undo;
mod dirty_matrix;
mod editor_remote;
mod feathers_composition;
mod keyframe_undo;
mod numeric_transform_undo;
mod play_current_scene;

mod record_counts;
mod recovery;
mod reference_audit;
mod reference_rewrite;
mod remote_debug_smoke;
mod scaffolded_component_flow;
mod session_journal;
mod undo_history;
mod user_config;
mod widget_purity;
