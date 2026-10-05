//! Pre-SDL startup wiring: the env overrides and SDL hints that must be in
//! place before any video init, gathered here so [`crate::run_app`] reads as
//! hooks, logging, config, prepare, run.

use crate::config::{self, AppConfig};

/// Fold the environment into `config` and set the process hints its choices
/// require. Must run before `sdl2::init`.
pub fn prepare(config: &mut AppConfig) {
    // A launcher's way to try a frame cap without editing the config — and the
    // way to compare two of them in one sitting.
    if let Some(fps) = std::env::var("RETSURF_MAX_FPS")
        .ok()
        .and_then(|v| v.parse::<u32>().ok())
    {
        // Lands after `load`'s sanitize pass, so it clamps here.
        config.performance.max_fps = fps.min(config::bounds::MAX_FPS.max as u32);
    }
    // We handle the finger events ourselves, and SDL's synthesized clicks
    // would fire at the end of every scroll.
    #[cfg(target_os = "android")]
    std::env::set_var("SDL_TOUCH_MOUSE_EVENTS", "0");

    // SDL defaults to x11 on a Wayland desktop while surfman reads WAYLAND_DISPLAY,
    // and two different display servers fail GL context creation.
    #[cfg(not(target_os = "android"))]
    if std::env::var_os("SDL_VIDEODRIVER").is_none()
        && std::env::var_os("WAYLAND_DISPLAY").is_some()
    {
        std::env::set_var("SDL_VIDEODRIVER", "wayland");
    }

    // Without this hint SDL lets Android background the activity on Back; with
    // it the button arrives as an AC_BACK key (mapped in crate::event::keyboard).
    #[cfg(target_os = "android")]
    std::env::set_var("SDL_ANDROID_TRAP_BACK_BUTTON", "1");
}
