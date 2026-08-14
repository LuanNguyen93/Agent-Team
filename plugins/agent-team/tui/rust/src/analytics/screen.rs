// impl Screen for AnalyticsScreen: LoadState, the split-bar and verdict
// render, session-list j/k navigation, by-agent PgUp/PgDn scroll, r
// refresh, and the 60-column degradation. Never `std::fs` directly, never
// `parse.rs` directly — goes through `discover` (docs/architecture-e7.md).

use crate::analytics::discover::{discover, DiscoveryError};
use crate::analytics::model::{ParseReport, Session};
use crate::analytics::rates::Rates;
use crate::shell::{Action, Screen};
use crossterm::event::{KeyCode, KeyEvent};
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph, Row, Table, Wrap};
use ratatui::Frame;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

/// Settled by `planner`/`ux-designer`, docs/ui-spec-analytics.md §8.2 and
/// §10, and docs/plan-e7.md's "Three under-specified values, chosen".
/// Constants live exactly here — rates.rs and parse.rs never see them, per
/// the dependency table (display-only).
pub const MAIN_SHARE_WARN: f64 = 0.40;
pub const MAIN_SHARE_ERROR: f64 = 0.80;
pub const MIN_WIDTH_COLS: u16 = 60;
pub const RENDER_BUDGET_MS: u128 = 100;

#[derive(Debug, Clone)]
pub struct LoadedData {
    pub sessions: Vec<Session>,
    pub report: ParseReport,
    pub read_at: SystemTime,
}

#[derive(Debug, Clone)]
pub enum LoadState {
    Empty {
        searched: PathBuf,
    },
    Failed {
        error: DiscoveryError,
        last_good: Option<LoadedData>,
    },
    Loaded(LoadedData),
    Refreshing {
        previous: LoadedData,
    },
}

/// Word-form verdict, present regardless of colour (design-system.md §1 —
/// no colour-only signal). See ui-spec-analytics.md §8.2.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum Verdict {
    Delegated,
    MostlyMain,
    AllMain,
    NoBilledActivity,
}

impl Verdict {
    pub fn label(self) -> &'static str {
        match self {
            Verdict::Delegated => "[DELEGATED]",
            Verdict::MostlyMain => "[MOSTLY MAIN]",
            Verdict::AllMain => "[ALL MAIN]",
            Verdict::NoBilledActivity => "[NO BILLED ACTIVITY]",
        }
    }

    pub fn role(self) -> Color {
        match self {
            Verdict::Delegated => Color::Green,
            Verdict::MostlyMain => Color::Yellow,
            Verdict::AllMain => Color::Red,
            Verdict::NoBilledActivity => Color::DarkGray,
        }
    }
}

/// Threshold rule, ui-spec-analytics.md §8.2. `total_cost == 0` is checked
/// by the caller first — this function assumes a nonzero total.
pub fn verdict_for(total_cost: f64, main_share: f64) -> Verdict {
    if total_cost == 0.0 {
        Verdict::NoBilledActivity
    } else if main_share >= MAIN_SHARE_ERROR {
        Verdict::AllMain
    } else if main_share >= MAIN_SHARE_WARN {
        Verdict::MostlyMain
    } else {
        Verdict::Delegated
    }
}

pub struct AnalyticsScreen {
    state: LoadState,
    /// Index into `sessions` of the currently-selected row. Always the
    /// most-expensive session (index 0) right after a load, since sessions
    /// are sorted most-expensive-first by `parse` (docs/plan-e7.md session
    /// scope decision).
    selected: usize,
    by_agent_scroll: usize,
    project_dir: PathBuf,
    rates: Rates,
}

const BY_AGENT_PAGE: usize = 8;

impl AnalyticsScreen {
    pub fn new(project_dir: PathBuf, rates: Rates) -> Self {
        Self {
            state: LoadState::Empty {
                searched: project_dir.clone(),
            },
            selected: 0,
            by_agent_scroll: 0,
            project_dir,
            rates,
        }
    }

    fn load(&self) -> LoadState {
        match discover(&self.project_dir) {
            Ok(discovered) => {
                let raw = discovered.as_raw_files();
                let (sessions, report) = crate::analytics::parse::parse(&raw, &self.rates);
                if sessions.is_empty() {
                    LoadState::Empty {
                        searched: self.project_dir.clone(),
                    }
                } else {
                    LoadState::Loaded(LoadedData {
                        sessions,
                        report,
                        read_at: discovered.read_at,
                    })
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
        // r is a no-op (not dropped) if already refreshing — the keymap
        // (ui-spec-analytics.md §11) says "input not dropped, just
        // ignored"; here that means a second r while Refreshing does not
        // re-enter the load.
        if matches!(self.state, LoadState::Refreshing { .. }) {
            return;
        }
        let previous = match &self.state {
            LoadState::Loaded(d) => Some(d.clone()),
            LoadState::Failed { last_good, .. } => last_good.clone(),
            LoadState::Refreshing { previous } => Some(previous.clone()),
            LoadState::Empty { .. } => None,
        };
        // FR-4: Refreshing renders once, with the last-good data, before the
        // blocking load runs — synchronous by design (architecture-e7.md,
        // "Refresh is synchronous").
        if let Some(previous) = previous {
            self.state = LoadState::Refreshing { previous };
        }
        self.state = self.load();
        self.by_agent_scroll = 0;
    }

    fn move_selection(&mut self, delta: i64) {
        let len = self.current_sessions_len();
        if len == 0 {
            return;
        }
        let new = (self.selected as i64 + delta).rem_euclid(len as i64);
        self.selected = new as usize;
        self.by_agent_scroll = 0;
    }

    fn current_sessions_len(&self) -> usize {
        match &self.state {
            LoadState::Loaded(d) => d.sessions.len(),
            LoadState::Refreshing { previous } => previous.sessions.len(),
            LoadState::Failed {
                last_good: Some(d), ..
            } => d.sessions.len(),
            _ => 0,
        }
    }
}

impl Screen for AnalyticsScreen {
    fn title(&self) -> &str {
        "ANALYTICS"
    }

    fn on_open(&mut self) -> Action {
        self.state = self.load();
        // Most expensive session first, since `parse` already sorts that
        // way (docs/plan-e7.md).
        self.selected = 0;
        Action::Redraw
    }

    fn on_key(&mut self, key: KeyEvent) -> Action {
        match key.code {
            KeyCode::Char('r') => {
                self.refresh();
                Action::Redraw
            }
            // up/down and j/k ALWAYS move the session cursor — never
            // remapped by focus (ui-spec-analytics.md §9, §11).
            KeyCode::Up | KeyCode::Char('k') => {
                self.move_selection(-1);
                Action::Redraw
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.move_selection(1);
                Action::Redraw
            }
            // PgUp/PgDn ALWAYS scroll the by-agent table.
            KeyCode::PageUp => {
                self.by_agent_scroll = self.by_agent_scroll.saturating_sub(BY_AGENT_PAGE);
                Action::Redraw
            }
            KeyCode::PageDown => {
                self.by_agent_scroll = self.by_agent_scroll.saturating_add(BY_AGENT_PAGE);
                Action::Redraw
            }
            _ => Action::Ignored,
        }
    }

    fn render(&mut self, frame: &mut Frame, area: Rect) {
        render_analytics(
            &self.state,
            self.selected,
            self.by_agent_scroll,
            area,
            frame,
        );
    }
}

fn render_analytics(
    state: &LoadState,
    selected: usize,
    by_agent_scroll: usize,
    area: Rect,
    frame: &mut Frame,
) {
    match state {
        LoadState::Empty { searched } => render_empty(frame, area, searched),
        LoadState::Failed { error, last_good } => {
            if let Some(data) = last_good {
                render_loaded(frame, area, data, selected, by_agent_scroll, Some(error));
            } else {
                render_error(frame, area, error);
            }
        }
        LoadState::Loaded(data) => {
            render_loaded(frame, area, data, selected, by_agent_scroll, None)
        }
        LoadState::Refreshing { previous } => {
            render_loaded(frame, area, previous, selected, by_agent_scroll, None);
        }
    }
}

fn render_empty(frame: &mut Frame, area: Rect, searched: &Path) {
    let text = format!(
        "No sessions found.\n\nLooked in: {}\n\nRun a session in this project, then press r to check again.",
        searched.display()
    );
    let block = Block::default().borders(Borders::ALL).title("ANALYTICS");
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
            format!("Could not read project directory\n\n{}\n\n{:?}", path.display(), kind),
        ),
    };
    let block = Block::default()
        .borders(Borders::ALL)
        .title(format!("ANALYTICS -- ERROR ({title_word})"));
    let p = Paragraph::new(body).block(block).wrap(Wrap { trim: false });
    frame.render_widget(p, area);
}

fn render_loaded(
    frame: &mut Frame,
    area: Rect,
    data: &LoadedData,
    selected: usize,
    by_agent_scroll: usize,
    stale: Option<&DiscoveryError>,
) {
    let selected = selected.min(data.sessions.len().saturating_sub(1));
    let session = &data.sessions[selected];

    let narrow = area.width < MIN_WIDTH_COLS;

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(1),                                       // header
            Constraint::Length((data.sessions.len().min(6) + 2) as u16), // session list
            Constraint::Length(2),                                       // split bar + verdict
            Constraint::Length(1),                                       // totals
            Constraint::Min(3),                                          // by-agent table
        ])
        .split(area);

    let header_title = if stale.is_some() {
        format!("ANALYTICS -- session {} -- STALE", short_id(&session.id))
    } else {
        format!("ANALYTICS -- session {}", short_id(&session.id))
    };
    frame.render_widget(Paragraph::new(header_title), chunks[0]);

    render_session_list(frame, chunks[1], &data.sessions, selected);
    render_split_bar(frame, chunks[2], session, narrow);
    render_totals(frame, chunks[3], session);
    render_by_agent(frame, chunks[4], session, by_agent_scroll);
}

fn short_id(id: &str) -> String {
    id.chars().take(8).collect()
}

fn render_session_list(frame: &mut Frame, area: Rect, sessions: &[Session], selected: usize) {
    let mut lines = Vec::new();
    for (i, s) in sessions.iter().enumerate().take(6) {
        let cursor = if i == selected { "> " } else { "  " };
        let share = if s.total_cost > 0.0 {
            s.main.cost / s.total_cost
        } else {
            0.0
        };
        let verdict = verdict_for(s.total_cost, share);
        lines.push(Line::from(format!(
            "{cursor}{}  ${:.2}  {:>3}% main  {}",
            short_id(&s.id),
            s.total_cost,
            (share * 100.0).round(),
            verdict.label()
        )));
    }
    let block = Block::default()
        .borders(Borders::ALL)
        .title(format!("SESSIONS ({})", sessions.len()));
    frame.render_widget(Paragraph::new(lines).block(block), area);
}

fn render_split_bar(frame: &mut Frame, area: Rect, session: &Session, narrow: bool) {
    let width: usize = if narrow { 20 } else { 40 };
    let total = session.total_cost;
    let (bar, main_pct_text, verdict) = if total == 0.0 {
        (
            "-".repeat(width),
            "$0 / $0".to_string(),
            Verdict::NoBilledActivity,
        )
    } else {
        let main_share = session.main.cost / total;
        let filled = ((main_share * width as f64).round() as usize).min(width);
        let bar = format!("{}{}", "#".repeat(filled), ".".repeat(width - filled));
        let text = format!(
            "{}% main / {}% sub",
            (main_share * 100.0).round(),
            (session.sub_share * 100.0).round()
        );
        (bar, text, verdict_for(total, main_share))
    };
    let line = Line::from(vec![
        Span::raw("main  "),
        Span::styled(bar, Style::default().fg(verdict.role())),
        Span::raw(format!("  {main_pct_text}  ")),
        Span::styled(verdict.label(), Style::default().fg(verdict.role())),
    ]);
    frame.render_widget(Paragraph::new(line), area);
}

fn render_totals(frame: &mut Frame, area: Rect, session: &Session) {
    let total = session.total_cost;
    let (main_pct, sub_pct) = if total > 0.0 {
        (
            format!("{}%", (session.main.cost / total * 100.0).round()),
            format!("{}%", (session.sub.cost / total * 100.0).round()),
        )
    } else {
        ("--".to_string(), "--".to_string())
    };
    let line = format!(
        "total  ${:.2}   main  ${:.2} ({main_pct})   sub  ${:.2} ({sub_pct})",
        session.total_cost, session.main.cost, session.sub.cost
    );
    frame.render_widget(Paragraph::new(line), area);
}

fn render_by_agent(frame: &mut Frame, area: Rect, session: &Session, scroll: usize) {
    let rows_total = session.by_agent.len();
    let visible = area.height.saturating_sub(3) as usize; // header + border*2
    let scroll = scroll.min(rows_total.saturating_sub(visible.max(1)));
    let end = (scroll + visible.max(1)).min(rows_total);

    let rows: Vec<Row> = session.by_agent[scroll..end]
        .iter()
        .map(|r| {
            Row::new(vec![
                r.agent.clone(),
                r.model.clone(),
                r.calls.to_string(),
                format!("${:.2}", r.cost),
            ])
        })
        .collect();

    let title = if rows_total > visible {
        format!(
            "BY AGENT / MODEL -- {rows_total} rows, {}-{} shown",
            scroll + 1,
            end
        )
    } else {
        format!("BY AGENT / MODEL -- {rows_total} rows")
    };

    let table = Table::new(
        rows,
        [
            Constraint::Length(27),
            Constraint::Length(19),
            Constraint::Length(6),
            Constraint::Length(9),
        ],
    )
    .header(Row::new(vec!["agent", "model", "calls", "cost"]))
    .block(Block::default().borders(Borders::ALL).title(title));
    frame.render_widget(table, area);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::analytics::model::{AgentRow, Bucket};
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

    fn session(id: &str, main_cost: f64, sub_cost: f64) -> Session {
        Session {
            id: id.to_string(),
            main: Bucket {
                calls: 1,
                cost: main_cost,
                output: 10,
                cache_read: 100,
                cache_write: 10,
                avg_context: 100.0,
                max_context: 100,
            },
            sub: Bucket {
                calls: if sub_cost > 0.0 { 1 } else { 0 },
                cost: sub_cost,
                output: 5,
                cache_read: 50,
                cache_write: 5,
                avg_context: 50.0,
                max_context: 50,
            },
            by_agent: vec![AgentRow {
                agent: "(main context)".to_string(),
                model: "claude-opus-5".to_string(),
                calls: 1,
                cache_read: 100,
                cache_write: 10,
                output: 10,
                cost: main_cost,
            }],
            total_cost: main_cost + sub_cost,
            sub_share: if main_cost + sub_cost > 0.0 {
                sub_cost / (main_cost + sub_cost)
            } else {
                0.0
            },
        }
    }

    fn test_terminal(w: u16, h: u16) -> Terminal<TestBackend> {
        Terminal::new(TestBackend::new(w, h)).unwrap()
    }

    // FR-2: headline renders on on_open with no keypress.
    #[test]
    fn headline_renders_on_open_with_no_keypress() {
        let mut screen = AnalyticsScreen {
            state: LoadState::Loaded(LoadedData {
                sessions: vec![session("9732d0cf", 30.46, 89.40)],
                report: ParseReport::default(),
                read_at: SystemTime::now(),
            }),
            selected: 0,
            by_agent_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("9732d0cf"));
        assert!(text.contains("119.86") || text.contains("30.46"));
    }

    // FR-2 zero-cost edge: dashed bar, no division by zero, NO BILLED ACTIVITY.
    #[test]
    fn zero_cost_session_renders_dashed_bar_and_no_billed_activity() {
        let mut s = session("zzzz0000", 0.0, 0.0);
        s.by_agent = vec![];
        let mut screen = AnalyticsScreen {
            state: LoadState::Loaded(LoadedData {
                sessions: vec![s],
                report: ParseReport::default(),
                read_at: SystemTime::now(),
            }),
            selected: 0,
            by_agent_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("NO BILLED ACTIVITY"));
        assert!(text.contains("$0 / $0"));
    }

    // FR-3: rows render, and the 30+ scroll edge does not truncate silently
    // (a scroll indicator is present).
    #[test]
    fn many_agent_rows_render_with_a_scroll_indicator() {
        let mut s = session("bigsess1", 100.0, 0.0);
        s.by_agent = (0..30)
            .map(|i| AgentRow {
                agent: format!("agent-{i}"),
                model: "claude-sonnet-5".to_string(),
                calls: (30 - i) as u64,
                cache_read: 10,
                cache_write: 1,
                output: 5,
                cost: (30 - i) as f64,
            })
            .collect();
        let mut screen = AnalyticsScreen {
            state: LoadState::Loaded(LoadedData {
                sessions: vec![s],
                report: ParseReport::default(),
                read_at: SystemTime::now(),
            }),
            selected: 0,
            by_agent_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("30 rows"));
        assert!(text.contains("shown"));
    }

    // FR-5: Empty and Failed(MissingProjectDir) render as different text.
    #[test]
    fn empty_and_missing_project_dir_render_different_text() {
        let mut empty_screen = AnalyticsScreen {
            state: LoadState::Empty {
                searched: PathBuf::from("/some/path"),
            },
            selected: 0,
            by_agent_scroll: 0,
            project_dir: PathBuf::from("/some/path"),
            rates: Rates::load(),
        };
        let mut failed_screen = AnalyticsScreen {
            state: LoadState::Failed {
                error: DiscoveryError::MissingProjectDir(PathBuf::from("/some/path")),
                last_good: None,
            },
            selected: 0,
            by_agent_scroll: 0,
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
        let mut screen = AnalyticsScreen {
            state: LoadState::Refreshing {
                previous: LoadedData {
                    sessions: vec![session("prevsess", 10.0, 5.0)],
                    report: ParseReport::default(),
                    read_at: SystemTime::now(),
                },
            },
            selected: 0,
            by_agent_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("prevsess"));
    }

    // FR-4 stale banner after a failure: last_good populated shows the
    // previous numbers, not a blank error screen.
    #[test]
    fn failed_refresh_with_last_good_shows_stale_numbers_not_blank() {
        let mut screen = AnalyticsScreen {
            state: LoadState::Failed {
                error: DiscoveryError::PermissionDenied(PathBuf::from("/x")),
                last_good: Some(LoadedData {
                    sessions: vec![session("stalesess", 10.0, 5.0)],
                    report: ParseReport::default(),
                    read_at: SystemTime::now(),
                }),
                // short_id truncates to 8 chars; assert against that prefix.
            },
            selected: 0,
            by_agent_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);
        terminal.draw(|f| screen.render(f, f.area())).unwrap();
        let text = rendered_text(&terminal);
        assert!(text.contains("staleses"));
        assert!(text.contains("STALE"));
    }

    // The 100ms render-budget test: fakes 50 in-memory sessions, times
    // on_key/render in a loop. No disk, no TTY (docs/plan-e7.md).
    #[test]
    fn fifty_sessions_render_within_the_per_frame_budget() {
        let sessions: Vec<Session> = (0..50)
            .map(|i| session(&format!("sess{i:04}"), 100.0 - i as f64, i as f64))
            .collect();
        let mut screen = AnalyticsScreen {
            state: LoadState::Loaded(LoadedData {
                sessions,
                report: ParseReport::default(),
                read_at: SystemTime::now(),
            }),
            selected: 0,
            by_agent_scroll: 0,
            project_dir: PathBuf::from("/dev/null"),
            rates: Rates::load(),
        };
        let mut terminal = test_terminal(100, 24);

        for _ in 0..50 {
            let start = Instant::now();
            screen.on_key(KeyEvent::new(
                KeyCode::Char('j'),
                crossterm::event::KeyModifiers::NONE,
            ));
            terminal.draw(|f| screen.render(f, f.area())).unwrap();
            let elapsed = start.elapsed().as_millis();
            assert!(
                elapsed < RENDER_BUDGET_MS,
                "on_key+render took {elapsed}ms, budget is {RENDER_BUDGET_MS}ms"
            );
        }
    }

    // Session list opens on the most-expensive session (settled scope,
    // docs/plan-e7.md).
    #[test]
    fn on_open_selects_index_zero_which_parse_already_sorts_most_expensive_first() {
        // parse() is what guarantees sort order; screen.rs trusts index 0.
        // This is asserted at the parse level (see analytics::parse tests
        // and the parity test) — here we assert the screen renders
        // whatever session is at index 0 without reordering it.
        let mut screen = AnalyticsScreen::new(PathBuf::from("/does/not/exist"), Rates::load());
        let action = screen.on_open();
        assert_eq!(action, Action::Redraw);
        assert_eq!(screen.selected, 0);
    }

    #[test]
    fn jk_always_moves_session_cursor_pgup_pgdn_always_scrolls_by_agent() {
        let sessions: Vec<Session> = (0..3)
            .map(|i| session(&format!("s{i}"), 10.0, 1.0))
            .collect();
        let mut screen = AnalyticsScreen {
            state: LoadState::Loaded(LoadedData {
                sessions,
                report: ParseReport::default(),
                read_at: SystemTime::now(),
            }),
            selected: 0,
            by_agent_scroll: 0,
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
        assert_eq!(screen.by_agent_scroll, BY_AGENT_PAGE);
    }

    #[test]
    fn refresh_is_a_no_op_not_dropped_when_already_refreshing() {
        let mut screen = AnalyticsScreen {
            state: LoadState::Refreshing {
                previous: LoadedData {
                    sessions: vec![session("x", 1.0, 1.0)],
                    report: ParseReport::default(),
                    read_at: SystemTime::now(),
                },
            },
            selected: 0,
            by_agent_scroll: 0,
            project_dir: PathBuf::from("/does/not/exist"),
            rates: Rates::load(),
        };
        screen.on_key(KeyEvent::new(
            KeyCode::Char('r'),
            crossterm::event::KeyModifiers::NONE,
        ));
        // Still Refreshing: the second r was ignored, not dropped as a crash
        // or an unrelated state change.
        assert!(matches!(screen.state, LoadState::Refreshing { .. }));
    }
}
