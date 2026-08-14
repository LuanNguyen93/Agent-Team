// Integration coverage for the shell's event loop: global keys, screen
// switching, the zero-screens state, and Action::Fatal handing off to the
// shell's own error screen. Runs the loop against `ratatui::backend::
// TestBackend`, no real terminal needed.

use agent_team_tui::analytics::rates::Rates;
use agent_team_tui::analytics::screen::AnalyticsScreen;
use agent_team_tui::shell::registry::Registry;
use agent_team_tui::shell::{Action, Shell};
use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::backend::TestBackend;
use ratatui::Terminal;

struct FatalOnFirstKey {
    fired: bool,
}

impl agent_team_tui::shell::Screen for FatalOnFirstKey {
    fn title(&self) -> &str {
        "fatal"
    }

    fn render(&mut self, frame: &mut ratatui::Frame, area: ratatui::layout::Rect) {
        frame.render_widget(ratatui::widgets::Paragraph::new("ok"), area);
    }

    fn on_key(&mut self, _key: KeyEvent) -> Action {
        if self.fired {
            Action::Ignored
        } else {
            self.fired = true;
            Action::Fatal(agent_team_tui::shell::ShellError {
                message: "screen exploded".to_string(),
            })
        }
    }
}

fn key(c: char) -> KeyEvent {
    KeyEvent::new(KeyCode::Char(c), KeyModifiers::NONE)
}

fn ctrl_c() -> KeyEvent {
    KeyEvent::new(KeyCode::Char('c'), KeyModifiers::CONTROL)
}

fn rendered_text(terminal: &Terminal<TestBackend>) -> String {
    terminal
        .backend()
        .buffer()
        .content()
        .iter()
        .map(|cell| cell.symbol())
        .collect()
}

#[test]
fn fatal_action_shows_the_error_screen_and_quit_still_works() {
    let screen: Box<dyn agent_team_tui::shell::Screen> =
        Box::new(FatalOnFirstKey { fired: false });
    let mut shell = Shell::new(Registry::new(vec![screen]));
    let mut terminal = Terminal::new(TestBackend::new(40, 6)).unwrap();

    // Any key reaches the screen, which returns Fatal.
    shell.handle(agent_team_tui::shell::event::Event::Key(key('x')));
    shell.draw(&mut terminal).unwrap();
    assert!(rendered_text(&terminal).contains("screen exploded"));

    // q still quits even while the error screen is showing.
    let flow = shell.handle(agent_team_tui::shell::event::Event::Key(key('q')));
    assert!(matches!(flow, agent_team_tui::shell::LoopFlow::Quit));
}

#[test]
fn tab_switches_screens_and_shift_tab_switches_back() {
    struct Named(&'static str);
    impl agent_team_tui::shell::Screen for Named {
        fn title(&self) -> &str {
            self.0
        }
        fn render(&mut self, frame: &mut ratatui::Frame, area: ratatui::layout::Rect) {
            frame.render_widget(ratatui::widgets::Paragraph::new(self.0), area);
        }
        fn on_key(&mut self, _key: KeyEvent) -> Action {
            Action::Ignored
        }
    }

    let screens: Vec<Box<dyn agent_team_tui::shell::Screen>> =
        vec![Box::new(Named("one")), Box::new(Named("two"))];
    let mut shell = Shell::new(Registry::new(screens));
    let mut terminal = Terminal::new(TestBackend::new(40, 6)).unwrap();

    shell.draw(&mut terminal).unwrap();
    assert!(rendered_text(&terminal).contains("one"));

    shell.handle(agent_team_tui::shell::event::Event::Key(KeyEvent::new(
        KeyCode::Tab,
        KeyModifiers::NONE,
    )));
    shell.draw(&mut terminal).unwrap();
    let after_tab = rendered_text(&terminal);
    assert!(after_tab.contains("two"));
    assert!(!after_tab.contains("one"), "previous screen bled into the new frame");

    shell.handle(agent_team_tui::shell::event::Event::Key(KeyEvent::new(
        KeyCode::BackTab,
        KeyModifiers::SHIFT,
    )));
    shell.draw(&mut terminal).unwrap();
    assert!(rendered_text(&terminal).contains("one"));
}

#[test]
fn zero_screens_renders_nothing_to_display_and_quit_still_works() {
    let mut shell = Shell::new(Registry::new(Vec::new()));
    let mut terminal = Terminal::new(TestBackend::new(40, 6)).unwrap();

    shell.draw(&mut terminal).unwrap();
    assert!(rendered_text(&terminal).to_lowercase().contains("nothing"));

    let flow = shell.handle(agent_team_tui::shell::event::Event::Key(ctrl_c()));
    assert!(matches!(flow, agent_team_tui::shell::LoopFlow::Quit));
}

// Step 15: the shell running against a real fixture project dir, end to
// end through the same Screen trait the shell only ever sees — a mock
// screen cannot exercise on_open's real discover()+parse() path.
#[test]
fn analytics_screen_loads_the_real_fixture_and_renders_through_the_shell() {
    let fixture_project = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../tests/fixtures/transcripts/project");

    let mut screen: Box<dyn agent_team_tui::shell::Screen> =
        Box::new(AnalyticsScreen::new(fixture_project, Rates::load()));
    screen.on_open();

    let mut shell = Shell::new(Registry::new(vec![screen]));
    let mut terminal = Terminal::new(TestBackend::new(120, 30)).unwrap();
    shell.draw(&mut terminal).unwrap();

    let text = rendered_text(&terminal);
    // aaaaaaaa-1111 is the most expensive session in the fixture — the
    // screen's settled session scope (docs/plan-e7.md) opens on it.
    assert!(text.contains("aaaaaaaa"), "rendered: {text}");

    // q still quits with a real screen loaded, not just the fake one above.
    let flow = shell.handle(agent_team_tui::shell::event::Event::Key(key('q')));
    assert!(matches!(flow, agent_team_tui::shell::LoopFlow::Quit));
}
