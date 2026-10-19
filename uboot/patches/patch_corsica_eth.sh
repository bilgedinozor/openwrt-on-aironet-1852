#!/bin/bash
# Give the AP148 board entry (machid 4704 = 0x1260, which Cisco CORSICA also
# uses) the AP1852's real Ethernet wiring, taken from the stock appsbl.bin
# board table (offset 0x5d514). Idempotent.
#   GMAC2 0x37400000 SGMII -> AR8033 @ MDIO 1
#   GMAC3 0x37600000 SGMII -> AR8033 @ MDIO 2
#   no QCA8337 switch on this board
# Also disable the APCS watchdog armed by run_ram.py once the prompt is reached.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
P=board/qcom/ipq806x_cdp/ipq806x_board_param.h
C=board/qcom/ipq806x_cdp/ipq806x_cdp.c
B=arch/arm/lib/board.c

if ! grep -q ap1852_gmac_gpio $P; then
# GPIO table copied from the stock image: {gpio, func, out, pull, drvstr, oe}
perl -0pi -e 's/(\/\* Board specific parameter Array \*\/)/\/* AP1852 (CORSICA): MDIO on 0\/1, SGMII-related pins as in stock table *\/
gpio_func_data_t ap1852_gmac_gpio[] = {
\t{ 0, 1, 1, 0, 3, 0 }, { 1, 1, 1, 0, 3, 1 },
\t{ 51, 2, 1, 0, 3, 0 }, { 52, 2, 1, 0, 3, 0 },
\t{ 59, 2, 1, 0, 3, 0 }, { 60, 2, 1, 0, 3, 0 },
\t{ 61, 2, 1, 0, 3, 0 }, { 62, 2, 1, 0, 3, 0 },
\t{ 27, 2, 1, 0, 3, 1 }, { 28, 2, 1, 0, 3, 1 },
\t{ 29, 2, 1, 0, 3, 1 }, { 30, 2, 1, 0, 3, 1 },
\t{ 31, 2, 1, 0, 3, 1 }, { 32, 2, 1, 0, 3, 1 },
};

$1/' $P

# Replace the gmac part of the first AP148 entry only.
perl -0pi -e 's/(\.machid = MACH_TYPE_IPQ806X_AP148,\n\t\t\.ddr_size = )\(256 << 20\)(,.*?)\.gmac_gpio_count = ARRAY_SIZE\(gmac1_gpio\),\n\t\t\.gmac_gpio = gmac1_gpio,\n\t\t\.gmac_cfg = \{.*?\n\t\t\},\n/$1(1024 << 20)$2.gmac_gpio_count = ARRAY_SIZE(ap1852_gmac_gpio),\n\t\t.gmac_gpio = ap1852_gmac_gpio,\n\t\t.gmac_cfg = {\n\t\t\tgmac_board_cfg(2, 1, SGMII, 0, 0, 1, 1, 1),\n\t\t\tgmac_board_cfg(3, 1, SGMII, 0, 0, 1, 1, 2),\n\t\t\tgmac_board_cfg_invalid(),\n\t\t\tgmac_board_cfg_invalid(),\n\t\t},\n/s' $P
fi

if ! grep -q ap1852_no_switch $C; then
perl -0pi -e 's/(int board_eth_init\(bd_t \*bis\)\n\{)/\/* AP1852 has no switch: PHYs hang directly off GMAC2\/3 *\/\nstatic int ap1852_no_switch(ipq_gmac_board_cfg_t *cfg)\n{\n\treturn 0;\n}\n\n$1/' $C
perl -0pi -e 's/(\tswitch \(gboard_param->machid\) \{\n)(\tcase MACH_TYPE_IPQ806X_AP160_2XX:)/$1\tcase MACH_TYPE_IPQ806X_AP148:\n\t\tipq_register_switch(ap1852_no_switch);\n\t\tbreak;\n$2/' $C
fi

if ! grep -q 'AP1852: watchdog off' $B; then
perl -0pi -e 's/(\t\/\* main_loop\(\) can return to retry autoboot, if so just run it again\. \*\/\n)/\twritel(0, APCS_WDT0_EN);\t\/* AP1852: watchdog off (armed by run_ram.py) *\/\n$1/' $B
fi

grep -n -A8 "ddr_size = (1024 << 20)" $P
grep -n -B1 -A2 "ap1852_no_switch" $C
grep -n "AP1852: watchdog off" $B
