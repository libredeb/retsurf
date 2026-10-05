//! Servo-facing rendering context: [`SwglRenderingContext`] over swgl, software
//! rendering end to end. This fork's one remaining target (the Pi Zero 2 W) has
//! no GPU path worth carrying — see `Cargo.toml` for the GL/WebGL backend this
//! used to also offer, removed once the pizero2w-only scope made it dead weight.

mod swgl;

pub use self::swgl::SwglRenderingContext;

/// Every buffer here is 32-bit colour: RGBA or BGRA, four bytes either way.
pub const BYTES_PER_PIXEL: usize = 4;
