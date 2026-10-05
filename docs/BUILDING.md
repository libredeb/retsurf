# Building from source

retsurf builds with plain `cargo`; rustup installs the Rust version pinned in
[`rust-toolchain.toml`](../rust-toolchain.toml). Servo brings C/C++ dependencies of its
own, so the first build is long.

This fork targets exactly one board — the Raspberry Pi Zero 2 W GamerCard — so there is
only one build, with no GPU feature to opt into: CPU-only (swgl + SDL's own renderer) end
to end, on Debian 12 (bookworm) ARM64.

## Linux

```sh
sudo apt-get install -y build-essential clang cmake curl git gperf pkg-config python3 \
  libssl-dev libdbus-1-dev libfreetype6-dev libglib2.0-dev \
  libharfbuzz-dev liblzma-dev libudev-dev libunwind-dev libsdl2-dev
```

```sh
cargo build --release
```

CI release builds add fat LTO, `codegen-units = 1`, `opt-level = "z"` and `panic = "abort"`
— pinned directly in `Cargo.toml` (not CI-only), so a local `cargo build --release` now
matches what ships. This trades local iteration speed for every build being the real
thing; see the comments in `Cargo.toml`'s `[profile.release]` if that tradeoff needs
revisiting for day-to-day development.

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
