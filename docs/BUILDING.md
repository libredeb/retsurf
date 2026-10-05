# Building from source

retsurf builds with plain `cargo`; rustup installs the Rust version pinned in
[`rust-toolchain.toml`](../rust-toolchain.toml). Servo brings C/C++ dependencies of its
own, so the first build is long.

This fork targets exactly one board — the Raspberry Pi Zero 2 W GamerCard — on Debian 12
(bookworm) ARM64. Rendering is GL (`default = ["webgl"]`, see `Cargo.toml`'s `[features]`
comment) atop Mesa's software rasterizer rather than this board's own GPU driver or this
fork's swgl `software` feature — [Rendering](RENDERING.md) has the full reasoning.
`LIBGL_ALWAYS_SOFTWARE=1` (set in `packaging/pizero2w/launch.sh`, see below for a local
`cargo run`) is what forces Mesa's CPU path; without it a build still runs, just against
whatever real GL driver the machine has.

## Linux

```sh
sudo apt-get install -y build-essential clang cmake curl git gperf pkg-config python3 \
  libssl-dev libdbus-1-dev libfreetype6-dev libglib2.0-dev \
  libgl1-mesa-dev libegl1-mesa-dev libgles2-mesa-dev \
  libharfbuzz-dev liblzma-dev libudev-dev libunwind-dev libsdl2-dev
```

```sh
cargo build --release
LIBGL_ALWAYS_SOFTWARE=1 cargo run    # force Mesa's CPU rasterizer, as the device does
```

CI release builds add fat LTO, `codegen-units = 1`, `opt-level = "z"` and `panic = "abort"`
— pinned directly in `Cargo.toml` (not CI-only), so a local `cargo build --release` now
matches what ships. This trades local iteration speed for every build being the real
thing; see the comments in `Cargo.toml`'s `[profile.release]` if that tradeoff needs
revisiting for day-to-day development.

## Cargo features

| Feature | Default | What it does |
| --- | --- | --- |
| `webgl` | **on** | GL chrome backend + WebGL, over SDL's EGL display — see [Rendering](RENDERING.md) for why this fork runs it atop Mesa's software rasterizer rather than this board's own GPU driver |
| `software` | off | CPU rendering: swgl rasterizes the page, SDL's own renderer paints the chrome. Kept only as a last-resort fallback (`RETSURF_SOFTWARE=1`/`[display] software_render`) — see `Cargo.toml`'s `[features]` comment for the crash it can hit |
| `sdl2-bundled` | off | Build SDL2 from source |
| `sdl2-static-link` | off | Link SDL2 statically |

## Tests

```sh
cargo test                           # unit tests + the engine-source guard
python3 tests/run_pages.py           # the pages, in a headless browser
```

The page runner needs a release binary, `Xvfb`, `xdotool` and `ffmpeg`. It loads each page
from `tests/serve.py` and checks the results the page reports. The `Check` workflow runs
both.

## The device build

CI (`build-pizero2w.yml`) cross-compiles on a native `aarch64` runner with
`RUSTFLAGS="-C target-cpu=cortex-a53"` (the board's exact CPU, a choice the universal
handheld builds upstream kept — portable across several ARM cores — never had to make
here, since this fork has only the one board). It then packages the binary with
`packaging/pizero2w/`'s config, bindings, fonts and launch script. See
[`packaging/pizero2w/README.md`](../packaging/pizero2w/README.md) for what ships beside
the binary and how the console's own software store installs it.
