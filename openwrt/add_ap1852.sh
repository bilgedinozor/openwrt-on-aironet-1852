#!/bin/bash
# Add the Cisco AP1852 board to an OpenWrt tree (idempotent):
# DTS, image recipe, network defaults and sysupgrade hook.
#   bash add_ap1852.sh [openwrt-tree]   (default: ~/ap1852/openwrt)
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
T=${1:-~/ap1852/openwrt}/target/linux/ipq806x

cp "$HERE/qcom-ipq8064-ap1852.dts" $T/files-6.6/arch/arm/boot/dts/qcom/

# Image overlay (performance defaults, RPS hotplug, cpustat tool). These are
# added to every image built from this tree; the scripts check board_name.
TREE=${1:-~/ap1852/openwrt}
mkdir -p "$TREE/files"
cp -r "$HERE/files/." "$TREE/files/"
rm -f "$TREE/files/etc/hotplug.d/net/99-ap1852-rps"	# superseded by the platform hook
chmod 0755 "$TREE/files/usr/libexec/platform/packet-steering.sh" "$TREE/files/usr/bin/ap1852-cpustat" "$TREE/files/etc/uci-defaults/"99-ap1852-*

# Image recipe. UbiFit gives FIT-in-UBI (kernel/rootfs/rootfs_data volumes) and
# a tar sysupgrade image. Only initramfs + nand-sysupgrade are produced: the
# ubinized factory image would ubiformat the whole NAND and wipe Cisco's
# volumes, so it is deliberately not built.
G=$T/image/generic.mk
perl -0pi -e 's/\ndefine Device\/cisco_ap1852\n.*?\nTARGET_DEVICES \+= cisco_ap1852\n//s' $G
cat >> $G <<'EOF'

define Device/cisco_ap1852
	$(call Device/FitImage)
	$(call Device/UbiFit)
	DEVICE_VENDOR := Cisco
	DEVICE_MODEL := AIR-AP1852I
	SOC := qcom-ipq8064
	DEVICE_DTS := qcom-ipq8064-ap1852
	BLOCKSIZE := 128k
	PAGESIZE := 2048
	BOARD_NAME := ap1852
	IMAGES := nand-sysupgrade.bin
	DEVICE_PACKAGES := kmod-ath10k-ct ath10k-firmware-qca99x0-ct
endef
TARGET_DEVICES += cisco_ap1852
EOF

N=$T/base-files/etc/board.d/02_network
grep -q 'cisco,ap1852' $N || perl -0pi -e 's/(\tcase "\$board" in\n)/$1\tcisco,ap1852)\n\t\t# eth0 = PoE\/main port (GMAC2), eth1 = AUX port (GMAC3)\n\t\tucidef_set_interfaces_lan_wan "eth0" "eth1"\n\t\t;;\n/' $N

U=$T/base-files/lib/upgrade/platform.sh
grep -q 'cisco,ap1852' $U || perl -0pi -e 's/(\tqcom,ipq8064-ap148 \|\\\n)/\tcisco,ap1852 |\\\n$1/' $U

grep -n "cisco" $N $U $G
