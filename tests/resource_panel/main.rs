//! The Resources panel: what it lists, and what it shows of the one
//! selected. Each module below was its own test binary; merged, the editor
//! links once.

#[path = "../util/mod.rs"]
mod util;

mod edit_undo;
mod insert_remove;
mod list_and_show;
mod no_pie_leak;
mod visibility;
