#!/bin/bash
# Route serial_putc through the known-good raw UART DM write (idempotent).
# The driver's packed-FIFO path completes but nothing reaches the wire on the
# AP1852; one char per NO_CHARS_FOR_TX transfer (as uart_hello.bin does) works.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
U=drivers/serial/qcom_uart.c
grep -q AP1852_RAW_PUTC $U && exit 0

# Driver probes from patch_debug_markers2.sh interrupted transfers; turn them off.
sed -i 's/^static int ap1852_probe_once = 1;/static int ap1852_probe_once = 0;/' $U

perl -0pi -e 's/(void serial_putc\(char c\)\n\{\n)(.*?\n\})/$1\t\/* AP1852_RAW_PUTC *\/\n\tif (c == \x27\\n\x27)\n\t\tap1852_dbg_putc(\x27\\r\x27);\n\tap1852_dbg_putc(c);\n}/s' $U
grep -q '^void ap1852_dbg_putc(char c);' $U || sed -i '0,/^#include <common.h>/s//#include <common.h>\nvoid ap1852_dbg_putc(char c);/' $U
grep -n -A7 'void serial_putc(char c)' $U
