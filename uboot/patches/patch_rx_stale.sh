#!/bin/bash
# Re-arm the UART DM RX transfer after a stale event (idempotent). The packer
# only pushes a partial (1-3 char) word into the FIFO on a stale timeout, and
# the stale event is one-shot; without re-arming, the tail of a typed line
# waits for more input. Done only once the FIFO is empty (RESET_RX clears it).
set -e
cd ~/ap1852/uboot-ipq806x/uboot
U=drivers/serial/qcom_uart.c
grep -q 'AP1852: re-arm stale' $U && exit 0
# Same sequence as Linux msm_serial handle_rx_dm(); the driver's
# init_rx_transfer (with RESET_RX) left stale disarmed on this board.
perl -0pi -e 's/(\tif \(!\(readl\(MSM_BOOT_UART_DM_SR\(base\)\) & MSM_BOOT_UART_DM_SR_RXRDY\)\)\n)\t\treturn 0;\n/$1\t{\n\t\t\/* AP1852: re-arm stale so partial words keep flushing *\/\n\t\tif (readl(MSM_BOOT_UART_DM_MISR(base)) & MSM_BOOT_UART_DM_RXSTALE)\n\t\t{\t\/* same sequence as Linux msm_serial handle_rx_dm(); no RESET_RX *\/\n\t\t\twritel(MSM_BOOT_UART_DM_CMD_RES_STALE_INT, MSM_BOOT_UART_DM_CR(base));\n\t\t\twritel(0xFFFFFF, MSM_BOOT_UART_DM_DMRX(base));\n\t\t\twritel(MSM_BOOT_UART_DM_GCMD_ENA_STALE_EVT, MSM_BOOT_UART_DM_CR(base));\n\t\t}\n\t\treturn 0;\n\t}\n/' $U
s=$(grep -n '^int serial_tstc' $U | cut -d: -f1); sed -n "$s,$((s+24))p" $U
grep -n 'msm_boot_uart_dm_init_rx_transfer' $U | head -3
