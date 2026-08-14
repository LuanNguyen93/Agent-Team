// The whole contract between the shell and every screen. See
// docs/architecture-e7.md "The seam: shell <-> screen". This module must
// never name a concrete screen (analytics, tree view, ...) — that is what
// lets those screens register without the shell changing.

/// A screen-level failure the shell cannot render around. Handed off to
/// `error_screen.rs`; the shell keeps running (quit and switch still work).
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct ShellError {
    pub message: String,
}

/// What a screen's `on_key`/`on_open` tells the shell to do next.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum Action {
    /// Nothing changed; the shell need not redraw.
    Ignored,
    /// The screen's state changed; redraw on the next tick.
    Redraw,
    /// The screen has hit a condition it cannot render around. The shell
    /// takes over with error_screen.rs.
    Fatal(ShellError),
}

/// The whole contract between the shell and every screen.
pub trait Screen {
    /// Shown in the shell's header and in the switcher. Stable for the
    /// process lifetime.
    fn title(&self) -> &str;

    /// Draw into the area the shell gives it. Must not block and must not
    /// perform I/O — anything slow happens in `on_key`/`on_open`.
    fn render(&mut self, frame: &mut ratatui::Frame, area: ratatui::layout::Rect);

    /// Every key the shell did not consume globally.
    fn on_key(&mut self, key: crossterm::event::KeyEvent) -> Action;

    /// Called once when the screen becomes active, including the first
    /// time. Where a screen does its initial load.
    fn on_open(&mut self) -> Action {
        Action::Redraw
    }
}

pub mod error_screen;
pub mod event;
pub mod registry;
pub mod terminal;

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::backend::Backend;
use ratatui::layout::Rect;
use ratatui::widgets::Paragraph;
use ratatui::{Frame, Terminal};

/// Whether the event loop should keep running after handling one event.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum LoopFlow {
    Continue,
    Quit,
}

/// The event loop's state and global-key handling, factored out of the
/// blocking crossterm read (`terminal.rs`, `event.rs`) so it is testable
/// with a plain `event::Event` and a `TestBackend` terminal — see
/// `tests/shell.rs`. This is the only place `q`/Ctrl+C (quit) and
/// `Tab`/`Shift+Tab` (switch) are interpreted; everything else reaches the
/// active screen's `on_key`.
pub struct Shell {
    registry: registry::Registry,
    error: Option<ShellError>,
}

impl Shell {
    pub fn new(registry: registry::Registry) -> Self {
        Self {
            registry,
            error: None,
        }
    }

    /// Draws the current frame: the shell's own error screen if one is
    /// showing, the active screen, or the "nothing to display" state when
    /// the registry is empty. The shell clears the frame between screens
    /// (ratatui's `draw` does this for every call), so nothing bleeds
    /// through a switch.
    pub fn draw<B: Backend>(&mut self, terminal: &mut Terminal<B>) -> Result<(), B::Error> {
        let error = self.error.clone();
        let active = self.registry.active();
        terminal.draw(move |frame| {
            let area = frame.area();
            match (&error, active) {
                (Some(err), _) => error_screen::render(frame, area, err),
                (None, Some(screen)) => screen.render(frame, area),
                (None, None) => render_nothing_to_display(frame, area),
            }
        })?;
        Ok(())
    }

    /// Handles one shell event. Global keys are consumed here and never
    /// forwarded to a screen; a resize is a redraw signal only, since
    /// `event.rs` already coalesced the burst.
    pub fn handle(&mut self, ev: event::Event) -> LoopFlow {
        match ev {
            event::Event::Resize(_, _) => LoopFlow::Continue,
            event::Event::Key(key) => self.handle_key(key),
        }
    }

    fn handle_key(&mut self, key: KeyEvent) -> LoopFlow {
        if is_quit(&key) {
            return LoopFlow::Quit;
        }
        // Global keys still work while the error screen is showing; nothing
        // else does — the error screen owns no interaction of its own.
        if self.error.is_some() {
            return LoopFlow::Continue;
        }
        if is_next_screen(&key) {
            self.registry.next();
            return LoopFlow::Continue;
        }
        if is_prev_screen(&key) {
            self.registry.prev();
            return LoopFlow::Continue;
        }
        if let Some(screen) = self.registry.active() {
            if let Action::Fatal(err) = screen.on_key(key) {
                self.error = Some(err);
            }
        }
        LoopFlow::Continue
    }
}

fn is_quit(key: &KeyEvent) -> bool {
    matches!(key.code, KeyCode::Char('q'))
        || (key.code == KeyCode::Char('c') && key.modifiers.contains(KeyModifiers::CONTROL))
}

fn is_next_screen(key: &KeyEvent) -> bool {
    key.code == KeyCode::Tab && !key.modifiers.contains(KeyModifiers::SHIFT)
}

fn is_prev_screen(key: &KeyEvent) -> bool {
    key.code == KeyCode::BackTab
        || (key.code == KeyCode::Tab && key.modifiers.contains(KeyModifiers::SHIFT))
}

fn render_nothing_to_display(frame: &mut Frame, area: Rect) {
    frame.render_widget(Paragraph::new("nothing to display. q quits."), area);
}

#[cfg(test)]
mod tests {
    use super::*;

    struct FakeScreen {
        opened: bool,
    }

    impl Screen for FakeScreen {
        fn title(&self) -> &str {
            "fake"
        }

        fn render(&mut self, _frame: &mut ratatui::Frame, _area: ratatui::layout::Rect) {}

        fn on_key(&mut self, _key: crossterm::event::KeyEvent) -> Action {
            Action::Ignored
        }

        fn on_open(&mut self) -> Action {
            self.opened = true;
            Action::Redraw
        }
    }

    #[test]
    fn action_variants_compile_and_match() {
        let mut screen = FakeScreen { opened: false };
        assert_eq!(screen.on_open(), Action::Redraw);
        assert!(screen.opened);

        let key = crossterm::event::KeyEvent::new(
            crossterm::event::KeyCode::Char('x'),
            crossterm::event::KeyModifiers::NONE,
        );
        match screen.on_key(key) {
            Action::Ignored => {}
            Action::Redraw => panic!("expected Ignored"),
            Action::Fatal(_) => panic!("expected Ignored"),
        }
    }
}
