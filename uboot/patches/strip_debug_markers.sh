#!/bin/bash
# Remove the single-character boot-progress markers (A, a..i, T.., X, R,
# <CPMGDSKOEW) added while bringing the board up. ap1852_dbg_putc() itself
# stays: serial_putc uses it for console output. Idempotent.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
for f in arch/arm/lib/board.c board/qcom/ipq806x_cdp/ipq806x_cdp.c drivers/net/ipq/ipq_gmac_eth.c; do
    sed -i -E "/^[[:space:]]*ap1852_dbg_putc\('.'( \+ \(init_fnc_ptr - init_sequence\))?\);[[:space:]]*$/d" $f
    sed -i -E '/^[[:space:]]*if \(\*init_fnc_ptr == display_banner\)$/{N;/ap1852_probe_timer\(\);/d}' $f
done
grep -n "ap1852_dbg_putc('\|ap1852_probe_timer();" arch/arm/lib/board.c board/qcom/ipq806x_cdp/ipq806x_cdp.c drivers/net/ipq/ipq_gmac_eth.c || echo "markers removed"
