#!/bin/bash
# Install eco mode (j5-eco) and its Phosh quick-settings tile.
#
# Usage: scripts/setup-eco.sh root@<phone-ip> [ssh options...]
set -euo pipefail

TARGET="${1:?usage: $0 root@<phone-ip> [ssh options]}"
shift
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_DIR/sparse"
PLUGIN="$REPO_DIR/phosh-plugin/libphosh-plugin-eco-quick-setting.so"
PLUGINS_DIR=/usr/lib/aarch64-linux-gnu/phosh/plugins

[ -f "$PLUGIN" ] || docker run --rm --platform linux/arm64 -v "$REPO_DIR/phosh-plugin:/src" -w /src \
    debian:trixie bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    gcc libc6-dev make pkg-config libgtk-3-dev >/dev/null && make && chown $(id -u):$(id -g) *.so"

tar -C "$S" -cf - ./usr/local/sbin/j5-eco ./etc/systemd/system/j5-eco.service \
    ./etc/sudoers.d/j5-eco \
    | ssh "$@" "$TARGET" 'tar -C / --no-same-owner -xf -'
scp -q "$@" "$PLUGIN" "$REPO_DIR/phosh-plugin/eco-quick-setting.plugin" "$TARGET:$PLUGINS_DIR/"

ssh "$@" "$TARGET" 'set -e
chown root:root /etc/sudoers.d/j5-eco /etc/systemd/system/j5-eco.service
chmod 440 /etc/sudoers.d/j5-eco
visudo -cf /etc/sudoers.d/j5-eco
systemctl daemon-reload
systemctl enable j5-eco.service
/usr/lib/aarch64-linux-gnu/glib-2.0/gio-querymodules '"$PLUGINS_DIR"'
/usr/local/sbin/j5-eco status >/dev/null
# add the tile to the top-bar quick settings (takes effect after Phosh restarts)
bus="unix:path=/run/user/$(id -u droidian)/bus"
qs=$(sudo -u droidian DBUS_SESSION_BUS_ADDRESS="$bus" gsettings get sm.puri.phosh.plugins quick-settings)
case "$qs" in *eco-quick-setting*) ;; *)
    qs=$(echo "$qs" | sed "s/^@as \\[\\]$/[]/; s/\\]$/, '"'"'eco-quick-setting'"'"']/; s/\\[, /[/")
    sudo -u droidian DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set sm.puri.phosh.plugins quick-settings "$qs" ;;
esac'
