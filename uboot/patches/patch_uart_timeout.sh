#!/bin/bash
# Bound the UART DM TX waits (idempotent). On the AP1852, after taking over the
# UART from the stock bootloader, ISR.TX_READY never asserts, so the driver's
# unbounded wait hangs on the very first printf. Wait at most ~5 ms instead.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
U=drivers/serial/qcom_uart.c
grep -q AP1852_TX_TIMEOUT $U && exit 0

perl -0pi -e 's/(static unsigned int\s*\nmsm_boot_uart_dm_write\()/#define AP1852_TX_TIMEOUT 5000\t\/* us *\/\n\n$1/' $U
perl -0pi -e 's/while \(!\(readl\(MSM_BOOT_UART_DM_ISR\(base\)\) & MSM_BOOT_UART_DM_TX_READY\)\)\n(\s*)__udelay\(1\);/{ int ap1852_t = AP1852_TX_TIMEOUT;\n$1while (!(readl(MSM_BOOT_UART_DM_ISR(base)) & MSM_BOOT_UART_DM_TX_READY) \&\&\n$1       !(readl(MSM_BOOT_UART_DM_SR(base)) & MSM_BOOT_UART_DM_SR_TXEMT) \&\& --ap1852_t)\n$1\t__udelay(1); }/' $U
perl -0pi -e 's/while \(!\(readl\(MSM_BOOT_UART_DM_SR\(base\)\) & MSM_BOOT_UART_DM_SR_TXRDY\)\)\n(\s*)__udelay\(1\);/{ int ap1852_t = AP1852_TX_TIMEOUT;\n$1while (!(readl(MSM_BOOT_UART_DM_SR(base)) \& MSM_BOOT_UART_DM_SR_TXRDY) \&\& --ap1852_t)\n$1\t__udelay(1); }/' $U
grep -n -A3 "ap1852_t = " $U
