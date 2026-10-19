#!/bin/bash
# RX investigation (idempotent):
#  - before main_loop: 15 s loop printing UART DM SR/MISR/ISR/RX_TOTAL_SNAP
#    every 0.5 s; if SR.RXRDY, read RF and print the word.
#  - WDT is kicked in serial_tstc only after a char has actually been received,
#    so a dead console still lets the run_ram.py watchdog reboot the board.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
U=drivers/serial/qcom_uart.c
B=arch/arm/lib/board.c

if ! grep -q ap1852_rx_ok $U; then
perl -0pi -e 's/\twritel\(1, 0x0200A038\);\t\/\* AP1852: kick WDT \(APCS_WDT0_RST\) \*\//\tif (ap1852_rx_ok)\n\t\twritel(1, 0x0200A038);\t\/* AP1852: kick WDT once console RX proven *\//' $U
perl -0pi -e 's/(void ap1852_dbg_putc\(char c\);\n)/$1int ap1852_rx_ok;\n/' $U
# mark RX as proven when serial_getc hands out a byte
perl -0pi -e 's/(\tbyte = \(int\)word & 0xff;\n)/\tap1852_rx_ok = 1;\n$1/' $U
fi

if ! grep -q ap1852_rx_probe $B; then
perl -0pi -e 's/(static void ap1852_probe_timer\(void\))/static void ap1852_rx_probe(void)
{
\tunsigned int b = 0x16340000, n, sr;
\tputs("\\nRX probe: type now (15 s)\\n");
\tfor (n = 0; n < 30; n++) {
\t\twritel(1, 0x0200A038);\t\/* kick WDT *\/
\t\t__udelay(500000);
\t\tsr = readl(b + 0x08);
\t\tap1852_dbg_putc(\x27S\x27); ap1852_dbg_hex(sr);
\t\tap1852_dbg_putc(\x27 \x27); ap1852_dbg_putc(\x27M\x27); ap1852_dbg_hex(readl(b + 0x10));
\t\tap1852_dbg_putc(\x27 \x27); ap1852_dbg_putc(\x27I\x27); ap1852_dbg_hex(readl(b + 0x14));
\t\tap1852_dbg_putc(\x27 \x27); ap1852_dbg_putc(\x27T\x27); ap1852_dbg_hex(readl(b + 0x38));
\t\tif (sr & 1) {
\t\t\tap1852_dbg_putc(\x27 \x27); ap1852_dbg_putc(\x27F\x27); ap1852_dbg_hex(readl(b + 0x70));
\t\t}
\t\tap1852_dbg_putc(\x27\\r\x27); ap1852_dbg_putc(\x27\\n\x27);
\t}
}

$1/' $B
perl -0pi -e 's/(\t\/\* main_loop\(\) can return to retry autoboot, if so just run it again\. \*\/\n)/\tap1852_rx_probe();\n$1/' $B
fi
grep -n "ap1852_rx" $U $B
