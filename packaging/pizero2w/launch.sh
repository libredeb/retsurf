#!/bin/sh
# Raspberry Pi Zero 2 W / GamerCard launcher. Adjust `gamedir`'s assumptions,
# the controller mapping and the autostart hook (systemd unit / labwc
# autostart / getty autologin) to your image. Covers: first-run config and
# bindings install, the fallback fontconfig template, the verified gamepad
# mapping, Wayland/PipeWire env, and opt-in zram/swap tuning — see
# packaging/pizero2w/README.md for the reasoning behind each.
gamedir=$(cd "$(dirname "$0")" && pwd)
cd "$gamedir" || exit 1

datadir="$gamedir/data"
mkdir -p "$datadir" "$gamedir/downloads"

# `data/` is the user's, so the shipped default is installed, never overwritten.
[ -f "$datadir/config.toml" ] || cp "$gamedir/config.toml" "$datadir/config.toml"

# Rebinds zoom_in/zoom_out/zoom_reset off the l2/r2 triggers this board
# doesn't have (see bindings.toml's own header and the README's Input
# section) — every other gesture is left for retsurf's own
# merge_missing_defaults to fill in from its compiled-in defaults.
[ -f "$datadir/bindings.toml" ] || cp "$gamedir/bindings.toml" "$datadir/bindings.toml"

export RETSURF_DATA_DIR="$datadir"
export RETSURF_DOWNLOAD_DIR="$gamedir/downloads"
export RETSURF_PANIC_FILE="$gamedir/retsurf-panic.log"
#export RETSURF_LOG_LEVEL=debug

# This board's VideoCore IV GPU only exposes GLES 2.x through its own driver —
# below WebRender/egui's GLES 3.0 floor — so retsurf's `webgl` build (the
# default; see Cargo.toml's `[features]` comment) is not meant to drive the
# real GPU here at all. LIBGL_ALWAYS_SOFTWARE forces Mesa's own `llvmpipe` CPU
# rasterizer underneath instead, giving a full, spec-compliant GL/EGL context
# with no real GPU involved — WebGL and every GL blend mode a page can ask for
# work, just CPU-bound. This is deliberately NOT retsurf's own
# `RETSURF_SOFTWARE=1` (the swgl `software` feature): on-device testing found
# swgl's blend-mode dispatch aborts the entire process on combinations outside
# its curated table, which Mesa's full GL implementation does not hit.
export LIBGL_ALWAYS_SOFTWARE=1

# The device runs labwc (a wlroots Wayland compositor) per its own launcher,
# so WAYLAND_DISPLAY is normally already in the environment and
# src/platform/startup.rs picks "wayland" on its own (it only overrides
# SDL_VIDEODRIVER when WAYLAND_DISPLAY is set and the var is otherwise unset).
# Export it explicitly only as a fallback: a custom launcher that execs
# retsurf from a systemd --user unit or a stripped shell often does NOT
# inherit the graphical session's WAYLAND_DISPLAY unless something has
# imported it (`systemctl --user import-environment WAYLAND_DISPLAY` or
# equivalent) — if retsurf logs "wayland" was not picked, uncomment this
# rather than chasing the session import:
#export SDL_VIDEODRIVER=wayland

# PipeWire is the audio/video server on this image. SDL >= 2.0.22 (Debian 12's
# libsdl2 is 2.26) has a native pipewire backend; without this it still works
# through pipewire-pulse's compatibility shim, just with one more layer.
export SDL_AUDIODRIVER=pipewire

# The Arduino Leonardo ("GamerCard custom gamepad") has no entry in SDL's
# bundled gamecontrollerdb — confirmed on-device: `js0` under
# /proc/bus/input/devices means the kernel's joydev already treats it as a
# joystick, not a keyboard, so WITHOUT this line
# `is_game_controller()` (src/event/handler.rs) returns false, SDL never
# opens it, and chrome input AND every web game's navigator.getGamepads()
# both get nothing — silently, no error anywhere. This mapping was
# previously generated and verified for this exact board (GUID
# 03000000412300003680000001010000, VID:PID 2341:8036).
#
# No `dpXXX` entries — on purpose, and not how this was first shipped. This
# nav disc has only two axes, so an earlier draft mapped `leftx`/`lefty`
# *and* `dpup`/`dpdown`/`dpleft`/`dpright` onto those same two axes, meaning
# every push past SDL's own (well below full-deflection) axis-to-button
# threshold also fired a synthetic D-pad button. `Gamepad::aim()`
# (src/event/gamepad.rs) merges the D-pad's digital ±1 *into* the analog
# stick vector it also reads (`(stick + dpad).clamp(-1, 1)`) — by design, for
# a real separate D-pad on a device with no stick at all — so on this board
# every meaningful push saturated the aim vector to exactly ±1 the instant it
# crossed that threshold, regardless of how far past it the disc actually
# travelled. `[controls] cursor_curve` (see the README section below) shapes
# values *between* 0 and ±1; it cannot do anything once the input is already
# pinned at ±1, which is exactly why changing it changed nothing. Dropping
# the `dpXXX` tokens stops SDL synthesizing those button presses at all, so
# `aim()` is now driven purely by the real, continuous `leftx`/`lefty` value
# — the only thing lost is hint mode's D-pad-press combo-letter shortcut
# (`[controls] hint_badges` below turns that off too, since there is nothing
# left to press it with).
export SDL_GAMECONTROLLERCONFIG="03000000412300003680000001010000,Arduino Leonardo,a:b0,b:b1,x:b3,y:b4,back:b10,start:b11,leftshoulder:b5,rightshoulder:b6,leftx:a0,lefty:a1,platform:Linux,"

# Raspberry Pi OS ships ca-certificates already, unlike the Miyoo firmwares
# this packaging convention started on — no SSL_CERT_FILE override needed
# here. Uncomment if your image is stripped down far enough to lack one:
#export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# Only reached if fontconfig genuinely cannot see a sans-serif family — a
# normal Raspberry Pi OS image (fontconfig + fonts-dejavu-core installed)
# never hits this branch, so it ships no font of its own either.
if ! fc-match sans-serif >/dev/null 2>&1; then
  fonts_conf="$datadir/fonts.conf"
  fccache="$datadir/fccache"
  mkdir -p "$fccache"
  if [ ! -s "$fonts_conf" ] || [ "$gamedir/fonts.conf.in" -nt "$fonts_conf" ]; then
    sed "s|@FCCACHE@|$fccache|g" "$gamedir/fonts.conf.in" > "$fonts_conf"
  fi
  export FONTCONFIG_FILE="$fonts_conf"
fi

# Swap tuning, off unless swap-tuning.on exists here — ported from
# packaging/portmaster/Retsurf.sh's battle-tested version (that one also
# juggles several CFWs' half-broken zram setups; Debian 12 needs none of
# that). System-wide and outlives this process, so check `zramctl` /
# `swapon --show` first: a stock Raspberry Pi OS / Debian image may already
# run its own zram-tools or systemd-zram-generator unit, and this would
# stack a second device on top rather than replace it.
SWAP_TUNING_ZRAM=""
SWAP_TUNING_CLUSTER=""
SWAP_TUNING_SWAPPINESS=""
SWAP_TUNING_MODULE=""

swap_tuning_add_zram() {
  total_mb=$1

  if [ ! -w /sys/class/zram-control/hot_add ]; then
    modprobe zram >/dev/null 2>&1 && SWAP_TUNING_MODULE=1
  fi
  [ -w /sys/class/zram-control/hot_add ] || return 0
  command -v mkswap >/dev/null && command -v swapon >/dev/null || return 0

  n=$(cat /sys/class/zram-control/hot_add 2>/dev/null) || return 0
  [ -n "$n" ] || return 0

  # Fastest to decompress wins: a page fault waits on it.
  for algo in lz4 lzo-rle lzo; do
    grep -qw "$algo" "/sys/block/zram$n/comp_algorithm" 2>/dev/null || continue
    echo "$algo" > "/sys/block/zram$n/comp_algorithm" 2>/dev/null && break
  done

  # zram lives in the RAM it stands in for, so size it from RAM, never a
  # constant — on the 512 MB Zero 2 W this lands around 340 MB.
  if ! echo $(( total_mb * 2 / 3 * 1024 * 1024 )) > "/sys/block/zram$n/disksize" 2>/dev/null; then
    echo "$n" > /sys/class/zram-control/hot_remove 2>/dev/null
    return 0
  fi

  # Outrank any swap the base image already runs, so new pages land in ours
  # (RAM-backed, lz4) and come back fast rather than off the SD/eMMC card.
  if mkswap "/dev/zram$n" >/dev/null 2>&1 && swapon -p 1100 "/dev/zram$n" 2>/dev/null; then
    SWAP_TUNING_ZRAM="$n"
    echo "retsurf: swap tuning on (zram$n, $(( total_mb * 2 / 3 )) MiB, $(sed 's/.*\[\(.*\)\].*/\1/' "/sys/block/zram$n/comp_algorithm"))"
  else
    echo "$n" > /sys/class/zram-control/hot_remove 2>/dev/null
  fi
}

swap_tuning_start() {
  [ -f "$gamedir/swap-tuning.on" ] || return 0

  total_mb=$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo 2>/dev/null)
  [ -n "$total_mb" ] && [ "$total_mb" -le 1536 ] || return 0

  swap_tuning_add_zram "$total_mb"

  [ -n "$SWAP_TUNING_ZRAM" ] || grep -q "^/" /proc/swaps 2>/dev/null || return 0

  # The default of 3 fetches eight pages a fault; zram decompresses each one.
  if [ -w /proc/sys/vm/page-cluster ]; then
    SWAP_TUNING_CLUSTER=$(cat /proc/sys/vm/page-cluster)
    echo 0 > /proc/sys/vm/page-cluster
  fi
  # Dropping a file page here means re-reading the binary off the SD/eMMC card.
  if [ -w /proc/sys/vm/swappiness ]; then
    SWAP_TUNING_SWAPPINESS=$(cat /proc/sys/vm/swappiness)
    echo 100 > /proc/sys/vm/swappiness
  fi
}

# On any exit, including a crash: a device left attached holds RAM, and a
# changed swappiness silently changes how everything else on the system
# behaves until reboot.
swap_tuning_stop() {
  [ -n "$SWAP_TUNING_CLUSTER" ] && echo "$SWAP_TUNING_CLUSTER" > /proc/sys/vm/page-cluster 2>/dev/null
  [ -n "$SWAP_TUNING_SWAPPINESS" ] && echo "$SWAP_TUNING_SWAPPINESS" > /proc/sys/vm/swappiness 2>/dev/null
  if [ -n "$SWAP_TUNING_ZRAM" ]; then
    if swapoff "/dev/zram$SWAP_TUNING_ZRAM" 2>/dev/null; then
      echo "$SWAP_TUNING_ZRAM" > /sys/class/zram-control/hot_remove 2>/dev/null
    else
      echo "retsurf: could not release zram$SWAP_TUNING_ZRAM; it stays until reboot"
      return 0
    fi
  fi
  [ -n "$SWAP_TUNING_MODULE" ] && modprobe -r zram >/dev/null 2>&1
  return 0
}

trap swap_tuning_stop EXIT
swap_tuning_start

./retsurf >> "$gamedir/log.txt" 2>&1 &
app=$!
trap 'kill -TERM "$app" 2>/dev/null' TERM INT HUP
wait "$app"
wait "$app" 2>/dev/null
