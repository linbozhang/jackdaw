//! Play-in-editor log relay: the game's own log lines stream to the editor.
//!
//! The editor's Game panel shows what the running game says, so a runtime
//! failure (a binding that names a missing field, an asset that did not
//! resolve) is visible where the game is running, not only in a console the
//! player never sees. [`maybe_windowless`](crate::pie_windowless::maybe_windowless)
//! hands [`pie_log_relayer`] to `LogPlugin::custom_layer` when the editor link
//! variable is set, so the relay layer joins the subscriber `LogPlugin`
//! already builds — one subscription, and only events that passed the game's
//! own filter reach it. [`forward_pie_logs`] (wired by `attach_pie`) drains
//! the lines into [`StateEvent::Log`]s on the reliable channel, under a
//! dedup-and-cap throttle so a game stuck in a per-frame warn cannot flood the
//! editor.

use std::collections::HashMap;
use std::sync::mpsc::{Receiver, channel};
use std::time::{Duration, Instant};

use bevy::log::tracing::{self, Event, Subscriber};
use bevy::log::tracing_subscriber::{Layer, layer::Context, registry::LookupSpan};
use bevy::prelude::*;

use jackdaw_pie_protocol::event::{StateEvent, to_bytes};
use jackdaw_pie_protocol::transport::PieTransport;

use crate::pie::PieTransportRes;

/// Log lines newer than this for the same (level, message) are duplicates the
/// throttle drops, so a warn-per-frame system still reads as one line.
const DEDUP_WINDOW: Duration = Duration::from_secs(1);

/// At most this many lines are forwarded per one-second window; the rest are
/// dropped until the window rolls. A flooded link is worth less than no link.
const MAX_PER_WINDOW: u32 = 32;

/// The relay drains at most this many queued lines per frame; anything past it
/// is dropped, because a queue this deep means the game is log-spamming and
/// the editor should see the newest lines, not fall further behind.
const MAX_DRAIN_PER_FRAME: usize = 512;

/// One game log line on its way to the editor.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PieLogLine {
    /// Lowercase level: `"info"`, `"warn"` or `"error"`.
    pub level: String,
    /// The logged message, prefixed with its target so the source is findable.
    pub message: String,
}

/// The receiving half of the relay, inserted into the app by
/// [`pie_log_relayer`] while `LogPlugin` builds. Lines written before the PIE
/// link attaches wait here and stream once the forwarder runs. The mutex is
/// the `Sync` a `Resource` asks for; the forwarder is the only reader and it
/// runs on the main thread.
#[derive(Resource)]
pub(crate) struct PieLogRelay(std::sync::Mutex<Receiver<PieLogLine>>);

/// A tracing layer that copies every info-or-louder event into the relay
/// channel. `mpsc::Sender` is `Send + Sync`, so the layer meets the
/// `Send + Sync` bound `LogPlugin::custom_layer` puts on its return value.
struct RelayLayer {
    tx: std::sync::mpsc::Sender<PieLogLine>,
}

/// Reads an event's fields: the `message` field becomes the line, and any
/// further structured fields trail it so nothing the game logged is lost.
struct FieldReader {
    message: String,
    extra: Vec<(&'static str, String)>,
}

impl tracing::field::Visit for FieldReader {
    fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
        let formatted = format!("{value:?}");
        if field.name() == "message" {
            self.message = formatted;
        } else {
            self.extra.push((field.name(), formatted));
        }
    }

    fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
        if field.name() == "message" {
            self.message = value.to_owned();
        } else {
            self.extra.push((field.name(), value.to_owned()));
        }
    }
}

impl<S> Layer<S> for RelayLayer
where
    S: Subscriber + for<'a> LookupSpan<'a>,
{
    fn on_event(&self, event: &Event<'_>, _ctx: Context<'_, S>) {
        // `Level` orders by verbosity: DEBUG and TRACE are GREATER than INFO,
        // and they stay local (a PIE link carries what a player would read,
        // not the firehose).
        let level = *event.metadata().level();
        if level > bevy::log::Level::INFO {
            return;
        }
        let mut reader = FieldReader {
            message: String::new(),
            extra: Vec::new(),
        };
        event.record(&mut reader);
        let target = event.metadata().target();
        let mut message = if target.is_empty() {
            reader.message
        } else {
            format!("{target}: {}", reader.message)
        };
        for (field, value) in reader.extra {
            message.push_str(&format!(" {field}={value}"));
        }
        let level = match level {
            bevy::log::Level::ERROR => "error",
            bevy::log::Level::WARN => "warn",
            _ => "info",
        };
        let _ = self.tx.send(PieLogLine {
            level: level.to_owned(),
            message,
        });
    }
}

/// The `LogPlugin::custom_layer` hook a PIE launch installs. Called once while
/// `LogPlugin` builds; it plants the receiving half in the app and returns the
/// sending layer, so the layer and the forwarder meet through the world.
pub(crate) fn pie_log_relayer(app: &mut App) -> Option<bevy::log::BoxedLayer> {
    let (tx, rx) = channel();
    app.insert_resource(PieLogRelay(std::sync::Mutex::new(rx)));
    Some(Box::new(RelayLayer { tx }))
}

/// The forwarder's throttle state: the open one-second window and what it has
/// already carried, plus what was sent when for dedup.
#[derive(Resource, Default)]
struct PieLogForwarder {
    window_start: Option<Instant>,
    sent_this_window: u32,
    recent: HashMap<(String, String), Instant>,
    /// Whether the open window has already carried its overflow line: one
    /// summary per window, not one per dropped line (A5 — the per-frame
    /// drain's overflow speaks, the window's overflow spoke only in silence,
    /// and the asymmetry hid exactly the lines a person needed).
    overflow_reported: bool,
}

impl PieLogForwarder {
    /// Roll the window when it has run its second.
    fn roll_if_expired(&mut self, now: Instant) {
        if self
            .window_start
            .is_some_and(|start| now.duration_since(start) >= DEDUP_WINDOW)
        {
            self.window_start = None;
            self.sent_this_window = 0;
            self.recent.clear();
            self.overflow_reported = false;
        }
    }

    /// The lines that pass the throttle, in order. A line repeating within
    /// [`DEDUP_WINDOW`] is dropped; once [`MAX_PER_WINDOW`] lines have gone
    /// through the current window everything else waits for the next one —
    /// and the first drop in a window appends one line of its own, counting
    /// what the window left behind (the drain overflow's own shape).
    fn admit(&mut self, lines: Vec<PieLogLine>, now: Instant) -> Vec<PieLogLine> {
        self.roll_if_expired(now);
        let mut passed = Vec::new();
        let mut window_dropped = 0u32;
        for line in lines {
            let key = (line.level.clone(), line.message.clone());
            if self
                .recent
                .get(&key)
                .is_some_and(|sent| now.duration_since(*sent) < DEDUP_WINDOW)
            {
                continue;
            }
            if self.sent_this_window >= MAX_PER_WINDOW {
                window_dropped += 1;
                continue;
            }
            self.window_start.get_or_insert(now);
            self.sent_this_window += 1;
            self.recent.insert(key, now);
            passed.push(line);
        }
        if window_dropped > 0 && !self.overflow_reported {
            self.overflow_reported = true;
            let plural = if window_dropped == 1 { "" } else { "s" };
            passed.push(PieLogLine {
                level: "warn".to_owned(),
                message: format!(
                    "jackdaw_runtime::pie_log: the one-second window overflowed; \
                     {window_dropped} line{plural} were dropped until it rolls"
                ),
            });
        }
        passed
    }
}

/// Drain the relay and stream the surviving lines to the editor as
/// [`StateEvent::Log`]s on the reliable channel. Quiet when there is no relay
/// (the resource is only planted under PIE) or no live transport yet.
fn forward_pie_logs(world: &mut World) {
    let Some(lines) = world
        .get_resource::<PieLogRelay>()
        .and_then(|relay| relay.0.lock().ok())
        .map(|relay| drain(&relay))
        .filter(|lines| !lines.is_empty())
    else {
        return;
    };
    if !world.contains_non_send::<PieTransportRes>() {
        return;
    }
    let passed = world
        .resource_mut::<PieLogForwarder>()
        .admit(lines, Instant::now());
    let Some(mut transport) = world.get_non_send_mut::<PieTransportRes>() else {
        return;
    };
    for line in passed {
        let Ok(bytes) = to_bytes(&StateEvent::Log {
            level: line.level,
            message: line.message,
        }) else {
            continue;
        };
        transport
            .0
            .send(jackdaw_pie_protocol::PieChannel::Reliable, &bytes);
    }
}

/// Take up to [`MAX_DRAIN_PER_FRAME`] queued lines; when more are waiting,
/// they are dropped in favor of staying current, and the drop is reported
/// rather than silent.
fn drain(receiver: &Receiver<PieLogLine>) -> Vec<PieLogLine> {
    let mut lines = Vec::new();
    while lines.len() < MAX_DRAIN_PER_FRAME {
        match receiver.try_recv() {
            Ok(line) => lines.push(line),
            Err(std::sync::mpsc::TryRecvError::Empty)
            | Err(std::sync::mpsc::TryRecvError::Disconnected) => break,
        }
    }
    if receiver.try_recv().is_ok() {
        while receiver.try_recv().is_ok() {}
        lines.truncate(MAX_DRAIN_PER_FRAME - 1);
        lines.push(PieLogLine {
            level: "warn".to_owned(),
            message: "jackdaw_runtime::pie_log: relay overflowed; older lines were dropped"
                .to_owned(),
        });
    }
    lines
}

/// Install the forwarder and its system. Called from
/// [`attach_pie`](crate::pie::attach_pie); the relay half arrives earlier (or
/// later — the system tolerates either) through [`pie_log_relayer`].
pub(crate) fn install(app: &mut App) {
    app.init_resource::<PieLogForwarder>();
    app.add_systems(bevy::app::Update, forward_pie_logs);
}

#[cfg(test)]
mod tests {
    use super::*;
    use bevy::log::tracing::subscriber::with_default;
    use bevy::log::tracing_subscriber::layer::SubscriberExt;
    use bevy::log::tracing_subscriber::registry::Registry;

    #[test]
    fn warn_and_info_stream_and_debug_does_not() {
        let (tx, rx) = channel();
        let subscriber = Registry::default().with(RelayLayer { tx });
        with_default(subscriber, || {
            bevy::log::warn!("binding failed");
            bevy::log::info!("started");
            bevy::log::debug!("per-frame chatter");
            bevy::log::trace!("even quieter");
        });
        let mut lines = Vec::new();
        while let Ok(line) = rx.try_recv() {
            lines.push((line.level, line.message));
        }
        assert_eq!(lines.len(), 2, "debug and trace stay local: {lines:?}");
        assert_eq!(lines[0].0, "warn");
        assert!(lines[0].1.ends_with("binding failed"), "{:?}", lines[0].1);
        assert!(
            lines[0].1.contains("pie_log"),
            "the target names the source"
        );
        assert_eq!(lines[1].0, "info");
    }

    #[test]
    fn structured_fields_trail_the_message() {
        let (tx, rx) = channel();
        let subscriber = Registry::default().with(RelayLayer { tx });
        with_default(subscriber, || {
            bevy::log::warn!(entity = 7, "could not apply");
        });
        let line = rx.try_recv().expect("line");
        assert_eq!(line.level, "warn");
        assert!(
            line.message.ends_with("could not apply entity=7"),
            "{}",
            line.message
        );
    }

    #[test]
    fn a_repeat_within_the_window_is_dropped_and_the_cap_holds() {
        let mut forwarder = PieLogForwarder::default();
        let now = Instant::now();
        let line = |n: u32| PieLogLine {
            level: "warn".to_owned(),
            message: format!("line {n}"),
        };
        let once = forwarder.admit(vec![line(0)], now);
        assert_eq!(once.len(), 1);
        let repeat = forwarder.admit(vec![line(0)], now + Duration::from_millis(200));
        assert!(repeat.is_empty(), "a duplicate inside the window is a drop");
        let fresh = forwarder.admit(
            (0..MAX_PER_WINDOW + 4).map(line).collect(),
            now + Duration::from_millis(400),
        );
        assert_eq!(
            fresh.len(),
            MAX_PER_WINDOW as usize,
            "the window carries at most {MAX_PER_WINDOW}, the last being its \
             overflow line: {fresh:?}"
        );
        assert!(
            fresh[fresh.len() - 1].message.contains("window overflowed"),
            "the overflow is counted: {:?}",
            fresh[fresh.len() - 1]
        );
        let rolled = forwarder.admit(vec![line(999)], now + Duration::from_secs(2));
        assert_eq!(rolled.len(), 1, "a new window admits again");
    }

    /// The window's own overflow speaks once per window, counting the lines
    /// it left behind (A5: the per-frame drain's overflow had a voice, the
    /// window's was a silence) — and a saturated window does not repeat the
    /// summary on every further call.
    #[test]
    fn a_window_overflow_counts_its_drops_once_per_window() {
        let mut forwarder = PieLogForwarder::default();
        let now = Instant::now();
        let line = |n: u32| PieLogLine {
            level: "warn".to_owned(),
            message: format!("line {n}"),
        };
        // Fill the window to its cap.
        let first = forwarder.admit((0..MAX_PER_WINDOW).map(line).collect(), now);
        assert_eq!(
            first.len() as u32,
            MAX_PER_WINDOW,
            "a fitting batch carries no overflow line"
        );
        // Overrun it: the dropped lines earn one counting line.
        let dropped = 7;
        let over = forwarder.admit(
            (100..100 + dropped).map(line).collect(),
            now + Duration::from_millis(300),
        );
        assert_eq!(
            over.len(),
            1,
            "only the summary comes through a saturated window: {over:?}"
        );
        assert!(
            over[0].message.contains(&dropped.to_string())
                && over[0].message.contains("window overflowed"),
            "the summary counts the drops: {}",
            over[0].message
        );
        // Still the same window: no second summary.
        let again = forwarder.admit(
            (200..203).map(line).collect(),
            now + Duration::from_millis(600),
        );
        assert!(again.is_empty(), "the summary spoke once: {again:?}");
        // A new window admits and reports nothing stale.
        let rolled = forwarder.admit(vec![line(999)], now + Duration::from_secs(2));
        assert_eq!(rolled.len(), 1);
        assert!(
            !rolled[0].message.contains("window overflowed"),
            "the fresh window carries only its own line: {:?}",
            rolled[0]
        );
    }

    #[test]
    fn a_flooded_relay_keeps_the_newest_and_says_so() {
        let (tx, rx) = channel();
        for n in 0..MAX_DRAIN_PER_FRAME + 10 {
            tx.send(PieLogLine {
                level: "info".to_owned(),
                message: format!("spam {n}"),
            })
            .expect("unbounded channel");
        }
        let lines = drain(&rx);
        assert_eq!(lines.len(), MAX_DRAIN_PER_FRAME);
        assert_eq!(lines[0].message, "spam 0");
        assert!(
            lines[MAX_DRAIN_PER_FRAME - 1]
                .message
                .contains("overflowed"),
            "the overflow is reported, not silent"
        );
    }
}
