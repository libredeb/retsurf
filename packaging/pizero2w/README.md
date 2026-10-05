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
      ready-to-copy `retsurf-pizero2w.zip` on every nightly/release — this
      fork's only remaining build workflow, needing no feature override of
      its own now that `software` is this fork's only rendering path at all.
- [x] **Platform scope and GL/WebGL removal.** This fork dropped every
      non-pizero2w platform from the repo (see the CI section below) and then
      the GL/WebGL chrome backend itself, Cargo feature and all, once nothing
      left in the tree still needed it — see the "GL/WebGL backend removed
      entirely" section below.
- [x] **Grid launcher integration.** `config.toml`'s `[osk] full_width`, a
      `start+select` → `quit` chord in `bindings.toml`, and
      `retsurf.desktop`'s `Categories=Game;` — see the three sections below.
      This is the device running its own systemd → labwc → custom-grid-
      launcher chain, with retsurf as one tile among other games rather than
      the only thing on screen.

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
detail worth knowing: the nav disc is only two analog axes, mapped onto the
Standard Gamepad's left stick (`leftx`/`lefty`) alone — **no `dpXXX` tokens**,
unlike an earlier draft of this mapping, which also pointed `dpup`/`dpdown`/
`dpleft`/`dpright` at those same two axes and ended up saturating the cursor
aim vector on every meaningful push; see the Cursor precision section below
for the full story and why this is the one part of the mapping that changed
after testing on the real unit, not just at generation time.

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
`src/event/window.rs`'s generic `WindowEvent::Resized` handling (shared,
general-purpose code, left as-is) simply never fires here as a result — not
because nothing could send it, but because the flag says not to.

## Cursor precision: a response curve for the nav disc

Landing the cursor exactly on a small link or field was hard by design, not
by bug: `[controls] cursor_speed` has always scaled the aim vector linearly
(`src/app/router.rs`), so any deflection past the dead zone moves the cursor
at a speed directly proportional to it — fine for crossing the screen, but it
leaves no slow, easy-to-hold zone for a precise final approach, especially on
a short-throw nav disc rather than a long-throw thumbstick. This fork adds
`[controls] cursor_curve` (new config field, `src/config/controls.rs`;
exposed in Settings > Controls as **Cursor precision**): an exponent applied
to the deflection before the speed scaling, `1.0` (the compiled-in default)
being the previous linear behavior and higher values softening small
deflections while leaving full deflection at the same top speed (`1.0` and
`-1.0` are fixed points of any exponent — more on that below). `config.toml`
pins `cursor_curve = 2.0` here; the exact value is a feel question for the
actual nav disc hardware, which is why it's also a live Settings slider, not
just a config file edit.

**Why trying `2.0`, `1.0` and `0.3` all felt identical on the real unit**: a
curve can only shape a value *between* its fixed points — it does nothing
once the input is already pinned at one of them. `Gamepad::aim()`
(`src/event/gamepad.rs`) is `(stick + dpad).clamp(-1, 1)`, where `dpad` is a
genuinely digital `±1`/`0` by design — correct for a real separate D-pad
(the Miyoo Mini has one and no stick at all, and there a D-pad press should
always aim at full speed), wrong the moment a D-pad press and a stick push
are the *same* physical motion. That was exactly this board's original
`SDL_GAMECONTROLLERCONFIG` (see `launch.sh`'s own comment): it mapped
`leftx`/`lefty` *and* `dpup`/`dpdown`/`dpleft`/`dpright` onto the same two
nav-disc axes, so every push past SDL's own axis-to-button threshold
(well below full deflection) also fired a synthetic D-pad press, adding a
full `±1` into `aim()` and saturating it there regardless of how far past
that threshold the disc actually travelled. One push, one instant snap to
top speed — a curve exponent changes how `aim` is shaped between 0 and `±1`,
and this input was never landing anywhere in that range.

The fix was at the input-mapping layer, not the curve: `launch.sh` no longer
maps any `dpXXX` token, so SDL never synthesizes those button presses off
this disc's axes, and `aim()` is left with the genuine, continuous
`leftx`/`lefty` value end to end. `cursor_curve` only has real, unsaturated
input to shape as of that change — re-tune it live in Settings now that it
actually does something, rather than trusting `2.0` as a value that was
never actually tested on this hardware. The one thing lost: hint mode's
D-pad-press combo-letter shortcut (`InputCommand::DpadPress`,
`src/app/router.rs`), which needs a real D-pad press that no longer exists —
`config.toml` turns `[controls] hint_badges` off for exactly that reason,
falling hint mode back to plain spatial hopping via the stick (unaffected by
any of this, since it was already reading `stick` — the undiluted left-stick
vector — rather than `aim`).

## On-screen keyboard: stretched to the panel's actual width

The grid keyboard's layout (`src/ui/osk/mod.rs`) is a hand-tuned design sized
to `ROW_SPAN` (574 points) — narrower even than the 640-wide chrome design
it was tuned against, let alone this 720px square panel at the `1.0` zoom the
square-compositing section above lands it on. The keys were never going to
grow to fill the extra width on their own: `src/ui/scale.rs`'s global zoom
factor scales the *whole* chrome uniformly against one design size, and any
panel width past that design already goes to the page's own viewport, not to
chrome widgets like the keyboard — confirmed by reading both files, not
guessed from the photo alone.

This fork adds `[osk] full_width` (new config field, `src/config/osk.rs`;
exposed in Settings > Controls as **Full-width keyboard**; grid style only —
the wheel picker has no row width to stretch): when on, every key, gap and
badge in `src/ui/osk/mod.rs` is multiplied by one `scale` factor computed
from the actual available panel width (`ctx.content_rect().width()`) against
`ROW_SPAN`, clamped to `[1.0, 1.6]` so an unusually wide panel can't blow the
keys up into oversized slabs. `scale` is exactly `1.0` — a no-op, same numbers
as before this change — whenever the flag is off, which is every device
except this one: default `false` in `src/config/osk.rs`, only flipped on in
`config.toml` below. `config.toml` pins `full_width = true` here, landing
around `scale ≈ 1.2` on this 720x720 panel (`(720 - 24) / 574`).

## START+SELECT: freed for the grid launcher to intercept

This board doesn't run retsurf as *the* thing on screen — its own systemd
service starts [labwc](https://github.com/labwc/labwc), which autostarts a
custom grid launcher, and retsurf is one tile in that grid among other games.
A launcher built that way needs some way to know the user wants back out
to the grid; without one, the only exits left are a window-manager close
button this kiosk setup has none of, or killing the process from outside.

retsurf already carries exactly the primitive this needs:
`Action::Quit` (`src/event/bindings.rs`) maps straight onto the engine's
normal clean-exit path (session save, Servo shutdown,
`std::process::exit(0)`) and is **unbound by default upstream, on purpose** —
its own doc comment says so — precisely so a device like this one can bind
it to whatever its hardware can spare. `bindings.toml` below binds
`start+select` (both orders, same idiom as the stock `l2+r2`/`r2+l2`) to
`quit`.

No `launch.sh` change was needed to make this reach the launcher: the script
already backgrounds `./retsurf` and does `wait "$app"` on it (see its
closing lines) — a self-initiated `process::exit(0)` from the quit chord
makes that `wait` return immediately, same as it already would for a crash
or a `kill`, and `launch.sh` then falls off its own end right after running
`swap_tuning_stop`. Whatever process forked/execs `launch.sh` itself (the
grid launcher, directly or through its own autostart chain) sees *that*
process exit the moment retsurf does — standard fork/wait launcher-grid
behavior, nothing bespoke to add on this side of it.

## `.desktop`: `Categories=Game;` for the grid launcher's own scan

`resources/retsurf.desktop` (the shared, generic entry for a normal desktop
menu/taskbar) ships `Categories=Network;WebBrowser;` — the categories a
*browser* belongs under, not a *game*. This board's custom launcher almost
certainly filters/groups its grid by `Categories=Game;` (the freedesktop.org
convention this kind of launcher would reasonably follow), so the shared
file was left untouched — editing it to `Game;` would be wrong for every
desktop install — and `retsurf.desktop` here is a new, device-specific entry
instead: `Categories=Game;`, `Exec=` pointed at `launch.sh` rather than the
bare binary (so the controller mapping, env hints and first-run config
install all still happen), and no `MimeType`/`%u` (a kiosk tile the grid
launcher starts with no arguments, not a file-manager association). Adjust
the `Exec=` path to wherever this directory actually lands on the image —
see the Install section below. `build-pizero2w.yml` now copies it into the
same packaged `retsurf-pizero2w.zip` as everything else here.

## 30 fps, not the panel's advertised 60

`[performance] max_fps = 30` in `config.toml` is pinned, not left at
`PerformanceConfig::default()` (also `30`, so behaviorally a no-op today) —
pinned so a later edit "fixing" this to `60` to match the HyperPixel's spec
sheet doesn't regress battery life by accident. Every frame is a full
720x720 CPU recomposite (`src/platform/window/software.rs`, this fork's only
rendering path), with no GPU compositor pass to amortize
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
  GPU is alive and in active use *for compositing* — software rendering
  above is still the right call regardless (it's about not doubling GPU
  memory pressure with an EGL/WebGL context of retsurf's own on top of what
  labwc already uses, a RAM argument, not a "no GPU exists" one; moot anyway
  now that this fork carries no such context at all — see the "GL/WebGL
  backend removed entirely" section below). The `SoftwareBackend` path
  (`src/platform/window/software.rs`) never requests `SDL_WINDOW_OPENGL` on
  its window in the first place (`build_window(video, config, false)`), so
  it cannot pick a GL-based SDL renderer even by accident — confirmed zero
  GL/EGL touch under labwc too.
- **Audio**: PipeWire. `launch.sh` now exports `SDL_AUDIODRIVER=pipewire`
  (Debian 12's SDL2 2.26 has a native backend for it).

## Files

| File | Purpose |
| --- | --- |
| `config.toml` | Copied to the data dir on first run as `config.toml`. |
| `bindings.toml` | Copied to the data dir on first run; rebinds `zoom_in`/`zoom_out`/`zoom_reset` off the l2/r2 triggers this board doesn't have, and binds `start+select` to `quit` for the grid launcher (see the Input section and the START+SELECT section above). Every other gesture comes back from retsurf's own compiled-in defaults. |
| `fonts.conf.in` | Fontconfig template; `launch.sh` only installs it if the image's own fontconfig can't resolve a sans-serif font at all. `@FCCACHE@` is substituted with a writable cache path. |
| `retsurf.desktop` | Device-specific desktop entry with `Categories=Game;`, for the custom grid launcher to pick up as a tile — see the `.desktop` section above. Not installed by `launch.sh`; copy it wherever your launcher scans. |
| `launch.sh` | Example launcher: env vars, first-run config/bindings install, conditional fontconfig template, opt-in zram/swap tuning (`swap-tuning.on`). Adjust `gamedir`/controller mapping/autostart to your image. |
| `../../.github/workflows/build-pizero2w.yml` | Not in this directory, but builds and packages everything above into `retsurf-pizero2w.zip` on every nightly and tagged release — see the CI section below. |

## CI: `build-pizero2w.yml` is the only build workflow left

This repo used to aggregate six platforms' worth of build workflows
(desktop Linux/macOS/Windows, Android, and the PortMaster/Miyoo per-core
matrices) behind `nightly.yml`. All of that — `build-android.yml`,
`build-linux.yml`, `build-linux-armhf.yml`, `build-linux-arm.yml`,
`build-macos.yml`, `build-windows.yml`, and the now-unused
`.github/actions/arm-build-env` composite action they shared — has been
**deleted**: this fork targets the Raspberry Pi Zero 2 W GamerCard
exclusively, and none of those workflows ever produced a binary this board
should run (most of them explicitly pinned `--no-default-features --features
webgl` back to a GPU-featured build — a feature this fork has since removed
outright, see below). `build-pizero2w.yml` is simply plain `cargo build
--release` with `RUSTFLAGS: -C target-cpu=cortex-a53` (the board's CPU is
fixed and known), no feature flags at all (there being only one build left
to produce), no `ubuntu:20.04` glibc-floor container (that floor existed for
a decade of mismatched handheld firmwares, not this known, modern, single
target OS — Debian 12 bookworm, glibc 2.36 — where the plain
`ubuntu-22.04-arm` runner, glibc 2.35, is already an older floor than the
device).

It uploads two artifacts: `retsurf-pizero2w-bin` (the bare binary, CI-only,
14-day retention) and `retsurf-pizero2w` (the binary plus every file this
directory ships — `config.toml`, `bindings.toml`, `fonts.conf.in`,
`retsurf.desktop`, `launch.sh` — laid out exactly as the Install section
below copies them, ready to unzip straight into `/opt/retsurf/`). A tagged
release also zips the second one with a `.sha256` sidecar, and `nightly.yml`
— now trimmed to just `changed → pizero2w → publish`, with no other
platform's artifacts to assemble — builds and publishes it every night.

## GL/WebGL backend removed entirely

Deleting the other platforms' CI workflows (above) left the `webgl` Cargo
feature and the GL chrome backend it gated (`src/platform/window/gl.rs`)
with no CI job that ever built them in this repo — this board's own
`software` default never touched either. Rather than leave that as dead
weight nothing exercises, both were removed outright, along with everything
that existed only to feed them:

- **`webgl` feature and the GL chrome backend**: `src/platform/window/gl.rs`
  (`GlBackend`, SDL2's own GL/GLES context), `src/platform/render/sdl.rs`
  (`SdlRenderingContext`, the FBO it rendered into), and
  `src/platform/render/webgl.rs`/`webgl_off.rs` (the EGL composite path
  WebGL needed to reach the screen) are all deleted. `src/platform/window/
  mod.rs`'s `build_backend()` no longer picks between GL and software at
  runtime — it only ever builds `SoftwareBackend` now, since that was
  already the only thing this board's `config.toml` ever asked for.
- **`[display] use_gles` / `software_render`**: both config fields removed
  from `src/config/display.rs` (and the "Use OpenGL ES" Settings row) — with
  no GL backend left to pick between, a config knob that could only ever
  mean "use the one renderer that exists" is confusion, not a setting.
  `config.toml` below no longer sets either.
- **Android (`android/`)**: `android/lib/Cargo.toml` depended on
  `retsurf = { ..., features = ["webgl"] }` directly — Mali/Adreno/PowerVR
  phones have no software-rendering fallback build upstream ever shipped, so
  removing `webgl` left that crate permanently unbuildable. Since Android
  was already out of scope for this repo (the "other devices are discarded"
  decision above covers it too), the whole `android/` directory and the
  `[workspace]` entry for it are gone rather than left half-broken. The
  scattered `#[cfg(target_os = "android")]` blocks still inside `src/`
  (15 files) are left exactly as they were: harmless, already never compiled
  by anything this repo builds, and out of scope for this pass — only the
  one crate that structurally *required* `webgl` to exist is gone.
- **`tests/run_pages.py`**: the `webgl` and `webgl2-features` cases (and
  their `tests/pages/webgl*.html`/`.js` fixtures) are deleted — they can
  never produce a context to probe once `servo/webgl` isn't compiled in at
  all, not just off by default. `.github/workflows/check.yml` dropped
  `--no-default-features --features webgl` from its build/test/clippy steps
  as a result: it now validates the exact `software` default
  `build-pizero2w.yml` ships, rather than a GPU path this repo can no
  longer produce.

Left untouched on purpose: `tools/arm64/build.sh`'s `--features webgl` and
`tools/armhf/build.sh`'s `--features software` invocations (both preserved,
per the "other devices discarded" decision, purely as reference material for
a future separate project) will no longer run against *this* repo's
`Cargo.toml` — neither feature exists here anymore. That is an accepted
consequence of preserving those two directories unedited, not an oversight;
flagging it here since it is the one place their contents and this repo's
current `Cargo.toml` now disagree.

## Updates: the console's own store, not retsurf's in-app updater

This board does not use `src/update`'s self-update path at all — updates are
a `.deb` the console's own software store installs when a new package is
published, outside retsurf entirely. `config.toml`'s `[update] auto_check =
false` turns off the in-app background check so it never contradicts the
store by announcing an update of its own (there also is no "update" for it
to find any more in the sense that mattered before: `resolve_kind()`'s
generic fallback, `retsurf-linux-aarch64.zip`, was the universal
`build-linux-arm.yml` build — deleted above along with every other
non-pizero2w asset `nightly.yml` used to publish, so a manual check from
Settings > About no longer has a wrong, mismatched asset to offer; it has
none at all). `resolve_kind()` gaining a pizero2w-specific case is no longer
tracked as a follow-up here for the same reason: this board's updates don't
go through it, by design, not pending a fix.

## Install

**Easiest**: download `retsurf-pizero2w.zip` from a [release](../../releases)
(or the `retsurf-pizero2w` artifact off a `build-pizero2w.yml` Actions run)
and unzip it straight into `/opt/retsurf/` — it already contains the binary
plus all five files this directory ships, laid out ready to run
(`chmod +x /opt/retsurf/launch.sh` once, since zip doesn't always preserve
the executable bit). Point your grid launcher's scan at `retsurf.desktop`
separately (or copy it to wherever it expects entries, e.g.
`~/.local/share/applications/`) — it isn't installed automatically the way
`config.toml`/`bindings.toml` are, since `launch.sh` only ever touches its
own data dir, not the launcher's.

**Building it yourself** instead — on-device, or any arm64 Linux box:

```sh
mkdir -p /opt/retsurf
cp /path/to/retsurf /opt/retsurf/
cp packaging/pizero2w/config.toml /opt/retsurf/
cp packaging/pizero2w/bindings.toml /opt/retsurf/
cp packaging/pizero2w/fonts.conf.in /opt/retsurf/
cp packaging/pizero2w/retsurf.desktop /opt/retsurf/
cp packaging/pizero2w/launch.sh /opt/retsurf/ && chmod +x /opt/retsurf/launch.sh
```

The binary itself needs no feature flags at all: a plain `cargo build
--release` already produces the CPU-only binary this board runs — this
fork's only rendering path now, not merely its default (see the "GL/WebGL
backend removed entirely" section above and the repo root's `Cargo.toml`;
`.github/workflows/build-pizero2w.yml` is the CI job that builds exactly
this).

Unlike the PortMaster per-core matrix (`tools/arm64/build.sh`, kept only as
reference material per the "other devices discarded" decision above), which
had to produce one binary that ran on A35, A53 *and* A55 cores, this board's
CPU is fixed and known: a Cortex-A53 quad-core. Building directly on the
device (Debian 12 arm64) can safely tell rustc that, which a generic/
portable build does not:

```sh
RUSTFLAGS="-C target-cpu=cortex-a53" cargo build --release
```

Not added to the repo's `.cargo/config.toml`: that file's `rustflags` would
apply to every `aarch64-unknown-linux-gnu` build — this belongs in this
board's own build invocation (or a `RUSTFLAGS` export in a local build
script), not shared.

## Minor: `[experimental] webgl2` stays on even though WebGL can't run

`ExperimentalConfig::default()` (the "Balanced" preset, `src/config/experimental.rs`)
ships `webgl2 = true`. `servo/webgl` doesn't exist as a buildable feature in
this fork's `Cargo.toml` at all anymore (see the "GL/WebGL backend removed
entirely" section above), so `canvas.getContext('webgl2')` returns `null`
regardless of this preference — it's a no-op, not a bug: the flag only
governs whether the (never compiled) WebGL backend is *permitted*, not
whether it exists. **Left as-is here, on purpose**: it's a Servo runtime
preference, unrelated to the Cargo feature, and this preset already shipped
in this exact "on but inert" state before the feature was removed — flipping
it to `false` would only be cosmetic in the Settings screen, not a behavior
change either way.
