// Integration coverage for the shell's event loop: global keys, screen
// switching, the zero-screens state, and Action::Fatal handing off to the
// shell's own error screen. Runs the loop against `ratatui::backend::
// TestBackend`, no real terminal needed.

use agent_team_tui::analytics::rates::Rates;
use agent_team_tui::analytics::screen::AnalyticsScreen;
use agent_team_tui::analytics::timeline_screen::TimelineScreen;
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
    let screen: Box<dyn agent_team_tui::shell::Screen> = Box::new(FatalOnFirstKey { fired: false });
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
    assert!(
        !after_tab.contains("one"),
        "previous screen bled into the new frame"
    );

    shell.handle(agent_team_tui::shell::event::Event::Key(KeyEvent::new(
        KeyCode::BackTab,
        KeyModifiers::SHIFT,
    )));
    shell.draw(&mut terminal).unwrap();
    assert!(rendered_text(&terminal).contains("one"));
}

// E7-followups: the timeline screen joins analytics as the shell's second
// registered screen (main.rs). Tab must cycle through both real screens'
// titles, not just the synthetic ones used elsewhere in this file.
#[test]
fn tab_cycles_titles_across_the_two_real_registered_screens() {
    let analytics: Box<dyn agent_team_tui::shell::Screen> = Box::new(AnalyticsScreen::new(
        std::path::PathBuf::from("/does/not/exist"),
        Rates::load(),
    ));
    let timeline: Box<dyn agent_team_tui::shell::Screen> = Box::new(TimelineScreen::new(
        std::path::PathBuf::from("/does/not/exist"),
        Rates::load(),
    ));
    let mut registry = Registry::new(vec![analytics, timeline]);
    assert_eq!(registry.active().unwrap().title(), "ANALYTICS");
    registry.next();
    assert_eq!(registry.active().unwrap().title(), "TIMELINE");
    registry.next();
    assert_eq!(registry.active().unwrap().title(), "ANALYTICS");
}

#[test]
fn shell_new_opens_the_initial_screen() {
    struct Recording {
        opens: std::rc::Rc<std::cell::RefCell<Vec<&'static str>>>,
        name: &'static str,
    }
    impl agent_team_tui::shell::Screen for Recording {
        fn title(&self) -> &str {
            self.name
        }
        fn render(&mut self, _frame: &mut ratatui::Frame, _area: ratatui::layout::Rect) {}
        fn on_key(&mut self, _key: KeyEvent) -> Action {
            Action::Ignored
        }
        fn on_open(&mut self) -> Action {
            self.opens.borrow_mut().push(self.name);
            Action::Redraw
        }
    }

    let opens = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
    let screen: Box<dyn agent_team_tui::shell::Screen> = Box::new(Recording {
        opens: opens.clone(),
        name: "only",
    });
    let _shell = Shell::new(Registry::new(vec![screen]));

    assert_eq!(*opens.borrow(), vec!["only"]);
}

#[test]
fn tab_switch_calls_on_open_on_the_newly_active_screen_every_time() {
    struct Recording {
        opens: std::rc::Rc<std::cell::RefCell<Vec<&'static str>>>,
        name: &'static str,
    }
    impl agent_team_tui::shell::Screen for Recording {
        fn title(&self) -> &str {
            self.name
        }
        fn render(&mut self, frame: &mut ratatui::Frame, area: ratatui::layout::Rect) {
            frame.render_widget(ratatui::widgets::Paragraph::new(self.name), area);
        }
        fn on_key(&mut self, _key: KeyEvent) -> Action {
            Action::Ignored
        }
        fn on_open(&mut self) -> Action {
            self.opens.borrow_mut().push(self.name);
            Action::Redraw
        }
    }

    let opens = std::rc::Rc::new(std::cell::RefCell::new(Vec::new()));
    let screens: Vec<Box<dyn agent_team_tui::shell::Screen>> = vec![
        Box::new(Recording {
            opens: opens.clone(),
            name: "one",
        }),
        Box::new(Recording {
            opens: opens.clone(),
            name: "two",
        }),
    ];
    let mut shell = Shell::new(Registry::new(screens));
    // The initial screen opened once, from Shell::new.
    assert_eq!(*opens.borrow(), vec!["one"]);

    shell.handle(agent_team_tui::shell::event::Event::Key(KeyEvent::new(
        KeyCode::Tab,
        KeyModifiers::NONE,
    )));
    assert_eq!(*opens.borrow(), vec!["one", "two"]);

    shell.handle(agent_team_tui::shell::event::Event::Key(KeyEvent::new(
        KeyCode::BackTab,
        KeyModifiers::SHIFT,
    )));
    // Re-entry re-opens: switching back to "one" fires on_open again.
    assert_eq!(*opens.borrow(), vec!["one", "two", "one"]);
}

#[test]
fn on_open_returning_fatal_shows_the_error_screen() {
    struct FatalOnOpen;
    impl agent_team_tui::shell::Screen for FatalOnOpen {
        fn title(&self) -> &str {
            "fatal-open"
        }
        fn render(&mut self, frame: &mut ratatui::Frame, area: ratatui::layout::Rect) {
            frame.render_widget(ratatui::widgets::Paragraph::new("ok"), area);
        }
        fn on_key(&mut self, _key: KeyEvent) -> Action {
            Action::Ignored
        }
        fn on_open(&mut self) -> Action {
            Action::Fatal(agent_team_tui::shell::ShellError {
                message: "load failed".to_string(),
            })
        }
    }

    let screen: Box<dyn agent_team_tui::shell::Screen> = Box::new(FatalOnOpen);
    let mut shell = Shell::new(Registry::new(vec![screen]));
    let mut terminal = Terminal::new(TestBackend::new(40, 6)).unwrap();

    shell.draw(&mut terminal).unwrap();
    assert!(rendered_text(&terminal).contains("load failed"));
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

    let screen: Box<dyn agent_team_tui::shell::Screen> =
        Box::new(AnalyticsScreen::new(fixture_project, Rates::load()));

    // Shell::new opens the initial active screen itself.
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
