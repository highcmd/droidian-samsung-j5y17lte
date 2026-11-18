#!/bin/bash
# Install Pi-hole on the phone, wire it to the Wi-Fi hotspot and add the
# Phosh "Pi-hole" on/off launcher.
#
# Usage: scripts/setup-pihole.sh root@<phone-ip> [ssh options...]
#
# Runs the official Pi-hole installer (https://github.com/pi-hole/pi-hole,
# "automated install/basic-install.sh") in unattended mode on the phone.
set -euo pipefail

TARGET="${1:?usage: $0 root@<phone-ip> [ssh options]}"
shift
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
S="$REPO_DIR/sparse"
INSTALLER_URL="https://raw.githubusercontent.com/pi-hole/pi-hole/master/automated%20install/basic-install.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/basic-install.sh" "$INSTALLER_URL"
# Phosh quick-settings tile (phosh-plugin/), built for arm64 in Docker
PLUGIN="$REPO_DIR/phosh-plugin/libphosh-plugin-pihole-quick-setting.so"
[ -f "$PLUGIN" ] || docker run --rm --platform linux/arm64 -v "$REPO_DIR/phosh-plugin:/src" -w /src \
    debian:trixie bash -c "apt-get update -qq && apt-get install -y -qq --no-install-recommends \
    gcc libc6-dev make pkg-config libgtk-3-dev >/dev/null && make && chown $(id -u):$(id -g) *.so"

echo "Pi-hole installer sha256: $(sha256sum "$tmp/basic-install.sh" | cut -d' ' -f1)"

ssh "$@" "$TARGET" 'mkdir -p /etc/pihole /etc/NetworkManager/dnsmasq-shared.d'
tar -C "$S" -cf - ./etc/pihole/pihole.toml ./etc/pihole/adlists.list \
    ./etc/NetworkManager/dnsmasq-shared.d/10-pihole.conf \
    ./etc/sudoers.d/j5-pihole-toggle \
    ./usr/local/sbin/j5-pihole-toggle ./usr/local/bin/pihole-toggle-ui \
    ./usr/share/applications/pihole-toggle.desktop \
    | ssh "$@" "$TARGET" 'tar -C / --no-same-owner -xf -'
scp -q "$@" "$tmp/basic-install.sh" "$TARGET:/root/pihole-basic-install.sh"
PLUGINS_DIR=/usr/lib/aarch64-linux-gnu/phosh/plugins
scp -q "$@" "$PLUGIN" "$REPO_DIR/phosh-plugin/pihole-quick-setting.plugin" "$TARGET:$PLUGINS_DIR/"
scp -q "$@" "$REPO_DIR/pihole/allowlist.sql" "$TARGET:/root/pihole-allowlist.sql"

ssh "$@" "$TARGET" 'set -e
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends curl ca-certificates
bash /root/pihole-basic-install.sh --unattended
# Pi-hole listens on 5335, so the systemd-resolved stub can stay on port 53
rm -f /etc/systemd/resolved.conf.d/90-pi-hole-disable-stub-listener.conf
systemctl restart systemd-resolved
pihole-FTL sqlite3 /etc/pihole/gravity.db < /root/pihole-allowlist.sql
pihole -g
chmod 440 /etc/sudoers.d/j5-pihole-toggle
visudo -cf /etc/sudoers.d/j5-pihole-toggle
update-desktop-database /usr/share/applications || true
/usr/lib/aarch64-linux-gnu/glib-2.0/gio-querymodules /usr/lib/aarch64-linux-gnu/phosh/plugins
/usr/local/sbin/j5-pihole-toggle status >/dev/null
# add the tile to the top-bar quick settings (takes effect after Phosh restarts)
bus="unix:path=/run/user/$(id -u droidian)/bus"
qs=$(sudo -u droidian DBUS_SESSION_BUS_ADDRESS="$bus" gsettings get sm.puri.phosh.plugins quick-settings)
case "$qs" in *pihole-quick-setting*) ;; *)
    qs=$(echo "$qs" | sed "s/^@as \\[\\]$/[]/; s/\\]$/, '"'"'pihole-quick-setting'"'"']/; s/\\[, /[/")
    sudo -u droidian DBUS_SESSION_BUS_ADDRESS="$bus" gsettings set sm.puri.phosh.plugins quick-settings "$qs" ;;
esac
echo "Set the web UI password with: pihole setpassword"'
