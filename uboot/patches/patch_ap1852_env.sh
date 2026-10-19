#!/bin/bash
# Second-stage U-Boot environment for the persistent NAND chain (idempotent).
#  - No saveenv command: the QSDK env driver (ENV_IS_IN_NAND, offset taken
#    from SMEM "appsblenv", which is an SPI offset) would overwrite a UBI
#    block on NAND. Reading it is harmless (bad CRC -> default env); the board
#    code is too entangled with the NAND/MMC env drivers to switch to
#    ENV_IS_NOWHERE, so only the write command is removed.
#  - Drop the GL.iNet "lu"/"lf" scripts (they flash SPI/NAND).
#  - Default env: boot OpenWrt's FIT from UBI volume "kernel".
set -e
cd ~/ap1852/uboot-ipq806x/uboot
H=include/configs/ipq806x_cdp.h
grep -q 'AP1852_ENV' $H && exit 0

sed -i 's/^#define CONFIG_CMD_SAVEENV$/#undef CONFIG_CMD_SAVEENV\t\/* AP1852_ENV: no env writes *\//' $H

# Replace the whole CONFIG_EXTRA_ENV_SETTINGS block (up to the first line
# that does not end with a backslash).
perl -0pi -e 's/#define CONFIG_EXTRA_ENV_SETTINGS \\\n(?:.*\\\n)*.*\n/#define CONFIG_EXTRA_ENV_SETTINGS \\
\t"mtdids=nand0=nand0\\0" \\
\t"mtdparts=mtdparts=nand0:256m\@0(ubi)\\0" \\
\t"ipaddr=10.0.5.201\\0" \\
\t"serverip=10.0.5.50\\0" \\
\t"loadaddr=0x48000000\\0" \\
\t"bootdelay=2\\0" \\
\t"bootargs=console=ttyMSM0,9600n8\\0" \\
\t"ubiboot=ubi part ubi && ubi read \$loadaddr kernel && bootm \$loadaddr\\0" \\
\t"tftpboot_ram=tftpboot \$loadaddr ap1852.itb; bootm \$loadaddr\\0"
/' $H

sed -i 's/^#define CONFIG_BOOTCOMMAND  "".*/#define CONFIG_BOOTCOMMAND  "run ubiboot"\t\/* AP1852_ENV *\//' $H
sed -i 's/^#define CONFIG_BOOTDELAY\t.*/#define CONFIG_BOOTDELAY\t2\t\/* AP1852_ENV *\//' $H

# The board code picks nand_saveenv/mmc_saveenv through a function pointer;
# point it at a stub that never writes.
C=board/qcom/ipq806x_cdp/ipq806x_cdp.c
grep -q ap1852_no_saveenv $C || {
    perl -0pi -e 's/(\nvoid env_relocate_spec\(void\))/\n\/* AP1852_ENV: env is never written (see patch_ap1852_env.sh) *\/\nstatic int ap1852_no_saveenv(void)\n{\n\tputs("saveenv is disabled on the AP1852");\n\tputc(10);\n\treturn 1;\n}\n$1/' $C
    # declared at the top: the function that assigns saveenv comes first
    perl -0pi -e 's/(\nloff_t board_env_range;\n)/$1static int ap1852_no_saveenv(void);\t\/* AP1852_ENV *\/\n/' $C
    sed -i 's/\t\tsaveenv = nand_saveenv;/\t\tsaveenv = ap1852_no_saveenv;/; s/\t\tsaveenv = mmc_saveenv;/\t\tsaveenv = ap1852_no_saveenv;/' $C
}

grep -n "AP1852_ENV\|ubiboot\|mtdparts=" $H
grep -n "ap1852_no_saveenv" $C
