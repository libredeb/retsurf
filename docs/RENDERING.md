# Rendering

How a page reaches the screen on this fork's one remaining target (the Raspberry Pi Zero
2 W): entirely on the CPU, with no GL driver at all.

> This fork dropped the GPU/WebGL chrome backend upstream also offered (`src/platform/
> window/gl.rs`, the `webgl` Cargo feature, `android/`) once the pizero2w-only scope made
> it dead weight — the VideoCore IV's shared-memory GL path costs RAM this device has none
> of spare, on a panel too small for the difference to be visible.

## How it works

- [swgl](https://crates.io/crates/swgl), WebRender's software backend, rasterizes the page.
  It must match our `webrender` version, which picks its software paths by renderer name.
- SDL's 2D renderer draws the chrome over the page into one surface, presented as a single
  texture copy.

swgl's framebuffer is already SDL's `ARGB8888` layout, so the page is copied row by row,
flipped. With no vsync, the loop caps at `[performance] max_fps`. `[debug] frame_timing`
logs the frame cost.

| File | Role |
|------|------|
| `src/platform/render/swgl.rs` | `SwglRenderingContext`: swgl's framebuffer as a `RenderingContext` |
| `src/platform/window/software.rs` | the composition surface, the chrome paint, presenting |
| `src/ui/mod.rs` | sizes the browser viewport |
| `src/app/mod.rs` | the loop: Servo paints, then the window composites and presents |

## Tuning

```sh
RETSURF_PARTIAL_PRESENT=1 cargo run   # present only the changed part of the frame
RETSURF_ROUNDING=1 cargo run          # restore rounded chrome corners (costlier to rasterize)
RETSURF_FEATHERING=1 cargo run        # restore egui's edge smoothing
RETSURF_MAX_FPS=30 cargo run          # override [performance] max_fps
```

See [Command line](CLI.md#environment-variables) for the full list.
