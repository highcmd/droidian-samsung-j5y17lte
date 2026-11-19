# Droidian on Samsung Galaxy J5 (2017) — `j5y17lte`

A port of [Droidian](https://droidian.org) (Debian for phones, Phosh + Halium)
to the **Samsung Galaxy J5 (2017), SM-J530F** (Exynos 7870).

This repository contains everything needed to reproduce the port from scratch:
kernel patches including the Droidian packaging, a rootfs overlay with the
device-specific fixes, helper scripts, and a Wi-Fi hotspot setup with Pi-hole.

> ⚠️ Hobby project. Flashing may leave you restoring the phone with
> Odin/Heimdall. Back up the `BOOT`, `RECOVERY` and **`EFS`** (IMEI!)
> partitions before you start.

## Status

| Feature | State | Notes |
|---|---|---|
| Boot to Phosh | ✅ | about 60 s to the lock screen |
| Display, touch (portrait and landscape) | ✅ | needs the phoc patch (see below) |
| Screen rotation | ✅ | |
| Voice calls | ✅ | |
| Mobile data (LTE) | ✅ | see "Mobile data" |
| Wi-Fi (client) | ✅ | |
| Wi-Fi hotspot | ✅ | SoftAP firmware, 2.4 GHz channel 6 |
| Pi-hole for the hotspot | ✅ | tile in the quick settings + launcher in the app grid |
| microSD card / SMB NAS | ✅ | SDR104; ext4 without features 3.18 lacks |
| SSH (USB and Wi-Fi) | ✅ | key-only |
| All 8 CPU cores | ✅ | hotplug governor disabled |
| Camera | ❌ | V4L2 nodes blocked — the FIMC-IS driver causes a kernel panic |
| Media audio, SMS, Bluetooth, GPS, sensors | ❓ | not tested (bluebinder does not start) |
| Web browser | ⚠️ | works, but 2 GB of RAM is little for Firefox |

## Device

| | |
|---|---|
| Model | SM-J530F (`j5y17lte`) |
| SoC | Exynos 7870, 8× Cortex-A53, Mali-T830 |
| RAM / storage | 2 GB / 16 GB eMMC |
| Bootloader | Samsung S-boot, flashing via Odin/Heimdall, UPPER-CASE partition names (`BOOT`, `VENDOR`, `USERDATA`) |
| `BOOT` partition | **32 MiB** |
| Android base | LineageOS 17.1 (Android 10, API 29), `VENDOR` partition (Treble) |
| Kernel | 3.18.140, [samsungexynos7870/android_kernel_samsung_exynos7870](https://github.com/samsungexynos7870/android_kernel_samsung_exynos7870) branch `simple_q_permissive` |
| Droidian | 101 (trixie), `api29` rootfs |

Boot image parameters (from postmarketOS pmaports, `device-samsung-j5y17lte`):
page size 2048, base `0x10000000`, kernel `0x8000`, ramdisk `0x01000000`,
tags `0x100`, header v0, separate `dt.img` in the Exynos `DTBH` format.

## Repository layout

```
kernel/patches/     patches on top of the kernel base (Droidian packaging + fixes)
sparse/             files overlaid on the Droidian rootfs (same layout as adaptation packages)
pihole/             SQL statement adding the allowlist subscription
phosh-plugin/       "Pi-hole" quick-settings tile for Phosh 0.49 (C, GTK 3)
scripts/
  build-kernel.sh     clones the kernel, applies the patches, builds .debs and boot.img in Docker
  install-overlay.sh  installs sparse/ on a running phone over SSH
  setup-pihole.sh     installs Pi-hole and wires it to the hotspot
  setup-nas.sh        formats the SD card and shares it over SMB
```

## Installing from scratch

### 0. Requirements

* Phone with an unlocked bootloader (OEM unlock), **TWRP** and LineageOS 17.1
  installed (the Android 10 `VENDOR` partition is required).
* Linux host with `adb`, `docker`, `git`.
* About 6 GB of free space on the phone's data partition.

### 1. Backup (in TWRP)

```sh
mkdir backup
for p in BOOT RECOVERY EFS CPEFS PARAM; do
  adb exec-out "dd if=/dev/block/by-name/$p 2>/dev/null" > backup/$p.img
done
```

Restoring Android = flashing `BOOT.img` back.

### 2. Kernel

```sh
scripts/build-kernel.sh            # output: build/boot.img and build/packages/*.deb
```

The build runs in the `quay.io/droidian/build-essential` container (Android
gcc 4.9). The script checks that `boot.img` fits into 32 MiB.

### 3. Droidian rootfs

Download `droidian-OFFICIAL-phosh-phone-rootfs-api29-arm64-*.zip` from
[droidian-images/droidian](https://github.com/droidian-images/droidian/releases).
`adb sideload` in TWRP **does not work** (the installer needs random access to
the zip, which the sideload FUSE does not provide), so install manually, doing
what the installer would do:

```sh
unzip droidian-*.zip data/rootfs.img
adb push data/rootfs.img /data/rootfs.img          # in TWRP
adb shell 'e2fsck -fy /data/rootfs.img; resize2fs -f /data/rootfs.img 8G;
           ln -s /halium-system/var/lib/lxc/android/android-rootfs.img /data/android-rootfs.img'
```

`rootfs.img` is a sparse file that grows as data is written — **the data
partition must keep free space** (see "Known issues").

### 4. First access (USB network)

The kernel uses the legacy `android_usb` gadget (not configfs) and Droidian
does not configure it on its own. Before flashing the kernel, mount the rootfs
in TWRP and add the USB network service plus a static busybox (it is in the
rootfs zip as `tools/busybox`):

```sh
adb shell 'mkdir -p /r && mount -o loop /data/rootfs.img /r'
unzip droidian-*.zip tools/busybox
adb push tools/busybox /r/usr/local/bin/busybox
adb push sparse/usr/local/bin/j5-usbnet.sh /r/usr/local/bin/
adb push sparse/etc/systemd/system/j5-usbnet.service /r/etc/systemd/system/
adb shell 'chmod 755 /r/usr/local/bin/busybox /r/usr/local/bin/j5-usbnet.sh
  ln -s /etc/systemd/system/j5-usbnet.service /r/etc/systemd/system/sysinit.target.wants/
  mkdir -p /r/root/.ssh'
adb push ~/.ssh/your_key.pub /r/root/.ssh/authorized_keys
adb shell 'chmod 600 /r/root/.ssh/authorized_keys; umount /r'
```

The phone gets `10.15.19.82`, the host gets a DHCP address from
`10.15.19.100–110`. The SSH server has to be installed after the first boot
(`apt install openssh-server`, over Wi-Fi or mobile data) — until then there is
only the network link. The overlay configures SSH for key-only login.

### 5. Flashing the kernel (in TWRP)

```sh
adb push build/boot.img /tmp/boot.img
adb shell 'dd if=/tmp/boot.img of=/dev/block/by-name/BOOT bs=1M; sync'
adb reboot
```

### 6. Device overlay

```sh
scripts/install-overlay.sh root@10.15.19.82 -i ~/.ssh/your_key
```

After a reboot Phosh should come up. The lock screen PIN and the password of
the `droidian` user (also used by `sudo`) are **1234** — change them with
`passwd`.

### 7. Hotspot + Pi-hole (optional)

```sh
scripts/setup-pihole.sh root@10.15.19.82 -i ~/.ssh/your_key
ssh root@10.15.19.82 pihole setpassword
```

### 8. SD card NAS (optional)

**Erases the SD card.**

```sh
NAS_PASSWORD='choose-one' scripts/setup-nas.sh root@10.15.19.82 -i ~/.ssh/your_key
```

## Problems found and how they were solved

Listed roughly in the order they showed up during porting. This section is the
most valuable part of the repository — most of these are not documented
anywhere else.

### Kernel and boot

| Problem | Cause | Fix |
|---|---|---|
| Parameters from `boot.img` never reach the kernel | **S-boot ignores the cmdline in the boot.img header** and passes its own (including `console=ram`) | the Droidian cmdline lives in `CONFIG_CMDLINE` (`droidian/j5y17lte.config`); `drivers/of/fdt.c` changed so that `CONFIG_CMDLINE` is appended **after** the bootloader arguments and takes precedence |
| `run-init: opening console: No such device`, systemd never starts | `console=ram` from the bootloader | `console=tty0` + `CONFIG_VT=y` (as above) |
| 36 MB `boot.img` > 32 MiB partition | `Image` is 19 MB, the Halium initramfs 17 MB | initramfs without `udev/hwdb.d`, LZMA compression (`CONFIG_RD_LZMA`), size check in `debian/rules` |
| No `dt.img` | the Droidian snippet only runs `make dtbs` | `debian/rules` runs `make dtb.img` (dtbtool_exynos) → `KERNEL_PREBUILT_DT` |
| initramfs cannot find the `vendor` partition | Samsung uses UPPER-CASE partition names | udev rule in the initramfs and in the rootfs adding lower-case aliases (`61-samsung-lowercase-partlabels.rules`) |
| Android container (LXC) fails: `Failed to prepare new devpts instance` | 3.18 kernel | `CONFIG_DEVPTS_MULTIPLE_INSTANCES=y` |
| systemd ≥ 256 vs cgroup v1 | 3.18 has no cgroup2 | `systemd.unified_cgroup_hierarchy=0 SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1` |
| Old toolchain / host | GCC 10+ and no ccache | patches for `dtc` (`yylloc`) and optional `ccache` in the Makefile |

### Rootfs / userspace

| Problem | Cause | Fix |
|---|---|---|
| Boot hangs at the logo, journald eats the CPU | **feedback loop**: journald reads kmsg → queries the power supply in sysfs → the `s2mu005` driver writes debug output to kmsg → … | `ReadKMsg=no` in `journald.conf.d/10-j5-persistent.conf`; dropped `systemd.journald.forward_to_kmsg` |
| phoc: `failed to get hwcomposer service` | `/dev/hwbinder`, `/dev/vndbinder` with mode `0600` | `69-android-system.rules` (generated from the system `ueventd.rc`) + `70-j5y17lte.rules` (from vendor) |
| Kernel panic ~60 s after the session starts | **GStreamer (`gst-plugin-scanner`) and Firefox (`gfxtest`) open the FIMC-IS camera V4L2 nodes** → NULL dereference in the driver / sysmmu | `fimc-is` patch (querycap) + `72-j5-v4l2-root-only.rules` (root-only, **without** the `uaccess` tag, otherwise logind grants the session an ACL) + disabled `libgstvideo4linux2.so` plugin (`dpkg-divert`) |
| Gestures do not work, "system too slow" | Samsung sensors are input devices and flood libinput | `71-j5-ignore-sensor-inputs.rules` (`LIBINPUT_IGNORE_DEVICE`) |
| Only 4 of 8 cores | the hotplug governor takes cores offline, and zswap fails to allocate its compressor when bringing them back | `j5-cpu-hotplug.service` keeps all cores online |
| Touch does not follow rotation, the scale in `phoc.ini` is ignored | the HWC2On1 adapter numbers the panel from 1 → the output is called **`HWCOMPOSER-2`**, while Droidian's phoc only treats `HWCOMPOSER-1` as built-in | `j5-patch-phoc` (same-length string replacement in the binary) + an APT hook re-applying it after upgrades; `phoc.ini` for `HWCOMPOSER-2` (scale 2). A proper fix belongs in [droidian/phoc](https://github.com/droidian/phoc) (`g_str_has_prefix(name, "HWCOMPOSER-")`) |
| No USB network | `android_usb` instead of configfs | `j5-usbnet.service` |

### Mobile data

When mobile data is enabled, Phosh creates a NetworkManager profile pinned to
the SIM's ICCID, but NM fails to read the SIM object from oFono
(`No SIM object available`) and considers the profile incompatible — the
switch stays "off". Fix:

```sh
nmcli -t -f UUID,TYPE con show | grep gsm          # delete duplicates
nmcli con modify <uuid> gsm.sim-id "" gsm.sim-operator-id "" connection.autoconnect yes
nmcli con up <uuid>
```

### Hotspot

* The `bcmdhd` driver with the "Station/P2P" firmware refuses to start an AP
  (`Failed to set beacon parameters`). The **SoftAP** firmware
  (`/vendor/etc/wifi/bcmdhd_apsta.bin_blob`) is needed; it also handles client
  mode. `j5-wifi-apsta-firmware.service` loads it (the driver appends `_blob`
  by itself).
* "Phosh Hotspot" profile: `802-11-wireless.band bg`, `channel 6`, `pmf disable`.
* After the AP is stopped the driver stays busy (`SCAN-FAILED ret=-16`) and the
  next start fails. The `90-j5-hotspot-recover` dispatcher script power-cycles
  the radio. **After turning the hotspot off, wait about 30–40 s before turning
  it on again.**
* **Kernel panic when the hotspot is started during a Wi-Fi scan.** With the
  AP+STA firmware P2P is unsupported and `cfg->p2p` stays NULL; the "scan
  aborted" event that follows the switch to AP mode dereferenced it in
  `wl_escan_handler()` / `wl_notify_escan_complete()` and the phone rebooted.
  Fixed by `0010-bcmdhd-fix-NULL-deref-of-cfg-p2p-on-aborted-scan.patch`.
  The previous boot's kernel log is in `/proc/last_kmsg`.
* **No Wi-Fi networks after turning the hotspot off.** wpa_supplicant scans on
  the AP interface; the driver accepted that scan but never reported it done,
  so every later scan failed with `-EBUSY` until reboot. Fixed by
  `0011-bcmdhd-complete-scan-requests-ignored-on-the-SoftAP-.patch`.

### Pi-hole

* Pi-hole v6 (FTL) listens on **127.0.0.1:5335**; NetworkManager's hotspot
  dnsmasq forwards client queries to it (`dnsmasq-shared.d/10-pihole.conf`,
  with its own cache disabled so the toggle takes effect immediately). The
  phone's own DNS is **not** filtered.
* Web UI: `http://10.42.0.1:8080/admin` (from a device on the hotspot).
* Toggle: the **"Pi-hole"** tile in the quick settings (pull down the top
  bar), the **"Pi-hole"** launcher in the app grid, or
  `sudo j5-pihole-toggle on|off|status|toggle`.
* Blocklists (`sparse/etc/pihole/adlists.list`, about 435k domains):
  * [StevenBlack hosts](https://github.com/StevenBlack/hosts)
  * [HaGeZi Pro](https://github.com/hagezi/dns-blocklists)
  * [KADhosts](https://github.com/FiltersHeroes/KADhosts) — Polish
  * [CERT Polska warning list](https://hole.cert.pl/) — Polish phishing and scam domains
  * [Polish Filters (MajkiIT)](https://github.com/MajkiIT/polish-ads-filter)
* Allowlist: [anudeepND/whitelist](https://github.com/anudeepND/whitelist)
  (domains needed by popular services).
* The Pi-hole installer disables the `systemd-resolved` stub on port 53 — not
  needed here (port 5335); `setup-pihole.sh` restores the stub.

### SD card NAS

* The card is formatted as ext4 and mounted on `/srv/nas` (`LABEL=nas`,
  `nofail`). e2fsprogs 1.47 enables `metadata_csum`, `orphan_file` and `64bit`
  by default; kernel 3.18 refuses to mount such a file system, so they are
  turned off.
* The bare `/srv/nas` directory is immutable (`chattr +i`), so nothing is
  written to the rootfs when the card is missing.
* Samba share **`nas`** (`sparse/etc/samba/smb.conf`): guests can read
  (VLC: *Local network* → *J5NAS*), user **`nas`** can write. Name discovery
  over NetBIOS (`nmbd`) and WS-Discovery (`wsdd-server`, Windows *Network*).
* `j5-nas-firewall.service` drops the SMB, NetBIOS and WS-Discovery ports
  on the mobile-data interfaces (`rmnet*`, IPv4 and IPv6). Samba's
  `hosts allow` is not used: Windows connects over IPv6 when it can, and
  the home IPv6 prefix comes from the ISP and can change.
* Address: `smb://10.42.0.1/nas` from the hotspot, `\\J5NAS\nas` on Windows
  (`wsdd-server` announces the name `J5NAS`; the hostname is set to `j5nas`
  because Windows resolves the name over LLMNR, answered by
  `systemd-resolved` with the hostname — otherwise `net use` fails with
  system error 53). Windows 11 refuses guest sessions, so Samba uses
  `map to guest = Never`: an unknown Windows account gets a logon failure
  and Explorer asks for credentials (`nas`) instead of failing; anonymous
  clients such as VLC still get read-only guest access.
* The 2017 J5 slot rejected one card with `card never left busy state`
  (`error -110`) even with both rails powered; another card worked — try a
  different card first.

### Pi-hole quick-settings tile

* `phosh-plugin/` is a Phosh quick-setting plugin (`pihole-quick-setting`).
  A tap runs `sudo -n j5-pihole-toggle toggle`; the tile reads
  `/run/j5-pihole.state` (written by `j5-pihole-toggle`) and watches it, so
  toggles from the launcher or the shell show up as well.
* Plugins resolve symbols from the `phosh` binary, and not everything in
  the headers is exported — `phosh_quick_setting_set_status_icon()` is
  missing in 0.49 and makes Phosh exit with `symbol lookup error`, so the
  plugin sets the `status-icon` property instead. Check with
  `nm -D --undefined-only` against `nm -D /usr/libexec/phosh` before
  installing a rebuilt plugin.
* Enabled through `gsettings set sm.puri.phosh.plugins quick-settings`
  (as user `droidian`); Phosh only scans plugins at start-up.

## Known issues

* **Free space on the data partition.** `rootfs.img` (8 GB) grows as data is
  written; when `/userdata` is full, writes inside the rootfs fail with
  `ENOSPC` (shown as `I/O error -28` in `dmesg`) and may corrupt the system.
  Remove the old Android data (keep `rootfs.img`, `android-rootfs.img`,
  `android-data`, `lost+found`).
* The camera does not work (and is intentionally blocked).
* Bluetooth: `bluebinder` does not start (the Bluetooth HAL in the container crashes).
* Little RAM — Firefox is very slow.

## Debugging

* Kernel log of the previous boot: `/proc/last_kmsg` (Samsung, also works in TWRP).
* Forced reboot: hold **Vol Down + Power** for ~10 s. TWRP: right after that,
  hold **Vol Up + Home + Power**. (A forced reboot shows up in the log as
  "kernel BUG … `sec_debug_hard_reset_hook`" — that is expected.)
* If boot gets stuck in the initramfs, Halium exposes telnet on `192.168.2.15` over USB.
* Container log: `lxc-start -n android -l DEBUG -o /tmp/lxc.log`.
* Android inside the container: `lxc-attach -n android -- /system/bin/logcat -d`.

## Sources and credits

* [Droidian porting guide](https://github.com/droidian/porting-guide)
* [postmarketOS pmaports](https://gitlab.postmarketos.org/postmarketOS/pmaports) — `device-samsung-j5y17lte`, `linux-postmarketos-exynos7870`
* [samsungexynos7870](https://github.com/samsungexynos7870) — kernel and device trees
* [droidian-devices/common_fragments](https://github.com/droidian-devices/common_fragments) — Halium/Droidian config fragments (4.14 branch)

## License

Kernel patches — GPL-2.0 (like the Linux kernel). `phosh-plugin/` —
GPL-3.0-or-later (it uses Phosh headers). Everything else (scripts,
configuration) — MIT, unless stated otherwise in the file.
