// Renders a `ShellError` as a full frame: the message, and a line stating
// that `q` quits and `Tab` switches. Deciding what is an error and
// recovering from one are not this module's job — `mod.rs` decides when to
// hand off here.

use super::ShellError;
use ratatui::layout::Rect;
use ratatui::style::{Color, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Paragraph, Wrap};
use ratatui::Frame;

pub fn render(frame: &mut Frame, area: Rect, error: &ShellError) {
    let lines = vec![
        Line::from(Span::styled(
            "Error",
            Style::default().fg(Color::Red),
        )),
        Line::from(error.message.clone()),
        Line::from(""),
        Line::from("q quits. Tab switches screens."),
    ];
    let paragraph = Paragraph::new(lines).wrap(Wrap { trim: false });
    frame.render_widget(paragraph, area);
}

#[cfg(test)]
mod tests {
    use super::*;
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;

    #[test]
    fn renders_the_message_and_the_still_works_line() {
        let backend = TestBackend::new(40, 6);
        let mut terminal = Terminal::new(backend).unwrap();
        let error = ShellError {
            message: "boom".to_string(),
        };

        terminal
            .draw(|frame| render(frame, frame.area(), &error))
            .unwrap();

        let buffer = terminal.backend().buffer().clone();
        let rendered: String = buffer
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect();

        assert!(rendered.contains("boom"), "rendered: {rendered}");
        assert!(rendered.contains("Tab"), "rendered: {rendered}");
        assert!(
            rendered.contains('q') || rendered.to_lowercase().contains("quit"),
            "rendered: {rendered}"
        );
    }
}
