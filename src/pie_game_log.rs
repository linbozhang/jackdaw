//! The focused game's recent log lines, as streamed by the PIE log relay.
//!
//! A running game's warnings and errors land here as
//! [`StateEvent::Log`]s and the Game panel shows the newest few, so a runtime
//! failure (a binding naming a missing field is the classic) is visible where
//! the game runs. The buffer keeps a bounded recent window: this is a "what
//! has the game been saying" face, not a log archive.

use std::collections::VecDeque;

use bevy::prelude::*;

/// How many recent lines the buffer keeps.
pub const PIE_GAME_LOG_CAP: usize = 100;

/// One line the focused game logged.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GameLogEntry {
    /// Lowercase level: `"info"`, `"warn"` or `"error"`.
    pub level: String,
    /// The logged message, target prefix included.
    pub message: String,
}

impl GameLogEntry {
    /// The color the line speaks in: errors in the error color, warnings in
    /// the warning color, everything else in the secondary color (the W13
    /// three-tier scheme).
    pub fn color(&self) -> Color {
        match self.level.to_ascii_uppercase().as_str() {
            "ERROR" => jackdaw_feathers::tokens::TEXT_ERROR,
            "WARN" => jackdaw_feathers::tokens::TEXT_WARNING,
            _ => jackdaw_feathers::tokens::TEXT_SECONDARY,
        }
    }
}

/// The focused game's recent log lines, newest last.
#[derive(Resource, Default, Debug)]
pub struct PieGameLog {
    entries: VecDeque<GameLogEntry>,
}

impl PieGameLog {
    /// Record one line; the oldest falls off once [`PIE_GAME_LOG_CAP`] is
    /// held.
    pub fn push(&mut self, level: impl Into<String>, message: impl Into<String>) {
        if self.entries.len() >= PIE_GAME_LOG_CAP {
            self.entries.pop_front();
        }
        self.entries.push_back(GameLogEntry {
            level: level.into(),
            message: message.into(),
        });
    }

    /// The recent lines, oldest first.
    pub fn entries(&self) -> impl Iterator<Item = &GameLogEntry> {
        self.entries.iter()
    }

    /// How many lines are held.
    pub fn len(&self) -> usize {
        self.entries.len()
    }

    /// True while nothing has been logged.
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lines_keep_order_and_the_oldest_falls_off() {
        let mut log = PieGameLog::default();
        assert!(log.is_empty());
        for n in 0..PIE_GAME_LOG_CAP + 5 {
            log.push("warn", format!("line {n}"));
        }
        assert_eq!(log.len(), PIE_GAME_LOG_CAP);
        let kept: Vec<_> = log.entries().map(|e| e.message.clone()).collect();
        assert_eq!(kept.first().map(String::as_str), Some("line 5"));
        assert_eq!(
            kept.last().map(String::as_str),
            Some(format!("line {}", PIE_GAME_LOG_CAP + 4).as_str())
        );
    }

    #[test]
    fn levels_pick_their_notice_tier() {
        let error = GameLogEntry {
            level: "error".into(),
            message: String::new(),
        };
        let warn = GameLogEntry {
            level: "WARN".into(),
            message: String::new(),
        };
        let info = GameLogEntry {
            level: "info".into(),
            message: String::new(),
        };
        assert_eq!(error.color(), jackdaw_feathers::tokens::TEXT_ERROR);
        assert_eq!(warn.color(), jackdaw_feathers::tokens::TEXT_WARNING);
        assert_eq!(info.color(), jackdaw_feathers::tokens::TEXT_SECONDARY);
    }
}
