# Droidian na Samsung Galaxy J5 (2017) — `j5y17lte`

Port [Droidiana](https://droidian.org) (Debian dla telefonów, Phosh + Halium) na
**Samsung Galaxy J5 (2017), SM-J530F** (Exynos 7870).

Repozytorium zawiera wszystko, czego potrzeba, żeby powtórzyć port od zera:
łatki kernela z pakietowaniem Droidiana, nakładkę na rootfs z poprawkami
specyficznymi dla urządzenia, skrypty oraz konfigurację hotspotu z Pi-hole.

> ⚠️ Projekt hobbystyczny. Flashowanie może skończyć się koniecznością
> przywracania telefonu przez Odin/Heimdall. Przed startem zrób kopię
> partycji `BOOT`, `RECOVERY` i **`EFS`** (IMEI!).

## Status

| Funkcja | Stan | Uwagi |
|---|---|---|
| Start do Phosh | ✅ | ok. 60 s do ekranu blokady |
| Ekran, dotyk (pion i poziom) | ✅ | wymaga łatki phoc (patrz niżej) |
| Obrót ekranu | ✅ | |
| Rozmowy głosowe | ✅ | |
| Dane komórkowe (LTE) | ✅ | patrz „Dane komórkowe” |
| Wi-Fi (klient) | ✅ | |
| Hotspot Wi-Fi | ✅ | firmware SoftAP, 2.4 GHz kan. 6 |
| Pi-hole dla hotspotu | ✅ | przełącznik w menu aplikacji |
| SSH (USB i Wi-Fi) | ✅ | tylko klucze |
| Wszystkie 8 rdzeni CPU | ✅ | hotplug governor wyłączony |
| Kamera | ❌ | węzły V4L2 zablokowane — sterownik FIMC-IS powoduje kernel panic |
| Dźwięk multimediów, SMS, Bluetooth, GPS, czujniki | ❓ | niesprawdzone (bluebinder się nie uruchamia) |
| Przeglądarka | ⚠️ | działa, ale 2 GB RAM to mało dla Firefoksa |

## Urządzenie

| | |
|---|---|
| Model | SM-J530F (`j5y17lte`) |
| SoC | Exynos 7870, 8× Cortex-A53, Mali-T830 |
| RAM / pamięć | 2 GB / 16 GB eMMC |
| Bootloader | Samsung S-boot, flashowanie przez Odin/Heimdall, partycje WIELKIMI literami (`BOOT`, `VENDOR`, `USERDATA`) |
| Partycja `BOOT` | **32 MiB** |
| Baza Androida | LineageOS 17.1 (Android 10, API 29), partycja `VENDOR` (Treble) |
| Kernel | 3.18.140, [samsungexynos7870/android_kernel_samsung_exynos7870](https://github.com/samsungexynos7870/android_kernel_samsung_exynos7870) gałąź `simple_q_permissive` |
| Droidian | 101 (trixie), rootfs `api29` |

Parametry obrazu startowego (z pmaports postmarketOS, `device-samsung-j5y17lte`):
page size 2048, base `0x10000000`, kernel `0x8000`, ramdisk `0x01000000`,
tags `0x100`, nagłówek v0, osobny `dt.img` w formacie Exynos `DTBH`.

## Zawartość repozytorium

```
kernel/patches/     łatki na bazę kernela (pakietowanie Droidiana + poprawki)
sparse/             pliki nakładane na rootfs Droidiana (układ jak w pakietach adaptation)
pihole/             zapytanie SQL dodające listę dozwolonych domen
scripts/
  build-kernel.sh     klonuje kernel, nakłada łatki, buduje .deb i boot.img w Dockerze
  install-overlay.sh  instaluje sparse/ na działającym telefonie przez SSH
  setup-pihole.sh     instaluje Pi-hole i podpina go pod hotspot
```

## Instalacja od zera

### 0. Wymagania

* Telefon z odblokowanym bootloaderem (OEM unlock), **TWRP** i zainstalowanym
  LineageOS 17.1 (potrzebna jest partycja `VENDOR` z Androida 10).
* Linux z `adb`, `docker`, `git`.
* Ok. 6 GB wolnego miejsca na partycji danych telefonu.

### 1. Kopia zapasowa (w TWRP)

```sh
mkdir backup
for p in BOOT RECOVERY EFS CPEFS PARAM; do
  adb exec-out "dd if=/dev/block/by-name/$p 2>/dev/null" > backup/$p.img
done
```

Przywrócenie Androida = wgranie z powrotem `BOOT.img`.

### 2. Kernel

```sh
scripts/build-kernel.sh            # wynik: build/boot.img i build/packages/*.deb
```

Kompilacja odbywa się w kontenerze `quay.io/droidian/build-essential`
(gcc 4.9 z Androida). Skrypt sprawdza, czy `boot.img` mieści się w 32 MiB.

### 3. Rootfs Droidiana

Pobierz `droidian-OFFICIAL-phosh-phone-rootfs-api29-arm64-*.zip` z
[droidian-images/droidian](https://github.com/droidian-images/droidian/releases).
`adb sideload` w TWRP **nie działa** (instalator wymaga losowego dostępu do zipa,
FUSE sideloadu go nie daje), więc instalujemy ręcznie, robiąc to samo co
instalator:

```sh
unzip droidian-*.zip data/rootfs.img
adb push data/rootfs.img /data/rootfs.img          # w TWRP
adb shell 'e2fsck -fy /data/rootfs.img; resize2fs -f /data/rootfs.img 8G;
           ln -s /halium-system/var/lib/lxc/android/android-rootfs.img /data/android-rootfs.img'
```

Plik `rootfs.img` jest rzadki i rośnie w miarę zapisów — **na partycji danych
musi zostać wolne miejsce** (patrz „Znane problemy”).

### 4. Pierwszy dostęp (sieć USB)

Kernel używa starego gadżetu `android_usb` (nie configfs), a Droidian nie
konfiguruje go sam. Zanim wgrasz kernel, zamontuj rootfs w TWRP i dograj
usługę sieci USB oraz statycznego busyboxa (jest w zipie rootfs, `tools/busybox`):

```sh
adb shell 'mkdir -p /r && mount -o loop /data/rootfs.img /r'
unzip droidian-*.zip tools/busybox
adb push tools/busybox /r/usr/local/bin/busybox
adb push sparse/usr/local/bin/j5-usbnet.sh /r/usr/local/bin/
adb push sparse/etc/systemd/system/j5-usbnet.service /r/etc/systemd/system/
adb shell 'chmod 755 /r/usr/local/bin/busybox /r/usr/local/bin/j5-usbnet.sh
  ln -s /etc/systemd/system/j5-usbnet.service /r/etc/systemd/system/sysinit.target.wants/
  mkdir -p /r/root/.ssh'
adb push ~/.ssh/twoj_klucz.pub /r/root/.ssh/authorized_keys
adb shell 'chmod 600 /r/root/.ssh/authorized_keys; umount /r'
```

Telefon dostanie adres `10.15.19.82`, komputer adres z DHCP `10.15.19.100–110`.
Serwer SSH trzeba doinstalować po pierwszym starcie (`apt install openssh-server`,
z Wi-Fi albo danych komórkowych) — do tego czasu jest tylko sieć.
Nakładka ustawia SSH na logowanie wyłącznie kluczem.

### 5. Wgranie kernela (w TWRP)

```sh
adb push build/boot.img /tmp/boot.img
adb shell 'dd if=/tmp/boot.img of=/dev/block/by-name/BOOT bs=1M; sync'
adb reboot
```

### 6. Nakładka z poprawkami

```sh
scripts/install-overlay.sh root@10.15.19.82 -i ~/.ssh/twoj_klucz
```

Po restarcie powinien pojawić się Phosh. PIN i hasło użytkownika `droidian`: **1234** — zmień je.

### 7. Hotspot + Pi-hole (opcjonalnie)

```sh
scripts/setup-pihole.sh root@10.15.19.82 -i ~/.ssh/twoj_klucz
ssh root@10.15.19.82 pihole setpassword
```

## Znalezione problemy i ich rozwiązania

Kolejność odpowiada temu, jak wychodziły podczas portowania. Ta sekcja jest
najcenniejszą częścią repozytorium — większość z tych rzeczy nie jest nigdzie
opisana.

### Kernel i start

| Problem | Przyczyna | Rozwiązanie |
|---|---|---|
| Parametry z `boot.img` w ogóle nie trafiają do kernela | **S-boot ignoruje cmdline z nagłówka boot.img** i podaje własny (m.in. `console=ram`) | cmdline Droidiana jest w `CONFIG_CMDLINE` (`droidian/j5y17lte.config`); `drivers/of/fdt.c` zmieniony tak, by `CONFIG_CMDLINE` był doklejany **po** argumentach bootloadera i miał pierwszeństwo |
| `run-init: opening console: No such device`, brak startu systemd | `console=ram` od bootloadera | `console=tty0` + `CONFIG_VT=y` (jw.) |
| `boot.img` 36 MB > 32 MiB partycji | `Image` ma 19 MB, initramfs Halium 17 MB | initramfs bez `udev/hwdb.d`, kompresja LZMA (`CONFIG_RD_LZMA`), sprawdzanie rozmiaru w `debian/rules` |
| Brak `dt.img` | snippet Droidiana robi tylko `make dtbs` | `debian/rules` buduje `make dtb.img` (dtbtool_exynos) → `KERNEL_PREBUILT_DT` |
| initramfs nie znajduje partycji `vendor` | Samsung ma nazwy WIELKIMI literami | reguła udev w initramfs i w rootfs z aliasami małymi literami (`61-samsung-lowercase-partlabels.rules`) |
| Kontener Androida (LXC) nie startuje: `Failed to prepare new devpts instance` | kernel 3.18 | `CONFIG_DEVPTS_MULTIPLE_INSTANCES=y` |
| systemd ≥ 256 a cgroup v1 | 3.18 nie ma cgroup2 | `systemd.unified_cgroup_hierarchy=0 SYSTEMD_CGROUP_ENABLE_LEGACY_FORCE=1` |
| Stara toolchain/host | GCC 10+ i brak ccache | łatki `dtc` (`yylloc`) i opcjonalny `ccache` w Makefile |

### Rootfs / userspace

| Problem | Przyczyna | Rozwiązanie |
|---|---|---|
| Start wisi na logo, journald zjada CPU | **pętla sprzężenia**: journald czyta kmsg → odpytuje sysfs zasilacza → sterownik `s2mu005` pisze debug do kmsg → … | `ReadKMsg=no` w `journald.conf.d/10-j5-persistent.conf`; usunięty `systemd.journald.forward_to_kmsg` |
| phoc: `failed to get hwcomposer service` | `/dev/hwbinder`, `/dev/vndbinder` z prawami `0600` | `69-android-system.rules` (wygenerowane z `ueventd.rc` systemu) + `70-j5y17lte.rules` (z vendor) |
| Kernel panic ~60 s po starcie sesji | **GStreamer (`gst-plugin-scanner`) i Firefox (`gfxtest`) otwierają węzły V4L2 kamery FIMC-IS** → NULL deref w sterowniku / sysmmu | łatka `fimc-is` (querycap) + `72-j5-v4l2-root-only.rules` (root-only, **bez** tagu `uaccess`, inaczej logind daje ACL sesji) + wyłączona wtyczka `libgstvideo4linux2.so` (`dpkg-divert`) |
| Gesty nie działają, „system too slow” | czujniki Samsunga są urządzeniami input i zalewają libinput | `71-j5-ignore-sensor-inputs.rules` (`LIBINPUT_IGNORE_DEVICE`) |
| Tylko 4 z 8 rdzeni | governor hotplug wyłącza rdzenie, a zswap nie potrafi zaalokować kompresora przy ponownym włączaniu | `j5-cpu-hotplug.service` trzyma wszystkie rdzenie online |
| Dotyk nie obraca się z ekranem, skala z `phoc.ini` nie działa | adapter HWC2On1 numeruje panel od 1 → wyjście nazywa się **`HWCOMPOSER-2`**, a phoc Droidiana uznaje za wbudowane tylko `HWCOMPOSER-1` | `j5-patch-phoc` (zamiana napisu w binarce, ta sama długość) + hook APT po aktualizacjach; `phoc.ini` dla `HWCOMPOSER-2` (skala 2). Lepszym rozwiązaniem byłaby poprawka w [droidian/phoc](https://github.com/droidian/phoc) (`g_str_has_prefix(name, "HWCOMPOSER-")`) |
| Brak sieci USB | `android_usb` zamiast configfs | `j5-usbnet.service` |

### Dane komórkowe

Phosh przy włączaniu danych tworzy profil NetworkManagera przypięty do ICCID
karty, a NM nie odczytuje obiektu SIM z oFono (`No SIM object available`) i
uznaje profil za niepasujący — przełącznik stoi na „off”. Rozwiązanie:

```sh
nmcli -t -f UUID,TYPE con show | grep gsm          # usuń duplikaty
nmcli con modify <uuid> gsm.sim-id "" gsm.sim-operator-id "" connection.autoconnect yes
nmcli con up <uuid>
```

### Hotspot

* Sterownik `bcmdhd` z firmware „Station/P2P” odrzuca start AP
  (`Failed to set beacon parameters`). Trzeba firmware **SoftAP**
  (`/vendor/etc/wifi/bcmdhd_apsta.bin_blob`), który obsługuje też tryb klienta.
  Ładuje go `j5-wifi-apsta-firmware.service` (sterownik sam dopisuje `_blob`).
* Profil „Phosh Hotspot”: `802-11-wireless.band bg`, `channel 6`, `pmf disable`.
* Po wyłączeniu AP sterownik zostaje „zajęty” (`SCAN-FAILED ret=-16`) i kolejne
  włączenie się nie udaje. Dispatcher `90-j5-hotspot-recover` restartuje radio.
  **Po wyłączeniu hotspotu odczekaj ok. 30–40 s przed ponownym włączeniem.**

### Pi-hole

* Pi-hole v6 (FTL) słucha na **127.0.0.1:5335**; dnsmasq hotspotu
  NetworkManagera przekazuje do niego zapytania klientów
  (`dnsmasq-shared.d/10-pihole.conf`, bez własnego cache, żeby przełącznik
  działał natychmiast). Własny DNS telefonu **nie** jest filtrowany.
* Panel WWW: `http://10.42.0.1:8080/admin` (z urządzenia w hotspocie).
* Przełącznik: ikona **„Pi-hole (wł./wył.)”** w menu aplikacji albo
  `sudo j5-pihole-toggle on|off|status|toggle`.
* Listy blokujące (`sparse/etc/pihole/adlists.list`, ok. 435 tys. domen):
  * [StevenBlack hosts](https://github.com/StevenBlack/hosts)
  * [HaGeZi Pro](https://github.com/hagezi/dns-blocklists)
  * [KADhosts](https://github.com/FiltersHeroes/KADhosts) — polskie
  * [CERT Polska — lista ostrzeżeń](https://hole.cert.pl/) — polskie domeny phishingowe i oszukańcze
  * [Polish Filters (MajkiIT)](https://github.com/MajkiIT/polish-ads-filter)
* Lista dozwolonych: [anudeepND/whitelist](https://github.com/anudeepND/whitelist)
  (domeny potrzebne popularnym usługom).
* Instalator Pi-hole wyłącza stub `systemd-resolved` na porcie 53 — tu nie jest
  to potrzebne (port 5335), `setup-pihole.sh` przywraca stub.

## Znane problemy

* **Miejsce na partycji danych.** `rootfs.img` (8 GB) rośnie w miarę zapisów;
  przy zapełnionym `/userdata` zapisy w rootfs kończą się błędem `ENOSPC`
  (widoczne jako `I/O error -28` w `dmesg`) i grożą uszkodzeniem systemu.
  Usuń dane starego Androida (zostaw `rootfs.img`, `android-rootfs.img`,
  `android-data`, `lost+found`).
* Kamera nie działa (i celowo jest zablokowana).
* Bluetooth: `bluebinder` się nie uruchamia (HAL Bluetooth w kontenerze pada).
* Mało RAM-u — Firefox jest bardzo wolny.

## Debugowanie

* Log kernela z poprzedniego startu: `/proc/last_kmsg` (Samsung, działa też w TWRP).
* Wymuszony restart: przytrzymaj **Vol Dół + Power** ~10 s. TWRP: od razu potem
  **Vol Góra + Home + Power**. (Wymuszony restart kończy się w logu
  „kernel BUG … `sec_debug_hard_reset_hook`” — to normalne.)
* Gdy start utknie w initramfs, Halium wystawia telnet na `192.168.2.15` przez USB.
* Log kontenera: `lxc-start -n android -l DEBUG -o /tmp/lxc.log`.
* Android w kontenerze: `lxc-attach -n android -- /system/bin/logcat -d`.

## Źródła i podziękowania

* [Droidian porting guide](https://github.com/droidian/porting-guide)
* [pmaports postmarketOS](https://gitlab.postmarketos.org/postmarketOS/pmaports) — `device-samsung-j5y17lte`, `linux-postmarketos-exynos7870`
* [samsungexynos7870](https://github.com/samsungexynos7870) — kernel i drzewa urządzeń
* [droidian-devices/common_fragments](https://github.com/droidian-devices/common_fragments) — fragmenty konfiguracji Halium/Droidian (gałąź 4.14)

## Licencja

Łatki kernela — GPL-2.0 (jak kernel Linux). Pozostałe pliki (skrypty,
konfiguracja) — MIT, chyba że w pliku zaznaczono inaczej.
