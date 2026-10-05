<p align="center">
  <img src="resources/images/retsurf-banner.png" alt="retsurf" width="420">
</p>

<div align="center">
  <a href="https://github.com/mxmgorin/retsurf/releases/latest"><img src="https://img.shields.io/github/v/release/mxmgorin/retsurf?style=flat-square&labelColor=16171a&color=3fb8a0&label=release&cacheSeconds=180" alt="Latest release"></a>
  <a href="https://github.com/mxmgorin/retsurf/releases/tag/nightly"><img src="https://img.shields.io/badge/dynamic/regex?url=https%3A%2F%2Fapi.github.com%2Frepos%2Fmxmgorin%2Fretsurf%2Freleases%2Ftags%2Fnightly&search=%22published_at%22%3A%22(%5Cd%7B4%7D-%5Cd%7B2%7D-%5Cd%7B2%7D)&replace=%241&label=nightly&style=flat-square&labelColor=16171a&color=3fb8a0&cacheSeconds=3600" alt="Nightly build date"></a>
  <a href="https://github.com/mxmgorin/retsurf/releases"><img src="https://img.shields.io/github/downloads/mxmgorin/retsurf/total?style=flat-square&labelColor=16171a&color=3fb8a0&label=downloads&cacheSeconds=180" alt="Downloads"></a>
  <!-- The check workflow, not a platform build: it is the one a push and a pull request run, and it carries the tests and clippy. -->
  <a href="https://github.com/mxmgorin/retsurf/actions/workflows/check.yml"><img src="https://img.shields.io/github/actions/workflow/status/mxmgorin/retsurf/check.yml?branch=main&style=flat-square&labelColor=16171a&color=3fb8a0&logo=githubactions&logoColor=white&label=ci&cacheSeconds=180" alt="CI"></a>
</div>

<p align="center">
  <a href="https://retsurf.mxmgorin.dev/">Website</a> &middot;
  <a href="#install">Install</a> &middot;
  <a href="docs/CONFIGURATION.md">Docs</a> &middot;
  <a href="https://github.com/mxmgorin/retsurf/discussions">Discussions</a>
</p>

retsurf is a web browser written in Rust and built with [Servo](https://servo.org/) and [SDL2](https://www.libsdl.org/). It aims to provide a full-featured web experience while staying lightweight and portable. It has gamepad- and keyboard-friendly controls for browsing and gaming-specific features like remappable input.

> **This fork.** This tree targets exactly one board — the Raspberry Pi Zero 2 W GamerCard
> handheld — and has dropped every other platform the upstream project supports (desktop
> Linux/macOS/Windows, Android, PortMaster handhelds, the Miyoo Mini). See
> [`packaging/pizero2w/README.md`](packaging/pizero2w/README.md) for the device build; the
> [upstream project](https://github.com/mxmgorin/retsurf) is where the other platforms live.

> **Work in progress.** Early development — expect bugs.

## Screenshots

| Start page | Browsing | Link hints | Keyboard |
|:---:|:---:|:---:|:---:|
| ![The built-in start page: the retsurf banner over a search field and a speed-dial grid of pinned sites, tinted after their site icons](resources/images/retsurf-start-page.png) | ![Hacker News rendered by Servo in its mobile layout, the toolbar above it](resources/images/retsurf-page.png) | ![Vimium-style hints over a Wikipedia article, each link labeled with the gamepad buttons that open it](resources/images/retsurf-hints.png) | ![The on-screen keyboard raised under the start page's search field, which shows what has been typed](resources/images/retsurf-keyboard.png) |

| Quick Access | Quick Menu | Reader view | Settings |
|:---:|:---:|:---:|:---:|
| ![Quick Access at the right edge over Hacker News: enter game mode, enter reader view, bookmark, page theme](resources/images/retsurf-quick-access.png) | ![Quick Menu at the left edge: home, tabs, bookmarks, history, downloads, settings and quit](resources/images/retsurf-quick-menu.png) | ![A Wikipedia article stripped to its text by reader view](resources/images/retsurf-reader.png) | ![The settings overlay on its Browser tab: home page, search URL, user agent, zoom, theme and the experimental web features](resources/images/retsurf-settings.png) |

| Game mode | Input map | Controls | Forced dark |
|:---:|:---:|:---:|:---:|
| ![Quick Access over the WebGL racer HexGL mid-race, the browser chrome hidden: view, the input map in use, the on-screen keyboard and exit](resources/images/retsurf-game-mode.png) | ![The input map editor: each stick direction and gamepad button with the key or mouse action it sends to the game](resources/images/retsurf-input-map.png) | ![The button bindings: each browser action with its gamepad and keyboard gestures](resources/images/retsurf-controls.png) | ![Lobsters, a light site with no dark theme, inverted by forced dark](resources/images/retsurf-forced-dark.png) |

## Features

- **Gamepad-first navigation**<br>
  The browser is fully navigable with a gamepad or keyboard, with a virtual cursor, Vimium-style link hints, and an on-screen keyboard as a grid or a wheel.

- **Customizable browser controls**<br>
  Every browser action can be rebound in-app, with support for tap, hold, and chord.

- **Game mode**<br>
  Hides the browser chrome and routes input to the page, with an in-app editor for input maps that turn buttons and sticks into keys, mouse, or raw gamepad input.

- **Web games**<br>
  WebGL 2, the Gamepad API, Web Audio, and IndexedDB, plus compatibility shims that let Emscripten exports from itch.io run.

- **Tabs, bookmarks, history, and downloads**<br>
  Everything lives in one full-screen menu. Downloads run in the background with progress and cancellation and a toolbar chip for active downloads.

- **Real page zoom**<br>
  Reflows the layout rather than simply magnifying it, with 50–300% zoom steps. Zoom is per-tab.

- **Reader view**<br>
  Strips pages down to their articles using Mozilla's [Readability](https://github.com/mozilla/readability). Runs in place, so it also works with logged-in and dynamically rendered pages.

- **Dark web pages**<br>
  Uses sites' own dark themes through `prefers-color-scheme`, or forces a dark appearance by inverting pages that don't provide one.

- **Ad & tracker blocking**<br>
  Network-level blocking powered by Brave's [`adblock-rust`](https://github.com/brave/adblock-rust), using EasyList and EasyPrivacy.

- **In-app updates**<br>
  Checks GitHub for updates, displays release notes, and installs updates in place on Linux. Supports stable, beta, and nightly channels.

- **Audio and video**<br>
  A custom Servo media backend provides audio and video playback. Supports direct media files and embedded players, but not streaming sites that require MSE.

- **No display server required**<br>
  SDL2 draws through whatever video backend the firmware ships. X11 and Wayland are optional, not required.

- **Software rendering**<br>
  swgl (WebRender's CPU rasterizer) draws the page, SDL's own renderer draws the chrome —
  this fork's only rendering path, chosen for a board with no GPU path worth spending RAM
  on.

## Install

This fork ships as a `.deb` built by `build-pizero2w.yml`, installed through the
GamerCard console's own software store — retsurf never updates itself on this board. See
[`packaging/pizero2w/README.md`](packaging/pizero2w/README.md) for the device build and
what ships beside the binary.

## Building

`cargo build --release`, once Servo's build dependencies are installed. See **[Building
from source](docs/BUILDING.md)** for the prerequisites and the device build.

## Configuration

Files are stored in the user data directory (`SDL_GetPrefPath`, e.g. `~/.local/share/mxmgorin/retsurf/` on Linux).
Templates with the defaults are written on first run. See **[Configuration](docs/CONFIGURATION.md)** for all options, **[Controls](docs/CONTROLS.md)** for bindings and Game Mode input maps, and **[Command line](docs/CLI.md)** for arguments and environment variables.

## How to help

If you find the project useful, here is how you can help:

- **Tell other people about it.** Sharing the project helps it reach more users.
- **Report bugs and request features** in [Issues](https://github.com/mxmgorin/retsurf/issues). Feedback is welcome.
- **Star the repo.** It helps the project get noticed and keeps me motivated.
- **[Buy me a coffee](https://ko-fi.com/mxmgorin)** on Ko-fi.

## Credits

- Web rendering by [Servo](https://servo.org)
- [SDL2](https://libsdl.org) through [rust-sdl2](https://github.com/Rust-SDL2/rust-sdl2)
  for window, input and audio
- [egui](https://github.com/emilk/egui) draws every overlay, with icons from
  [Phosphor](https://phosphoricons.com/)
- Blocking by Brave's [adblock-rust](https://github.com/brave/adblock-rust), over
  [EasyList](https://easylist.to/) and EasyPrivacy
- Reader view by Mozilla's [Readability](https://github.com/mozilla/readability)
- Media by [Symphonia](https://github.com/pdeljanov/Symphonia) and
  [openh264](https://github.com/ralfbiedert/openh264-rs) over Cisco's codec
- TLS by [rustls](https://github.com/rustls/rustls)
- SDL2 for the Miyoo Mini by [Steward Fu](https://github.com/steward-fu/sdl2)
