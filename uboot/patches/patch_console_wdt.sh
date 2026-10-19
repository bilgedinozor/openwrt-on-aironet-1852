#!/bin/bash
# Console + safety tweaks for running from RAM on the AP1852 (idempotent):
#  - serial_init: leave the UART exactly as the stock bootloader configured it
#    (re-initialising it broke both TX and RX); TX already goes via raw writes.
#  - serial_tstc: kick APCS WDT0 so an idle prompt stays up, while a hung
#    command still lets the watchdog armed by run_ram.py reboot the board.
#    (tstc is polled by the prompt and by ctrlc() inside long ops like tftp)
#  - drop the unconditional "watchdog off" before main_loop.
#  - no autoboot: empty bootcmd, bootdelay -1 (never touch NAND by itself).
set -e
cd ~/ap1852/uboot-ipq806x/uboot
U=drivers/serial/qcom_uart.c
B=arch/arm/lib/board.c
CFG=include/configs/ipq806x_cdp.h

grep -q 'AP1852: keep stock UART' $U || perl -0pi -e 's/(int  serial_init\(void\)\n\{\n)        uart_dm_init\(\);/$1\t\/* AP1852: keep stock UART setup; uart_dm_init() breaks TX\/RX *\//' $U
grep -q 'AP1852: kick WDT' $U || perl -0pi -e 's/(int serial_tstc\(void\)\n\{\n(?:[^\n]*;\n)*?)/$1\twritel(1, 0x0200A038);\t\/* AP1852: kick WDT (APCS_WDT0_RST) *\/\n/' $U
sed -i '/AP1852: watchdog off (armed by run_ram.py)/d' $B

sed -i 's/^#define CONFIG_BOOTCOMMAND  "bootipq"/#define CONFIG_BOOTCOMMAND  ""\t\/* AP1852: no autoboot *\//' $CFG
sed -i 's/^#define CONFIG_BOOTDELAY\t2/#define CONFIG_BOOTDELAY\t-1\t\/* AP1852: no autoboot *\//' $CFG

grep -n "AP1852" $U $CFG
grep -c "watchdog off" $B || true
