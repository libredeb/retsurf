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
- [x] **Post-stage hardening, against the real unit.** `bindings.toml`,
      `launch.sh`'s gamepad/audio/video env and opt-in swap tuning, and
      `config.toml`'s `max_fps`: everything below that only confirmed or
      corrected itself once an actual board's `lsusb` / `/proc/bus/input/
      devices` output and its labwc/Wayland/PipeWire stack were in hand,
      rather than assumed from the spec sheet alone.
- [x] **CI**: `.github/workflows/build-pizero2w.yml` builds and packages a
      ready-to-copy `retsurf-pizero2w.zip` on every nightly/release, the one
      workflow in this repo that doesn't fight the fork's own `software`
      default back to `webgl`. `config.toml`'s `[update] auto_check = false`
      is the safety note that goes with it.
- [ ] **Follow-up, not yet done**: `src/update/mod.rs`'s `resolve_kind()`
      needs a pizero2w-specific case so a *manual* update check doesn't still
      offer the wrong (`webgl`-featured) asset — see the update-safety
      section below.

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

## Input: confirmed — Arduino Leonardo joystick, no sticks on the box

Verified on an actual unit (`lsusb`, `/proc/bus/input/devices`): the Arduino
Leonardo ("GamerCard custom gamepad", VID:PID `2341:8036`) enumerates with
`Handlers=event0 js0` — the kernel's `joydev` already treats it as a
**joystick**, not a keyboard. That matters because retsurf has two entirely
separate input paths and only one of them touches joysticks at all:
`src/event/handler.rs` opens a device into `self.game_controllers` — feeding
*both* the chrome's own input (`src/event/gamepad.rs`) and the page-facing
`navigator.getGamepads()` (`src/event/gamepad_api.rs`, the API the
PICO-8/itch.io games this device is marketed for actually read) — **only
when `game_controller_subsystem.is_game_controller(id)` is true**. SDL
answers that from its bundled `gamecontrollerdb` by VID:PID+platform, which a
one-off Arduino HID is never going to be in; an unrecognized joystick is
simply never opened. No crash, no log a user would notice — chrome input and
every web game's Gamepad API both just see nothing.

The fix is the same one `packaging/portmaster/Retsurf.sh` already carries for
unusual pads in production (`export SDL_GAMECONTROLLERCONFIG=
"$sdl_controllerconfig"`): hand SDL a mapping string for this exact VID:PID
before it opens any device, and `is_game_controller()` starts returning true
for it. `launch.sh` now carries the mapping already generated and verified
for this board — see its comment for the GUID and what each field does. One
detail worth knowing: the nav disc reports as two analog axes doing double
duty as both the D-pad (`dpup`/`dpdown`/`dpleft`/`dpright` thresholds) *and*
the Standard Gamepad's left stick (`leftx`/`lefty`) — so
`src/event/gamepad.rs`'s cursor aiming gets real analog movement, not just
8-way digital, at no extra cost.

The mapping covers exactly 8 physical buttons (a/b/x/y/back/start/l1/r1,
matching the spec's "8 tactile buttons" precisely) and no L2/R2/L3/R3 — this
board's firmware never reports `lefttrigger`/`righttrigger` axes or a
`leftstick`/`rightstick` click, so `Pad::L2`/`R2`/`L3`/`R3`
(`src/event/handler.rs`) can physically never fire. The product brief's
original "D-Pad, Analog Sticks, Face Buttons, Shoulders" undersold what's
actually here (no *second* stick, no analog triggers) but retsurf already
fits almost all of it with zero changes: the one stick/D-pad already drives
the virtual cursor, `[controls] edge_scroll` (on by default) scrolls from a
cursor pushed to the screen edge, and every stock default except the
trigger-bound ones resolves onto a button this board actually has — `a/b`
(confirm/cancel), `x/y` + their holds (OSK/reader, hints/bookmark), `l1/r1` +
their holds (prev-back/next-forward, home/reload), and `select`/`start` +
their chords (menu/address, quick access, tab switching) all work exactly as
documented in [`CONTROLS.md`](../../docs/CONTROLS.md) — the same arrangement
the stick-less Miyoo Mini already ships with.

Only `zoom_in`/`zoom_out`/`zoom_reset` are genuinely orphaned (stock-bound
only to `l2`/`r2`/`l2+r2`), plus the on-screen keyboard's L2=Shift/R2=Enter/
R2=Digits-layer *shortcuts* — not its Shift/Caps/Enter keys themselves, which
sit in the grid like any other key and stay fully reachable by D-pad + A
(`src/overlay/osk/mod.rs`); losing the triggers costs a couple of extra
button presses there, not the ability to type. `bindings.toml` below fixes
the zoom gap the same way `config.toml` fixes the memory tier: shipped here,
installed by `launch.sh` on first run only, and it rebinds just the three
broken actions — `src/event/bindings.rs`'s `merge_missing_defaults` restores
every other stock gesture the file doesn't mention, so there's nothing to
keep in sync with upstream's own defaults by hand.

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
free. **Correction from an earlier draft of this file**: this board does run
a compositor — [labwc](https://github.com/labwc/labwc) (wlroots) under its
own launcher, not a bare KMS/DRM console — so a window manager capable of
moving/resizing a toplevel genuinely exists here, unlike the Miyoo Mini's
driver-owns-the-screen setup `panel_size()` was written for. `lock_size`
(SDL's `resizable` flag, see `src/platform/window/mod.rs`) is what keeps
retsurf's own window from being dragged off 720x720 if the custom launcher
or a labwc keybind ever interacts with it directly, and
`src/event/window.rs`'s generic `WindowEvent::Resized` handling (needed for
desktop/Android, where it stays untouched) simply never fires here as a
result — not because nothing could send it, but because the flag says not to.

## Cursor precision: a response curve for the nav disc

Landing the cursor exactly on a small link or field was hard by design, not
by bug: `[controls] cursor_speed` has always scaled the aim vector linearly
(`src/app/router.rs`), so any deflection past the dead zone moves the cursor
at a speed directly proportional to it — fine for crossing the screen, but it
leaves no slow, easy-to-hold zone for a precise final approach, especially on
a short-throw nav disc rather than a long-throw thumbstick. This fork adds
`[controls] cursor_curve` (new config field, `src/config/controls.rs`;
exposed in Settings > Controls as **Cursor precision**): an exponent applied
to the deflection before the speed scaling, `1.0` (every other device,
unchanged — this is the compiled-in default everywhere) being the previous
linear behavior and higher values softening small deflections while leaving
full deflection at the same top speed (`1.0` and `-1.0` are fixed points of
any exponent, and so is the D-pad's own digital `±1` — this never changes
D-pad-only aiming, only the stick's). `config.toml` pins `cursor_curve = 2.0`
here; the exact value is a feel question for the actual nav disc hardware,
which is why it's also a live Settings slider, not just a config file edit.

## 30 fps, not the panel's advertised 60

`[performance] max_fps = 30` in `config.toml` is pinned, not left at
`PerformanceConfig::default()` (also `30`, so behaviorally a no-op today) —
pinned so a later edit "fixing" this to `60` to match the HyperPixel's spec
sheet doesn't regress battery life by accident. Every frame on
`software_render = true` is a full 720x720 CPU recomposite
(`src/platform/window/software.rs`), with no GPU compositor pass to amortize
it the way labwc's own desktop compositing does — doubling the rate doubles
that cost, for a kiosk-style browser UI rather than a twitch game, on a 1600
mAh cell. Raise it only after measuring actual battery life and per-frame
cost on a unit, not from the spec sheet.

## Opt-in: zram/swap tuning for pages that outgrow 512 MB

`launch.sh` now carries the same zram + `vm.swappiness` + `vm.page-cluster`
tuning `packaging/portmaster/Retsurf.sh` already runs in production on
comparably-tight devices, trimmed down (no multi-CFW detection needed for one
Debian 12 target) and adapted to this script's own variable names. It is
**off unless `swap-tuning.on` exists next to `launch.sh`** — check `zramctl`
and `swapon --show` on your image first: a stock Raspberry Pi OS / Debian
install may already run `zram-tools` or a `systemd-zram-generator` unit, and
turning this on too would stack a second zram device on top (harmless —
`swapon -p 1100` just outranks it — but redundant) rather than replace it.
When it does run: a 512 MB `MemTotal` sizes the zram device to roughly
340 MB (`total_mb * 2/3`) of `lz4`-compressed swap, set to outrank any swap
the base image already has so a page that doesn't fit the JS heap/layout
budget gets compressed back into RAM rather than round-tripping the SD/eMMC
card — cheaper than a tab reload, and the thing an OOM kill looks like to a
user on a device with no window to tell them why the page went blank.
Cleans up after itself on any exit, crash included (`trap swap_tuning_stop
EXIT`), same as upstream.

## Confirmed on-device: Wayland compositor, PipeWire audio

Two more things this file assumed are now verified against the real board:

- **Compositor**: this board runs [labwc](https://github.com/labwc/labwc)
  (wlroots) under its own launcher — real Wayland, not a bare KMS/DRM
  console. `SDL_VIDEODRIVER` only needs a manual nudge in `launch.sh` if a
  custom launcher execs retsurf with `WAYLAND_DISPLAY` stripped from its
  environment (common with systemd `--user` units) —
  `src/platform/startup.rs` already auto-selects `wayland` whenever that
  variable is present and the driver is otherwise unset. This also means the
  GPU is alive and in active use *for compositing* — `software_render = true`
  above is still the right call regardless (it's about not doubling GPU
  memory pressure with retsurf's own EGL/WebGL context on top of what labwc
  already uses, a RAM argument, not a "no GPU exists" one), and the
  `SoftwareBackend` path (`src/platform/window/software.rs`) never requests
  `SDL_WINDOW_OPENGL` on its window in the first place
  (`build_window(video, config, false)`), so it cannot pick a GL-based SDL
  renderer even by accident — confirmed zero GL/EGL touch under labwc too.
- **Audio**: PipeWire. `launch.sh` now exports `SDL_AUDIODRIVER=pipewire`
  (Debian 12's SDL2 2.26 has a native backend for it).

## Files

| File | Purpose |
| --- | --- |
| `config.toml` | Copied to the data dir on first run as `config.toml`. |
| `bindings.toml` | Copied to the data dir on first run; rebinds `zoom_in`/`zoom_out`/`zoom_reset` off the l2/r2 triggers this board doesn't have (see the Input section above). Every other gesture comes back from retsurf's own compiled-in defaults. |
| `fonts.conf.in` | Fontconfig template; `launch.sh` only installs it if the image's own fontconfig can't resolve a sans-serif font at all. `@FCCACHE@` is substituted with a writable cache path. |
| `launch.sh` | Example launcher: env vars, first-run config/bindings install, conditional fontconfig template, opt-in zram/swap tuning (`swap-tuning.on`). Adjust `gamedir`/controller mapping/autostart to your image. |
| `../../.github/workflows/build-pizero2w.yml` | Not in this directory, but builds and packages everything above into `retsurf-pizero2w.zip` on every nightly and tagged release — see the CI section below. |

## CI: `build-pizero2w.yml`, and where it differs from every other job

None of this repo's existing workflows ever produced a binary this board
should run: `build-linux-arm.yml`'s per-core matrix and `build-universal` job,
and `build-linux.yml`'s desktop build, all explicitly pass
`--no-default-features --features webgl` to pin back to a GPU-featured build
— correct for PortMaster handhelds and desktop Linux, the opposite of what
this fork's own default flip (`Cargo.toml`, `default = ["software"]`) was
for. `build-pizero2w.yml` is the one that doesn't fight that default: plain
`cargo build --release` with `RUSTFLAGS: -C target-cpu=cortex-a53` (the
board's CPU is fixed and known, unlike PortMaster's A35/A53/A55 spread), no
feature flags at all. It also skips the `ubuntu:20.04` glibc-floor container
every ARM job here otherwise needs: that floor exists for a decade of
mismatched handheld firmwares, not a known, modern, single target OS (Debian
12 bookworm, glibc 2.36) — the plain `ubuntu-22.04-arm` runner (glibc 2.35) is
already an older floor than the device, and mozjs_sys's prebuilt SpiderMonkey
(itself built on Ubuntu 22.04) needs no `MOZJS_FROM_SOURCE` rebuild to match
it, unlike the floored jobs.

It uploads two artifacts: `retsurf-pizero2w-bin` (the bare binary, CI-only,
14-day retention) and `retsurf-pizero2w` (the binary plus every file this
directory ships — `config.toml`, `bindings.toml`, `fonts.conf.in`,
`launch.sh` — laid out exactly as the Install section below copies them,
ready to unzip straight into `/opt/retsurf/`). A tagged release also zips the
second one with a `.sha256` sidecar, and `nightly.yml` now builds and
publishes it alongside every other platform.

**Before this release asset exists publicly, read the update-safety note
right below** — it's the reason `config.toml` ships `[update] auto_check =
false`.

## Update safety: `[update] auto_check = false` is load-bearing here

`src/update/mod.rs`'s install-kind detection (`resolve_kind()`) has no case
for this board: it only special-cases PortMaster (a sibling `Retsurf.sh`
file) before falling through to "any writable-directory `linux`/`aarch64`
install" as `Kind::Single`, pointed at the **generic** release asset,
`retsurf-linux-aarch64.zip` — the `webgl`-featured, untuned universal build
from `build-linux-arm.yml`, not this board's own `retsurf-pizero2w.zip`. With
`auto_check` on (the engine's own default), this board would see "update
available" and, if installed, get swapped onto a binary that doesn't even
compile `SoftwareBackend` in — `config.toml`'s `software_render = true` would
have nothing to select at that point. `config.toml` above turns the
background check off so this never ambushes anyone from a notification; it
doesn't stop a manual check from Settings > About, which is still a trap
until `resolve_kind()` gains a pizero2w-specific case (a sibling-file check
in the same spirit as `portmaster_paths()`, pointed at
`retsurf-pizero2w.zip`) — filed as a follow-up, not yet done.

## Install

**Easiest**: download `retsurf-pizero2w.zip` from a [release](../../releases)
(or the `retsurf-pizero2w` artifact off a `build-pizero2w.yml` Actions run)
and unzip it straight into `/opt/retsurf/` — it already contains the binary
plus all four files this directory ships, laid out ready to run
(`chmod +x /opt/retsurf/launch.sh` once, since zip doesn't always preserve
the executable bit).

**Building it yourself** instead — on-device, or any arm64 Linux box:

```sh
mkdir -p /opt/retsurf
cp /path/to/retsurf /opt/retsurf/
cp packaging/pizero2w/config.toml /opt/retsurf/
cp packaging/pizero2w/bindings.toml /opt/retsurf/
cp packaging/pizero2w/fonts.conf.in /opt/retsurf/
cp packaging/pizero2w/launch.sh /opt/retsurf/ && chmod +x /opt/retsurf/launch.sh
```

The binary itself needs building with this fork's new defaults (stage 3):
a plain `cargo build --release` already produces a CPU-only binary matching
`[display] software_render = true` above — no extra `--features` flag needed,
unlike every *other* platform this repo still ships GPU builds for (see the
repo root's `Cargo.toml` and the `README.md`/`CHANGELOG.md` for that change;
`.github/workflows/build-pizero2w.yml` is the CI job that builds exactly
this, see the CI section above for why it looks nothing like its siblings).

Unlike the PortMaster per-core matrix (`tools/arm64/build.sh`), which must
produce one binary that runs on A35, A53 *and* A55 cores, this board's CPU is
fixed and known: a Cortex-A53 quad-core. Building directly on the device
(Debian 12 arm64) can safely tell rustc that, which a generic/portable
build does not:

```sh
RUSTFLAGS="-C target-cpu=cortex-a53" cargo build --release
```

Not added to the repo's `.cargo/config.toml`: that file's `rustflags` would
apply to every `aarch64-unknown-linux-gnu` build in this repo, including the
PortMaster one that must stay portable across A35/A53/A55 — this belongs in
this board's own build invocation (or a `RUSTFLAGS` export in a local
build script), not shared.

## Minor: `[experimental] webgl2` stays on even though WebGL can't run

`ExperimentalConfig::default()` (the "Balanced" preset, `src/config/experimental.rs`)
ships `webgl2 = true`. On this fork's software-only default, `servo/webgl`
isn't compiled in at all (see the repo's `Cargo.toml`), so `canvas.getContext
('webgl2')` returns `null` regardless of this preference — it's a no-op, not
a bug: the flag only governs whether the (compiled-out) WebGL backend is
*permitted*, not whether it exists. **Left as-is here, on purpose**:
`packaging/miyoo/shared/config.toml` — the one other device in this repo that
already ships `--features software` with no `webgl` in production today —
makes the same choice, leaving the preset at its default rather than special
-casing a cosmetic mismatch in the Settings screen. Flip it to `false` only
if a `[debug] memory_overlay` session on-device shows the few KB the unused
preference string costs are worth chasing; it will not change behavior
either way.
