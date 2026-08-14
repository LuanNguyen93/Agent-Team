// Holds the registered screens in a stable order, the active index, and
// switching. Never constructs, clones or drops a screen — `main.rs`
// constructs screens; this module only holds and indexes the boxes it is
// handed. Never knows what any screen renders.

use super::Screen;

pub struct Registry {
    screens: Vec<Box<dyn Screen>>,
    active: usize,
}

impl Registry {
    pub fn new(screens: Vec<Box<dyn Screen>>) -> Self {
        Self { screens, active: 0 }
    }

    pub fn len(&self) -> usize {
        self.screens.len()
    }

    pub fn is_empty(&self) -> bool {
        self.screens.is_empty()
    }

    pub fn active_index(&self) -> usize {
        self.active
    }

    pub fn active(&mut self) -> Option<&mut Box<dyn Screen>> {
        self.screens.get_mut(self.active)
    }

    /// Advances to the next screen, modulo the length. A no-op when there
    /// are zero or one screens.
    pub fn next(&mut self) {
        if self.screens.len() > 1 {
            self.active = (self.active + 1) % self.screens.len();
        }
    }

    /// Moves to the previous screen, modulo the length. A no-op when there
    /// are zero or one screens.
    pub fn prev(&mut self) {
        if self.screens.len() > 1 {
            self.active = (self.active + self.screens.len() - 1) % self.screens.len();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::shell::Action;

    struct NamedScreen(&'static str);

    impl Screen for NamedScreen {
        fn title(&self) -> &str {
            self.0
        }

        fn render(&mut self, _frame: &mut ratatui::Frame, _area: ratatui::layout::Rect) {}

        fn on_key(&mut self, _key: crossterm::event::KeyEvent) -> Action {
            Action::Ignored
        }
    }

    fn screens(names: &[&'static str]) -> Vec<Box<dyn Screen>> {
        names
            .iter()
            .map(|n| Box::new(NamedScreen(n)) as Box<dyn Screen>)
            .collect()
    }

    #[test]
    fn switch_is_inert_with_exactly_one_screen() {
        let mut reg = Registry::new(screens(&["only"]));
        assert_eq!(reg.active_index(), 0);
        reg.next();
        assert_eq!(reg.active_index(), 0);
        reg.prev();
        assert_eq!(reg.active_index(), 0);
    }

    #[test]
    fn switch_is_inert_with_zero_screens() {
        let mut reg = Registry::new(screens(&[]));
        assert!(reg.is_empty());
        reg.next();
        assert_eq!(reg.active_index(), 0);
        assert!(reg.active().is_none());
    }

    #[test]
    fn switch_cycles_deterministically_through_five_or_more_screens() {
        let mut reg = Registry::new(screens(&["a", "b", "c", "d", "e"]));
        let mut order = Vec::new();
        for _ in 0..reg.len() {
            order.push(reg.active().unwrap().title().to_string());
            reg.next();
        }
        assert_eq!(order, vec!["a", "b", "c", "d", "e"]);
        // wraps back to the start
        assert_eq!(reg.active().unwrap().title(), "a");

        reg.prev();
        assert_eq!(reg.active().unwrap().title(), "e");
    }
}
