#!/bin/bash
# Raw console RX for the AP1852 (idempotent). Measured with patch_rx_probe.sh:
# received chars land in the UART DM RX FIFO packed 4 per word (low byte
# first, partial words zero-padded) and SR.RXRDY (bit 0) flags them, but the
# driver's MISR/stale/RX_TOTAL_SNAP bookkeeping never reports them. Read the
# FIFO directly instead.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
U=drivers/serial/qcom_uart.c
grep -q 'AP1852_RAW_RX' $U && exit 0

perl -0pi -e 's/(int serial_tstc\(void\)\n\{\n).*?\n\treturn 1;\n\}\n/$1\t\/* AP1852_RAW_RX *\/
\tunsigned int base = 0x16340000;\t\/* GSBI4 UART DM *\/
\tint n;

\tif (ap1852_rx_ok)
\t\twritel(1, 0x0200A038);\t\/* AP1852: kick WDT once console RX proven *\/
\tif (valid_data)
\t\treturn 1;
\tif (!(readl(MSM_BOOT_UART_DM_SR(base)) & MSM_BOOT_UART_DM_SR_RXRDY))
\t\treturn 0;
\tword = readl(MSM_BOOT_UART_DM_RF(base, 0));
\tfor (n = 0; n < 4 && ((word >> (8 * n)) & 0xff); n++)
\t\t;
\tvalid_data = n;
\treturn n != 0;
}
/s' $U
s=$(grep -n '^int serial_tstc' $U | cut -d: -f1); sed -n "$s,$((s+20))p" $U
grep -n "define MSM_BOOT_UART_DM_SR_RXRDY\|define MSM_BOOT_UART_DM_RF(" arch/arm/include/asm/arch-qcom-common/uart.h
