// Reads crossterm events and coalesces a burst of resizes to the latest.
// Produces the shell's own `Event` enum. Never interprets a key as a screen
// action — it maps nothing beyond turning a crossterm event into ours.

use crossterm::event::{self, KeyEvent};
use std::time::Duration;

/// The shell's own event type — crossterm's, collapsed to what the shell
/// loop cares about.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum Event {
    Key(KeyEvent),
    Resize(u16, u16),
}

/// Blocks until at least one event is available, then drains any further
/// events already queued so a rapid resize burst coalesces to the latest
/// size instead of redrawing once per intermediate size. Non-resize events
/// found while draining are kept, in order, after the first event.
///
/// O(k) in the number of queued events (k = burst size), not the terminal
/// size.
pub fn read_coalesced() -> std::io::Result<Vec<Event>> {
    let mut out = Vec::new();

    // Block until at least one event the shell cares about arrives.
    loop {
        if let Some(ev) = from_crossterm(event::read()?) {
            out.push(ev);
            break;
        }
    }

    // Drain anything already queued without blocking, coalescing resizes.
    while event::poll(Duration::from_secs(0))? {
        if let Some(ev) = from_crossterm(event::read()?) {
            push_coalesced(&mut out, ev);
        }
    }

    Ok(out)
}

/// Mouse, focus and bracketed-paste events are not part of the shell's
/// contract (`architecture-e7.md`: `event.rs` maps nothing beyond the
/// shell's own `Event`), so they are dropped here rather than forwarded.
fn from_crossterm(ev: event::Event) -> Option<Event> {
    match ev {
        event::Event::Key(k) => Some(Event::Key(k)),
        event::Event::Resize(w, h) => Some(Event::Resize(w, h)),
        _ => None,
    }
}

fn push_coalesced(out: &mut Vec<Event>, next: Event) {
    match (out.last_mut(), &next) {
        (Some(Event::Resize(_, _)), Event::Resize(w, h)) => {
            *out.last_mut().unwrap() = Event::Resize(*w, *h);
        }
        _ => out.push(next),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyModifiers};

    fn key(c: char) -> event::Event {
        event::Event::Key(KeyEvent::new(KeyCode::Char(c), KeyModifiers::NONE))
    }

    #[test]
    fn maps_key_event() {
        assert_eq!(
            from_crossterm(key('q')),
            Some(Event::Key(KeyEvent::new(KeyCode::Char('q'), KeyModifiers::NONE)))
        );
    }

    #[test]
    fn maps_resize_event() {
        assert_eq!(
            from_crossterm(event::Event::Resize(80, 24)),
            Some(Event::Resize(80, 24))
        );
    }

    #[test]
    fn drops_events_outside_the_shells_contract() {
        assert_eq!(from_crossterm(event::Event::FocusGained), None);
    }

    /// This is the coalescing rule itself, tested at the pure-function
    /// level (`read_coalesced` needs a real input stream and is covered by
    /// the shell integration test instead): a burst of resizes folds into
    /// one, and a key in the middle of the burst is preserved.
    #[test]
    fn coalesces_a_burst_of_resizes_to_the_latest() {
        let mut out: Vec<Event> = Vec::new();
        for ev in [
            event::Event::Resize(10, 10),
            event::Event::Resize(20, 20),
            key('x'),
            event::Event::Resize(30, 30),
            event::Event::Resize(40, 40),
        ] {
            if let Some(next) = from_crossterm(ev) {
                push_coalesced(&mut out, next);
            }
        }
        assert_eq!(
            out,
            vec![
                Event::Resize(20, 20),
                Event::Key(KeyEvent::new(KeyCode::Char('x'), KeyModifiers::NONE)),
                Event::Resize(40, 40),
            ]
        );
    }
}
