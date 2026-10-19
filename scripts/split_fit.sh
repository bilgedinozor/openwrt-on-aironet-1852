#!/bin/bash
# Split an OpenWrt ipq806x FIT into an uncompressed legacy uImage + DTB so the
# 2012.07 U-Boot (8 MiB BOOTM_LEN) can boot it: bootm <kernel> - <dtb>
#   bash split_fit.sh <fit.itb> <outprefix>
set -e
FIT=$1; OUT=$2
T=$(mktemp -d)
dumpimage -T flat_dt -p 0 -o $T/kernel.gz "$FIT" >/dev/null
dumpimage -T flat_dt -p 1 -o "$OUT.dtb" "$FIT" >/dev/null
gunzip -c $T/kernel.gz > $T/Image
mkimage -A arm -O linux -T kernel -C none -a 0x42208000 -e 0x42208000 \
    -n "OpenWrt $(basename "$OUT")" -d $T/Image "$OUT.uimg" | grep -E "Data Size|Load"
ls -l "$OUT.uimg" "$OUT.dtb"
rm -rf $T
