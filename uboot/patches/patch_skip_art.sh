#!/bin/bash
# AP1852 keeps MACs in Cisco MFG data on SPI NOR, not in a QSDK "0:ART"
# partition; the AP148-style ART read hangs. Skip it (idempotent) and take
# the MAC from the environment (setenv ethaddr ...) instead.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
C=board/qcom/ipq806x_cdp/ipq806x_cdp.c
grep -q 'AP1852: no QSDK ART' $C && exit 0
perl -0pi -e 's/(int get_eth_mac_address\(uchar \*enetaddr, uint no_of_macs\)\n\{\n(?:[^\n]*;\n|#[^\n]*\n)*?\n)/$1\treturn -1;\t\/* AP1852: no QSDK ART partition; MAC comes from env *\/\n\n/' $C
grep -n "AP1852: no QSDK ART" $C
