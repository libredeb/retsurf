# retsurf — Raspberry Pi Zero 2 W / HyperPixel 4.0 Square

Device profile for a single-purpose handheld built on a Raspberry Pi Zero 2 W
(4x Cortex-A53, **hard-capped at 512 MB total RAM**, shared with the VideoCore
GPU's own carve-out) driving a Pimoroni HyperPixel 4.0 Square panel (720x720,
no touch) through a standard game controller.

This directory is being built up in the same stages as the refactor itself:

- [x] **Stage 1 — resource trim.** `config.toml`, `fonts.conf.in` and
      `launch.sh` below: pinned memory tier, image-cache ceiling, zero bundled
      font bytes.
- [x] **Stage 2 — 720x720 square compositing.** `[display]` in `config.toml`:
      fixed 720x720, CPU rendering, no window-manager resize.
- [x] **Stage 3 — forced size-optimized/CPU-only build profile.** Lives in the
      repo root's `Cargo.toml` (`[profile.release]`, `default = ["software"]`),
      not here — see the project's own changelog/commit history for that stage.

## Why `embedded`, not a new tier

`src/browser/memory.rs` already ships a memory tier for exactly this RAM
class — `MemoryProfile::Embedded`, documented there as "~512 MB (sub-1 GB
boards): the floor." Auto-detection (`suggest()`) already resolves any
`MemTotal` between 257 and 768 MB to it, so the Pi Zero 2 W lands there with no
code change. `config.toml` below pins it explicitly anyway (`memory_profile =
"embedded"`), the same way `packaging/miyoo/shared/config.toml` pins `micro`:
a tier picked by a hand-set value in the shipped config survives an SoC that
reports a slightly different `MemTotal` after the GPU's memory split, where
leaving it on `auto` would not.

That tier already does most of section 1's "aggressive cache limiting" ask by
itself: no in-memory or on-disk HTTP cache, a single layout/worker thread, a
64 MB JS heap with the most eager GC thresholds short of `micro`'s, grayscale-
only text AA, and every optional DOM subsystem (WebXR, Bluetooth, service/
shared workers, worklets, accessibility) off. `config.toml` only adds what the
tier doesn't own: one tab, one disk-cache policy, and a decoded-image ceiling.

## No embedded fonts to strip

There is nothing to remove here: `src/` and `resources/` carry zero `.ttf`/
`.otf`/`.woff` bytes already (check with `find . -iname '*.ttf' -o -iname
'*.woff*'` from the repo root). `servo` is pulled in with
`default-features = false`, so no bundled-fallback-font feature of the engine
is even compiled in; `bundled_freetype` bundles the FreeType *library* for
cross-compilation only, not font data. Glyph lookup goes through font-kit,
which resolves through fontconfig on Linux — `fonts.conf.in` below is that
resolution's only configuration, and it ships no font of its own, only
pointers at whatever the base image already carries (Raspberry Pi OS and
Debian-derived images bring `fontconfig` and a `fonts-dejavu-core` package by
default).

The one bundled font in the dependency graph, `egui-phosphor` (the chrome's
button icons), is not a text font — it is a small icon glyph set, already
built with only the two weight variants retsurf draws (`bold`, `fill`) rather
than all six upstream ships. Dropping it would blank out every toolbar icon
for a few hundred KB; not worth it at this binary's size.

## Square compositing: a config value, not a new layout engine

`src/ui/scale.rs` already draws the whole chrome against one 640x480 design
and picks a single zoom factor from whatever panel it actually lands on — the
Miyoo Flip's 752x560 and a 1280x720 desktop window already go through this,
not a fixed 640x480 assumption. For a 720x720 panel:

```
fit = min(720/640, 720/480) = min(1.125, 1.5) = 1.125
```

1.125 is within `WHOLE_ZOOM_REACH` (0.25) of a whole step, so it floors to a
crisp `1.0` zoom rather than rendering type between pixels for a 12.5% gain —
the same rule that already keeps the Flip's 17%-oversized panel at `1.0`. The
80 extra points the square panel has over the 640x480 design on *both* axes
go to the page's viewport, not to larger chrome — `[display]` only needs to
say `720`/`720`; no override, no new scale constant, no device-specific
branch. `src/ui/scale.rs`'s test suite now carries this panel size
(`a_square_panel_a_little_past_the_design_also_keeps_a_whole_zoom`) so a
future change to the fit math can't regress it unnoticed.

Legibility at a glance: this panel's 4" diagonal at 720x720 is ~254 ppi —
*lower* density than the Flip's ~268 ppi, where `1.0` zoom is already the
shipped, read-at-arm's-length default. Nothing here needs to render larger to
stay legible; if anything this panel has more headroom than a device already
in the field.

`[display] lock_size = true` is the one thing the fit math can't give for
free: it is about *not having a window manager to drag the window away from
720x720* (and, incidentally, not reacting to a resize event that can now
never fire — `src/event/window.rs`'s generic `WindowEvent::Resized` handling
stays untouched, since Android and desktop still need it; it is simply inert
here), not about layout. See `DisplayConfig::lock_size` in
`src/config/display.rs`.

## Files

| File | Purpose |
| --- | --- |
| `config.toml` | Copied to the data dir on first run as `config.toml`. |
| `fonts.conf.in` | Fontconfig template; `launch.sh` only installs it if the image's own fontconfig can't resolve a sans-serif font at all. `@FCCACHE@` is substituted with a writable cache path. |
| `launch.sh` | Example launcher: env vars, first-run config install, conditional fontconfig template. Adjust `GAMEDIR`/controller mapping/autostart to your image. |

## Install

```sh
mkdir -p /opt/retsurf
cp /path/to/retsurf-linux-aarch64/retsurf /opt/retsurf/
cp packaging/pizero2w/config.toml /opt/retsurf/
cp packaging/pizero2w/fonts.conf.in /opt/retsurf/
cp packaging/pizero2w/launch.sh /opt/retsurf/ && chmod +x /opt/retsurf/launch.sh
```

The binary itself needs building with this fork's new defaults (stage 3):
a plain `cargo build --release` (or the arm64 cross-build in
`tools/arm64/build.sh`, once it's taught this board's target triple/CPU
tuning) now produces a CPU-only binary already matching
`[display] software_render = true` above — no extra `--features` flag needed,
unlike every *other* platform this repo still ships GPU builds for (see the
repo root's `Cargo.toml` and the `README.md`/`CHANGELOG.md` for that change).
