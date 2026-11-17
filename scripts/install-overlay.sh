#!/bin/bash
# Copy the device overlay (sparse/) onto a running Droidian J5 and enable it.
#
# Usage: scripts/install-overlay.sh root@<phone-ip> [ssh options...]
#   e.g. scripts/install-overlay.sh root@10.15.19.82 -i ~/.ssh/j5droidian_ed25519
#
# Needs root SSH access on the phone (see README, "Pierwszy dostęp").
set -euo pipefail

TARGET="${1:?usage: $0 root@<phone-ip> [ssh options]}"
shift
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Pi-hole files are installed by scripts/setup-pihole.sh, not here.
tar -C "$REPO_DIR/sparse" --exclude='./etc/pihole' \
    --exclude='./etc/NetworkManager/dnsmasq-shared.d' \
    --exclude='./etc/sudoers.d' \
    --exclude='./usr/local/sbin/j5-pihole-toggle' \
    --exclude='./usr/local/bin/pihole-toggle-ui' \
    --exclude='./usr/share/applications/pihole-toggle.desktop' \
    -cf - . | ssh "$@" "$TARGET" 'tar -C / --no-same-owner -xf -'

ssh "$@" "$TARGET" 'set -e
chown root:root /etc/udev/rules.d/*.rules /etc/systemd/system/j5-*.service
systemctl daemon-reload
# older name of the USB network service used during porting
if systemctl list-unit-files j5-usbnet-debug.service >/dev/null 2>&1; then
    systemctl disable j5-usbnet-debug.service 2>/dev/null || true
    rm -f /etc/systemd/system/j5-usbnet-debug.service /usr/local/bin/j5-usbnet-debug.sh
fi
systemctl enable j5-cpu-hotplug.service j5-wifi-apsta-firmware.service j5-usbnet.service
[ -x /usr/local/bin/busybox ] || echo "WARNING: /usr/local/bin/busybox missing (needed by j5-usbnet.sh, see README)"
# camera V4L2 nodes crash the kernel when probed by GStreamer (see README)
dpkg-divert --local --rename \
    --divert /usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstvideo4linux2.so.disabled-j5 \
    --add /usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstvideo4linux2.so
/usr/local/sbin/j5-patch-phoc || true
udevadm control --reload
echo "overlay installed - reboot the phone"'
