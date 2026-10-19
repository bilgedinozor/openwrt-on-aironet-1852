#!/bin/bash
# CONFIG_HW_WATCHDOG makes U-Boot kick APCS WDT0 from main_loop/getc, which
# defeated run_ram.py's "reboot if the console is dead" safety. Gate the
# board's hw_watchdog_reset() on console RX having worked once (idempotent).
set -e
cd ~/ap1852/uboot-ipq806x/uboot
C=board/qcom/ipq806x_cdp/ipq806x_cdp.c
grep -q 'AP1852: only once console RX' $C && exit 0
perl -0pi -e 's/(#ifdef CONFIG_HW_WATCHDOG\nvoid hw_watchdog_reset\(void\)\n\{\n)(\twritel\(1, APCS_WDT0_RST\);)/extern int ap1852_rx_ok;\n$1\tif (!ap1852_rx_ok)\t\/* AP1852: only once console RX works *\/\n\t\treturn;\n$2/' $C
s=$(grep -n 'void hw_watchdog_reset' $C | cut -d: -f1); sed -n "$((s-2)),$((s+7))p" $C
