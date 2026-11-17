#!/bin/sh
# Samsung J5 2017 (legacy android_usb gadget): RNDIS network over USB
# Phone: 10.15.19.82/24, DHCP for the host from busybox udhcpd.
A=/sys/class/android_usb/android0
BB=/usr/local/bin/busybox
[ -d $A ] || exit 0
# keep the USB controller powered (runtime PM may suspend dwc3 -> no D+ pullup)
for c in /sys/devices/platform/13600000.usb/power/control /sys/devices/platform/13600000.usb/13600000.dwc3/power/control /sys/class/udc/*/device/power/control; do [ -e "$c" ] && echo on > "$c"; done
echo 0 > $A/enable
echo "" > $A/functions
echo 1 > $A/enable
sleep 1
echo 0 > $A/enable
echo "Samsung" > $A/iManufacturer
echo "j5y17lte-droidian" > $A/iSerial
echo 04E8 > $A/idVendor
echo 6863 > $A/idProduct
echo "Droidian" > $A/iProduct
echo rndis > $A/functions
echo 1 > $A/enable
sleep 1
for u in /sys/class/udc/*; do [ -e $u/soft_connect ] && { echo disconnect > $u/soft_connect; sleep 1; echo connect > $u/soft_connect; }; done
for i in 1 2 3 4 5 6 7 8 9 10; do
  ip link show rndis0 >/dev/null 2>&1 && break; sleep 1
done
ip addr add 10.15.19.82/24 dev rndis0 2>/dev/null
ip link set rndis0 up
printf 'start 10.15.19.100\nend 10.15.19.110\ninterface rndis0\noption subnet 255.255.255.0\nlease_file /run/udhcpd.leases\n' > /run/udhcpd.conf
touch /run/udhcpd.leases
$BB udhcpd /run/udhcpd.conf
# (no shell here: use SSH over this link)
