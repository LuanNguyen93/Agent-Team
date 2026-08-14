// impl Screen for TimelineScreen: LoadState, session j/k navigation,
// PgUp/PgDn tree scroll, r refresh, MIN_WIDTH_COLS floor — structurally a
// copy of screen.rs's own pattern (E7-followups plan: "do NOT extract a
// shared abstraction with the existing screen"). Never `std::fs` directly,
// never `timeline.rs` directly from outside `load` — goes through
// `discover` (docs/architecture-e7.md).

use crate::analytics::discover::{discover, DiscoveryError};
use crate::analytics::rates::Rates;
use crate::analytics::screen::MIN_WIDTH_COLS;
use crate::analytics::timeline::build_timelines;
use crate::analytics::timeline_model::{AgentSpan, SessionTimeline};
use crate::shell::{Action, Screen};
use crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::text::Line;
use ratatui::widgets::{Block, Borders, Paragraph, Wrap};
use ratatui::Frame;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct LoadedTimelines {
    pub timelines: Vec<SessionTimeline>,
}

#[derive(Debug, Clone)]
pub enum LoadState {
    Empty {
        searched: PathBuf,
    },
    Failed {
        error: DiscoveryError,
        last_good: Option<LoadedTimelines>,
    },
    Loaded(LoadedTimelines),
    Refreshing {
        previous: LoadedTimelines,
    },
}

pub struct TimelineScreen {
    state: LoadState,
    selected: usize,
    tree_scroll: usize,
    project_dir: PathBuf,
    rates: Rates,
}

const TREE_PAGE: usize = 8;

impl TimelineScreen {
    pub fn new(project_dir: PathBuf, rates: Rates) -> Self {
        Self {
            state: LoadState::Empty {
                searched: project_dir.clone(),
            },
            selected: 0,
            tree_scroll: 0,
            project_dir,
            rates,
        }
    }

    fn load(&self) -> LoadState {
        match discover(&self.project_dir) {
            Ok(discovered) => {
                let raw = discovered.as_raw_files();
                let raw_meta = discovered.as_raw_meta_files();
                let (timelines, _report) = build_timelines(&raw, &raw_meta, &self.rates);
                if timelines.is_empty() {
                    LoadState::Empty {
                        searched: self.project_dir.clone(),
                    }
                } else {
                    LoadState::Loaded(LoadedTimelines { timelines })
                }
            }
            Err(error) => {
                let last_good = match &self.state {
                    LoadState::Loaded(d) => Some(d.clone()),
                    LoadState::Refreshing { previous } => Some(previous.clone()),
                    LoadState::Failed { last_good, .. } => last_good.clone(),
                    LoadState::Empty { .. } => None,
                };
                LoadState::Failed { error, last_good }
            }
        }
    }

    fn refresh(&mut self) {
        // r is a no-op (not dropped) if already refreshing, matching
        // screen.rs's own contract for the same input.
        if matches!(self.state, LoadState::Refreshing { .. }) {
            return;
        }
        let previous = match &self.state {
            LoadState::Loaded(d) => Some(d.clone()),
            LoadState::Failed { last_good, .. } => last_good.clone(),
            LoadState::Refreshing { previous } => Some(previous.clone()),
            LoadState::Empty { .. } => None,
        };
        if let Some(previous) = previous {
            self.state = LoadState::Refreshing { previous };
        }
        self.state = self.load();
        self.tree_scroll = 0;
    }

    fn move_selection(&mut self, delta: i64) {
        let len = self.current_timelines_len();
        if len == 0 {
            return;
        }
        let new = (self.selected as i64 + delta).rem_euclid(len as i64);
        self.selected = new as usize;
        self.tree_scroll = 0;
    }

    fn current_timelines_len(&self) -> usize {
        match &self.state {
            LoadState::Loaded(d) => d.timelines.len(),
            LoadState::Refreshing { previous } => previous.timelines.len(),
            LoadState::Failed {
                last_good: Some(d), ..
            } => d.timelines.len(),
            _ => 0,
        }
    }
}

impl Screen for TimelineScreen {
    fn title(&self) -> &str {
        "TIMELINE"
    }

    fn on_open(&mut self) -> Action {
        self.state = self.load();
        self.selected = 0;
        Action::Redraw
    }

    fn on_key(&mut self, key: KeyEvent) -> Action {
        match key.code {
            KeyCode::Char('r') => {
                self.refresh();
                Action::Redraw
            }
            KeyCode::Up | KeyCode::Char('k') => {
                self.move_selection(-1);
                Action::Redraw
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.move_selection(1);
                Action::Redraw
            }
            KeyCode::PageUp => {
                self.tree_scroll = self.tree_scroll.saturating_sub(TREE_PAGE);
                Action::Redraw
            }
            KeyCode::PageDown => {
                self.tree_scroll = self.tree_scroll.saturating_add(TREE_PAGE);
                Action::Redraw
            }
            _ => Action::Ignored,
        }
    }

    fn render(&mut self, frame: &mut Frame, area: Rect) {
        render_timeline(&self.state, self.selected, self.tree_scroll, area, frame);
    }
}

fn render_timeline(
    state: &LoadState,
    selected: usize,
    tree_scroll: usize,
    area: Rect,
    frame: &mut Frame,
) {
    match state {
        LoadState::Empty { searched } => render_empty(frame, area, searched),
        LoadState::Failed { error, last_good } => {
            if let Some(data) = last_good {
                render_loaded(frame, area, data, selected, tree_scroll, true);
            } else {
                render_error(frame, area, error);
            }
        }
        LoadState::Loaded(data) => render_loaded(frame, area, data, selected, tree_scroll, false),
        LoadState::Refreshing { previous } => {
            render_loaded(frame, area, previous, selected, tree_scroll, false);
        }
    }
}

fn render_empty(frame: &mut Frame, area: Rect, searched: &Path) {
    let text = format!(
        "No sessions found.\n\nLooked in: {}\n\nRun a session in this project, then press r to check again.",
        searched.display()
    );
    let block = Block::default().borders(Borders::ALL).title("TIMELINE");
    let p = Paragraph::new(text).block(block).wrap(Wrap { trim: false });
    frame.render_widget(p, area);
}

fn render_error(frame: &mut Frame, area: Rect, error: &DiscoveryError) {
    let (title_word, body) = match error {
        DiscoveryError::MissingProjectDir(path) => (
            "does not exist",
            format!(
                "Project directory does not exist\n\n{}\n\nThis path is derived from the current working directory.",
                path.display()
            ),
        ),
        DiscoveryError::PermissionDenied(path) => (
            "permission denied",
            format!(
                "Permission denied reading project directory\n\n{}\n\nThe TUI process does not have read access to this path.",
                path.display()
            ),
        ),
        DiscoveryError::Io(path, kind) => (
            "io error",
            format!(
                "Could not read project directory\n\n{}\n\n{:?}",
                path.display(),
                kind
            ),
        ),
    };
    let block = Block::default()
        .borders(Borders::ALL)
        .title(format!("TIMELINE -- ERROR ({title_word})"));
    let p = Paragraph::new(body).block(block).wrap(Wrap { trim: false });
    frame.render_widget(p, area);
}

fn render_loaded(
    frame: &mut Frame,
    area: Rect,
    data: &LoadedTimelines,
    selected: usize,
    tree_scroll: usize,
    stale: bool,
) {
    // Callers only reach render_loaded via LoadState::Loaded/Refreshing/
    // Failed{last_good: Some}, all of which the load() path only ever
    // constructs from a non-empty `timelines` — `.saturating_sub(1)` never
    // has to cover an actual empty vec, just clamp `selected` when the list
    // shrank between a load and a stale render.
    let selected = selected.min(data.timelines.len().saturating_sub(1));
    let timeline = &data.timelines[selected];
    let narrow = area.width < MIN_WIDTH_COLS;

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),                                        // header
            Constraint::Length((data.timelines.len().min(6) + 2) as u16), // session list
            Constraint::Min(3),                                           // tree
        ])
        .split(area);

    let header_title = if stale {
        format!(
            "TIMELINE -- session {} -- STALE",
            short_id(&timeline.session_id)
        )
    } else {
        format!("TIMELINE -- session {}", short_id(&timeline.session_id))
    };
    frame.render_widget(Paragraph::new(header_title), chunks[0]);

    render_session_list(frame, chunks[1], &data.timelines, selected);
    render_tree(frame, chunks[2], timeline, tree_scroll, narrow);
}

fn short_id(id: &str) -> String {
    id.chars().take(8).collect()
}

fn render_session_list(
    frame: &mut Frame,
    area: Rect,
    timelines: &[SessionTimeline],
    selected: usize,
) {
    let mut lines = Vec::new();
    for (i, t) in timelines.iter().enumerate().take(6) {
        let cursor = if i == selected { "> " } else { "  " };
        lines.push(Line::from(format!(
            "{cursor}{}  {} agents",
            short_id(&t.session_id),
            t.spans.len()
        )));
    }
    let block = Block::default()
        .borders(Borders::ALL)
        .title(format!("SESSIONS ({})", timelines.len()));
    frame.render_widget(Paragraph::new(lines).block(block), area);
}

fn format_duration(start_ms: i64, end_ms: i64) -> String {
    let secs = ((end_ms - start_ms).max(0)) / 1000;
    if secs < 60 {
        format!("{secs}s")
    } else {
        format!("{}m {}s", secs / 60, secs % 60)
    }
}

fn truncate(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        s.chars().take(max.saturating_sub(1)).collect::<String>() + "\u{2026}"
    }
}

fn render_tree(
    frame: &mut Frame,
    area: Rect,
    timeline: &SessionTimeline,
    scroll: usize,
    narrow: bool,
) {
    let desc_width: usize = if narrow { 20 } else { 40 };
    let rows_total = timeline.spans.len();
    let visible = area.height.saturating_sub(2) as usize; // border*2
    let scroll = scroll.min(rows_total.saturating_sub(visible.max(1)));
    let end = (scroll + visible.max(1)).min(rows_total);

    let lines: Vec<Line> = timeline.spans[scroll..end]
        .iter()
        .map(|s: &AgentSpan| {
            let indent = "  ".repeat(s.spawn_depth as usize);
            Line::from(format!(
                "{indent}{}  {}  {}  ${:.2}  {} calls",
                s.agent_type,
                truncate(&s.description, desc_width),
                format_duration(s.start_ms, s.end_ms),
                s.cost,
                s.calls
            ))
        })
        .collect();

    let title = if rows_total > visible {
        format!(
            "AGENT FLOW -- {rows_total} agents, {}-{} shown",
            scroll + 1,
            end
        )
    } else {
        format!("AGENT FLOW -- {rows_total} agents")
    };

    let block = Block::default().borders(Borders::ALL).title(title);
    frame.render_widget(Paragraph::new(lines).block(block), area);
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;
    use std::time::Instant;

    fn rendered_text(terminal: &Terminal<TestBackend>) -> String {
        terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect()
    }

    fn test_terminal(w: u16, h: u16) -> Terminal<TestBackend> {
        Terminal::new(TestBackend::new(w, h)).unwrap()
    }

    fn timeline(id: &str, span_count: usize) -> SessionTimeline {
        let mut spans = vec![AgentSpan {
            id: "main".to_string(),
            parent_id: None,
            agent_type: "main".to_string(),
            description: "main session".to_string(),
            spawn_depth: 0,
            start_ms: 0,
            end_ms: 5000,
            calls: 10,
            cost: 1.23,
            output: 100,
            cache_read: 10,
            cache_write: 5,
        }];
        for i in 0..span_count.saturating_sub(1) {
            spans.push(AgentSpan {
                id: format!("agent-{i}"),
                parent_id: Some("main".to_string()),
                agent_type: "implementer".to_string(),
                description: format!("did task {i}"),
                spawn_depth: 1,
                start_ms: 100,
                end_ms: 200,
                calls: 1,
                cost: 0.1,
                output: 5,
                cache_read: 1,
                cache_write: 1,
            });
        }
        SessionTimeline {
            session_id: id.to_string(),
            spans,
        }
    }

    // FR: headline renders on on_open with no keypress.
    #[test]
    fn headline_renders_on_open_with_no_keypress() {
        let mut screen = TimelineScreen {
            state: LoadState::Loaded(LoadedTimelines {
                timelines: vec![timeline("9732d0cf", 3)],
            }),
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("9732d0cf"));
        assert!(text.contains("main"));
    }

    #[test]
    fn tree_renders_indented_by_spawn_depth() {
        let mut screen = TimelineScreen {
            state: LoadState::Loaded(LoadedTimelines {
                timelines: vec![timeline("sess1", 2)],
            }),
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("implementer"));
        assert!(text.contains("did task 0"));
    }

    // FR-5: Empty and Failed(MissingProjectDir) render as different text.
    #[test]
    fn empty_and_missing_project_dir_render_different_text() {
        let mut empty_screen = TimelineScreen {
            state: LoadState::Empty {
                searched: PathBuf::from("/some/path"),
            },
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/some/path"),
            rates: Rates::load(),
        };
        let mut failed_screen = TimelineScreen {
            state: LoadState::Failed {
                error: DiscoveryError::MissingProjectDir(PathBuf::from("/some/path")),
                last_good: None,
            },
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/some/path"),
            rates: Rates::load(),
        };
        let mut t1 = test_terminal(100, 24);
        let mut t2 = test_terminal(100, 24);
        t1.draw(|f| empty_screen.render(f, f.area())).unwrap();
        t2.draw(|f| failed_screen.render(f, f.area())).unwrap();
        let text1 = rendered_text(&t1);
        let text2 = rendered_text(&t2);
        assert!(text1.contains("No sessions found"));
        assert!(text2.contains("does not exist"));
        assert_ne!(text1, text2);
    }

    // FR-4: previous frame stays visible during Refreshing.
    #[test]
    fn refreshing_state_keeps_previous_frame_visible() {
        let mut screen = TimelineScreen {
            state: LoadState::Refreshing {
                previous: LoadedTimelines {
                    timelines: vec![timeline("prevsess", 1)],
                },
            },
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("prevsess"));
    }

    // FR-4 stale banner after a failure: last_good populated shows the
    // previous tree, not a blank error screen.
    #[test]
    fn failed_refresh_with_last_good_shows_stale_tree_not_blank() {
        let mut screen = TimelineScreen {
            state: LoadState::Failed {
                error: DiscoveryError::PermissionDenied(PathBuf::from("/x")),
                last_good: Some(LoadedTimelines {
                    timelines: vec![timeline("stalesess", 1)],
                }),
            },
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("staleses"));
        assert!(text.contains("STALE"));
    }

    #[test]
    fn jk_always_moves_session_cursor_pgup_pgdn_always_scrolls_tree() {
        let timelines: Vec<SessionTimeline> =
            (0..3).map(|i| timeline(&format!("s{i}"), 1)).collect();
        let mut screen = TimelineScreen {
            state: LoadState::Loaded(LoadedTimelines { timelines }),
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        screen.on_key(KeyEvent::new(
            KeyCode::Char('j'),
            crossterm::event::KeyModifiers::NONE,
        ));
        assert_eq!(screen.selected, 1);
        screen.on_key(KeyEvent::new(
            KeyCode::PageDown,
            crossterm::event::KeyModifiers::NONE,
        ));
        assert_eq!(screen.selected, 1, "PgDn must not move the session cursor");
        assert_eq!(screen.tree_scroll, TREE_PAGE);
    }

    #[test]
    fn refresh_is_a_no_op_not_dropped_when_already_refreshing() {
        let mut screen = TimelineScreen {
            state: LoadState::Refreshing {
                previous: LoadedTimelines {
                    timelines: vec![timeline("x", 1)],
                },
            },
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/does/not/exist"),
            rates: Rates::load(),
        };
        screen.on_key(KeyEvent::new(
            KeyCode::Char('r'),
            crossterm::event::KeyModifiers::NONE,
        ));
        assert!(matches!(screen.state, LoadState::Refreshing { .. }));
    }

    // Many-span tree renders with a scroll indicator, mirroring screen.rs's
    // by-agent 30+ row edge.
    #[test]
    fn many_span_tree_renders_with_a_scroll_indicator() {
        let mut screen = TimelineScreen {
            state: LoadState::Loaded(LoadedTimelines {
                timelines: vec![timeline("bigsess1", 30)],
            }),
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("30 agents"));
        assert!(text.contains("shown"));
    }

    // 100ms render budget, mirroring screen.rs's own precedent.
    #[test]
    fn fifty_span_session_renders_within_the_per_frame_budget() {
        let mut screen = TimelineScreen {
            state: LoadState::Loaded(LoadedTimelines {
                timelines: vec![timeline("perf", 50)],
            }),
            selected: 0,
            tree_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        for _ in 0..50 {
            let start = Instant::now();
            screen.on_key(KeyEvent::new(
                KeyCode::PageDown,
                crossterm::event::KeyModifiers::NONE,
            ));
            terminal.draw(|f| screen.render(f, f.area())).unwrap();
            let elapsed = start.elapsed().as_millis();
            assert!(
                elapsed < 100,
                "on_key+render took {elapsed}ms, budget is 100ms"
            );
        }
    }
}
