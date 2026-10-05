use serde::{Deserialize, Serialize};

/// The window and how it is drawn (`[display]` in the config): its size, the
/// GL backend, and panel quirks.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct DisplayConfig {
    /// The size the window opens at, where the driver leaves that to us (desktop,
    /// never a handheld). Rewritten on exit with the size it was left at.
    pub width: u32,
    pub height: u32,
    /// Request an OpenGL ES context (required on Mali handhelds) instead of
    /// desktop GL. Can be overridden at startup via `RETSURF_GLES=0`.
    pub use_gles: bool,
    /// Render the page and the chrome on the CPU, with no GL context at all —
    /// the only thing that draws on a GPU-less device (Miyoo Mini). Needs the
    /// `software` build feature; overridden at startup via `RETSURF_SOFTWARE=1`.
    pub software_render: bool,
    /// Paint the screen's last row black. Some panels show that row again as the
    /// first one, so a light page bleeds a band above the toolbar (muOS/A133).
    pub dark_last_row: bool,
    /// Build the window without SDL's `resizable` flag, so a window manager
    /// present on the box (X11/Wayland during development, say) cannot drag it
    /// away from `width`x`height`. Off by default: on every other target the
    /// flag is already inert (no mouse/WM to act on it — a touch handheld, a
    /// panel driver that owns the screen outright, Android's own fixed
    /// surface) and the dynamic-resize path (`src/event/window.rs`'s
    /// `WindowEvent::Resized` handling) stays in place for the targets that do
    /// need it (desktop, Android rotation). A panel wired to one fixed
    /// resolution with no compositor at all (a dedicated kiosk board) turns
    /// this on to make that guarantee a build-configured fact rather than an
    /// absence of hardware able to break it.
    pub lock_size: bool,
}

impl Default for DisplayConfig {
    fn default() -> Self {
        Self {
            width: 640,
            height: 480,
            use_gles: true,
            software_render: false,
            dark_last_row: false,
            lock_size: false,
        }
    }
}
