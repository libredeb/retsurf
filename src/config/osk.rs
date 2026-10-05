use crate::config::token_enum::token_enum;
use serde::{Deserialize, Serialize};

/// On-screen-keyboard settings (`[osk]` in the config): which of the built-in
/// layouts are enabled — see [`crate::overlay::osk`] for the layout data itself.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct OskConfig {
    /// Enabled layouts, in the order the keyboard's Lang key cycles them.
    /// Unknown names are logged and skipped; an empty (or fully invalid) list
    /// falls back to `["en"]`, so the keyboard always works.
    pub layouts: Vec<String>,
    pub style: OskStyle,
    /// Stretch the grid keyboard to fill the panel's width instead of its
    /// hand-tuned design size (`ROW_SPAN` in `src/ui/osk/mod.rs`), which is
    /// narrower than most square handheld panels. Off by default: every
    /// desktop and the other handhelds already size their window around that
    /// design, so stretching it there would just make the keys oversized.
    /// Grid style only — the wheel has no row width to stretch.
    pub full_width: bool,
}

impl Default for OskConfig {
    fn default() -> Self {
        Self {
            layouts: vec!["en".to_string(), "ru".to_string()],
            style: OskStyle::default(),
            full_width: false,
        }
    }
}

token_enum! {
    /// How the keyboard picks a character.
    pub enum OskStyle {
        default Grid;
        /// A key grid walked with the D-pad or stick.
        Grid => "grid", "Grid",
        /// The left stick picks one of eight groups, a face button one of its
        /// four characters. Needs an analog stick.
        Wheel => "wheel", "Wheel",
    }
}
