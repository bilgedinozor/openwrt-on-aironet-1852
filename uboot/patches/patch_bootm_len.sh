#!/bin/bash
# OpenWrt ipq806x kernels decompress to >8 MiB (2012.07 default BOOTM_LEN). Idempotent.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
CFG=include/configs/ipq806x_cdp.h
grep -q 'CONFIG_SYS_BOOTM_LEN' $CFG || sed -i 's/^#define CONFIG_FIT$/#define CONFIG_FIT\n#define CONFIG_SYS_BOOTM_LEN\t(64 << 20)\t\/* AP1852: OpenWrt kernel > 8 MiB *\//' $CFG
grep -n 'CONFIG_SYS_BOOTM_LEN' $CFG
