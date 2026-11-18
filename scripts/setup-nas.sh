#!/bin/bash
# Turn the phone into a small NAS: format the SD card (ext4), mount it on
# /srv/nas and share it over SMB (Samba + NetBIOS + WS-Discovery).
#
# Usage: NAS_PASSWORD=... scripts/setup-nas.sh root@<phone-ip> [ssh options...]
#
# DESTROYS everything on /dev/mmcblk1 (set FORMAT=0 to keep an already
# formatted card labelled "nas"). Guests get read-only access; user "nas"
# with NAS_PASSWORD can write.
set -euo pipefail

TARGET="${1:?usage: NAS_PASSWORD=... $0 root@<phone-ip> [ssh options]}"
shift
: "${NAS_PASSWORD:?set NAS_PASSWORD (password of the SMB user nas)}"
FORMAT="${FORMAT:-1}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

scp -q "$@" "$REPO_DIR/sparse/etc/samba/smb.conf" "$TARGET:/root/j5-smb.conf"
scp -q "$@" "$REPO_DIR/sparse/usr/local/sbin/j5-nas-firewall" "$TARGET:/usr/local/sbin/"
scp -q "$@" "$REPO_DIR/sparse/etc/systemd/system/j5-nas-firewall.service" "$TARGET:/etc/systemd/system/"

ssh "$@" "$TARGET" "FORMAT=$FORMAT bash -s" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --no-install-recommends e2fsprogs parted samba wsdd-server
[ -b /dev/mmcblk1 ] || { echo "no SD card (/dev/mmcblk1)" >&2; exit 1; }
if [ "$FORMAT" = 1 ]; then
    umount /srv/nas 2>/dev/null || true
    wipefs -a /dev/mmcblk1
    parted -s /dev/mmcblk1 mklabel gpt mkpart nas ext4 1MiB 100%
    udevadm settle
    # kernel 3.18 cannot mount the newer ext4 features enabled by default
    mkfs.ext4 -q -F -L nas -m 0 \
        -O ^metadata_csum,^metadata_csum_seed,^orphan_file,^64bit /dev/mmcblk1p1
fi
mkdir -p /srv/nas
grep -q "LABEL=nas" /etc/fstab || \
    echo "LABEL=nas /srv/nas ext4 defaults,noatime,nofail,x-systemd.device-timeout=10s 0 2" >> /etc/fstab
systemctl daemon-reload
# keep uploads off the rootfs when the card is missing
mountpoint -q /srv/nas || chattr +i /srv/nas
mount /srv/nas 2>/dev/null || mountpoint -q /srv/nas
id nas >/dev/null 2>&1 || useradd --system --home-dir /srv/nas --no-create-home --shell /usr/sbin/nologin nas
chown nas:nas /srv/nas && chmod 2775 /srv/nas
[ -f /etc/samba/smb.conf.orig ] || cp /etc/samba/smb.conf /etc/samba/smb.conf.orig
install -m 644 /root/j5-smb.conf /etc/samba/smb.conf && rm /root/j5-smb.conf
testparm -s >/dev/null 2>&1
chmod 755 /usr/local/sbin/j5-nas-firewall
# Windows resolves names over LLMNR (systemd-resolved answers with the
# hostname), so the hostname has to match the announced name J5NAS
hostnamectl set-hostname j5nas
grep -qw j5nas /etc/hosts || echo "127.0.1.1 j5nas" >> /etc/hosts
# Windows sees the WS-Discovery name, not the NetBIOS one
sed -i 's/^WSDD_PARAMS=.*/WSDD_PARAMS="-n J5NAS"/' /etc/wsdd-server/defaults
systemctl daemon-reload
systemctl enable --now j5-nas-firewall
systemctl enable smbd nmbd wsdd-server
systemctl restart smbd nmbd wsdd-server
REMOTE

printf '%s\n%s\n' "$NAS_PASSWORD" "$NAS_PASSWORD" | ssh "$@" "$TARGET" 'smbpasswd -s -a nas >/dev/null'
echo "NAS ready: smb://<phone-ip>/nas (guest read-only, user nas read-write)"
