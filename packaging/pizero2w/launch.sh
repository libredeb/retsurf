#!/bin/sh
# Raspberry Pi Zero 2 W launcher — stage 1 (resource trim) of the pizero2w
# device profile. Adjust GAMEDIR, the controller mapping and the autostart
# hook (systemd unit / .xinitrc / getty autologin) to your image; this script
# only covers what stage 1 needs: first-run config install and the
# fallback fontconfig template.
gamedir=$(cd "$(dirname "$0")" && pwd)
cd "$gamedir" || exit 1

datadir="$gamedir/data"
mkdir -p "$datadir" "$gamedir/downloads"

# `data/` is the user's, so the shipped default is installed, never overwritten.
[ -f "$datadir/config.toml" ] || cp "$gamedir/config.toml" "$datadir/config.toml"

export RETSURF_DATA_DIR="$datadir"
export RETSURF_DOWNLOAD_DIR="$gamedir/downloads"
export RETSURF_PANIC_FILE="$gamedir/retsurf-panic.log"
#export RETSURF_LOG_LEVEL=debug

# Usually autodetected on a vc4-kms-v3d Raspberry Pi OS image booting straight
# to the console (no X11/Wayland running). Force it only if SDL picks the
# wrong one — e.g. a dummy/x11 driver surviving from a desktop image:
#export SDL_VIDEODRIVER=kmsdrm

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

# Not `exec`: kept so a future stage (swap/zram tuning, like
# packaging/portmaster/Retsurf.sh) can clean up after the process exits.
./retsurf >> "$gamedir/log.txt" 2>&1 &
app=$!
trap 'kill -TERM "$app" 2>/dev/null' TERM INT HUP
wait "$app"
wait "$app" 2>/dev/null
