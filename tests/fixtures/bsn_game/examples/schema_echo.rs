//! The run-target e2e fixture: a cargo `[[example]]` the editor builds
//! when a `[[run]]` entry carries
//! `target = { example = "schema_echo" }`.
//!
//! Deliberately not a bevy `App`: an example target need not run the
//! game's plugins, and a plain main that prints a marker and exits keeps
//! the heavy smoke's run step instant. The schema extractor runs this
//! binary too (with its flag); it ignores the flag, exits 0, and the
//! extraction fails fast and harmlessly, exactly as it does for any
//! target without `JackdawPlugin`.

fn main() {
    println!("SCHEMA_ECHO_MARKER example target runs");
}
