#!/bin/bash
# Build adron-s/uboot-ipq806x as a RAM-loadable second-stage U-Boot for the
# AP1852 (CORSICA, machid 0x1260). Loaded by stock U-Boot with
#   tftpboot 0x44000000 uboot_ap1852.bin; go 0x44000000
set -e
SRC=~/ap1852/uboot-ipq806x/uboot
OUT="${OUT:-$(cd "$(dirname "$0")/.." && pwd)/out}"
cd "$SRC"

# --- board adaptation (idempotent) ---
CFG=include/configs/ipq806x_cdp.h
sed -i 's/^#define CONFIG_SYS_TEXT_BASE .*/#define CONFIG_SYS_TEXT_BASE            0x44000000/' $CFG
sed -i 's/^#define CONFIG_BAUDRATE .*/#define CONFIG_BAUDRATE                 9600/' $CFG
# CORSICA uses the same UART (GSBI4, 0x16340000, mnd 12/625/313) as AP148.
sed -i 's|machid = MACH_TYPE_IPQ806X_STORM; //!!!!$|machid = MACH_TYPE_IPQ806X_AP148; //!!!! AP1852/CORSICA: same UART as AP148|' board/qcom/ipq806x_cdp/ipq806x_cdp.c

# Keep the UART baud divisor (CSR) programmed by the stock bootloader (9600);
# the driver would otherwise force 0xFF (115200) and the console goes silent.
UART=drivers/serial/qcom_uart.c
grep -q AP1852_KEEP_CSR $UART || perl -0pi -e 's/(\twritel\(UART_DM_CLK_RX_TX_BIT_RATE,\n\t\t\tMSM_BOOT_UART_DM_CSR\(uart_cfg->uart_dm_base\)\);)/#ifndef AP1852_KEEP_CSR\n$1\n#endif/' $UART
grep -q 'define AP1852_KEEP_CSR' $CFG || sed -i 's/^#define CONFIG_BAUDRATE .*/&\n#define AP1852_KEEP_CSR/' $CFG

# Bounded UART TX waits (TX_READY never asserts after taking over from stock).
bash "$(dirname "$0")/patch_uart_timeout.sh" >/dev/null
# Console output via raw one-char writes (needs ap1852_dbg_putc from patch_debug_markers.sh).
bash "$(dirname "$0")/patch_debug_markers.sh" >/dev/null
bash "$(dirname "$0")/patch_uart_raw.sh" >/dev/null
bash "$(dirname "$0")/patch_corsica_eth.sh" >/dev/null
bash "$(dirname "$0")/patch_skip_art.sh" >/dev/null
bash "$(dirname "$0")/patch_console_wdt.sh" >/dev/null
bash "$(dirname "$0")/patch_rx_probe.sh" >/dev/null
bash "$(dirname "$0")/patch_rx_raw.sh" >/dev/null
bash "$(dirname "$0")/patch_wdt_gate.sh" >/dev/null
bash "$(dirname "$0")/patch_rx_stale.sh" >/dev/null
bash "$(dirname "$0")/patch_bootm_len.sh" >/dev/null
# RX probe served its purpose; keep the code but don't run the 15 s loop.
sed -i 's/^\tap1852_rx_probe();$/\t\/\/ap1852_rx_probe();/' arch/arm/lib/board.c
# Persistent-chain env (no env storage, boot from UBI) and no debug markers.
bash "$(dirname "$0")/patch_ap1852_env.sh" >/dev/null
bash "$(dirname "$0")/strip_debug_markers.sh" >/dev/null
# Final say on autoboot: patch_console_wdt.sh (bring-up era) sets -1/"" on
# every run; the persistent chain needs a 2 s delay and "run ubiboot".
sed -i 's/^#define CONFIG_BOOTDELAY\t.*/#define CONFIG_BOOTDELAY\t2\t\/* AP1852_ENV *\//' $CFG
sed -i 's/^#define CONFIG_BOOTCOMMAND .*/#define CONFIG_BOOTCOMMAND  "run ubiboot"\t\/* AP1852_ENV *\//' $CFG
grep -q '"bootdelay=2' $CFG || sed -i '/^\t"loadaddr=0x48000000\\0" \\$/a\	"bootdelay=2\\0" \\' $CFG
# never bootm a stale image left in RAM when the UBI read fails
sed -i 's/"ubiboot=ubi part ubi; ubi read $loadaddr kernel; bootm $loadaddr\\0"/"ubiboot=ubi part ubi \&\& ubi read $loadaddr kernel \&\& bootm $loadaddr\\0"/' $CFG
grep -q '"ubiboot=ubi part ubi && ubi read' $CFG || { echo "ERROR: ubiboot not chained with &&"; exit 1; }

# Cross compiler: Ubuntu's gcc-arm-linux-gnueabi if present (apt removes it
# when gcc-multilib for the OpenWrt build is installed), else OpenWrt's own.
if command -v arm-linux-gnueabi-gcc >/dev/null; then
    CC_PREFIX=arm-linux-gnueabi-
else
    TC=$(ls -d ~/ap1852/openwrt/staging_dir/toolchain-arm_cortex-a15+neon-vfpv4_gcc-*_musl_eabi 2>/dev/null | head -1)
    [ -n "$TC" ] || { echo "no ARM cross compiler (OpenWrt toolchain not built yet)"; exit 1; }
    export STAGING_DIR=$(dirname "$TC") PATH="$TC/bin:$PATH"
    CC_PREFIX=arm-openwrt-linux-muslgnueabi-
    # This toolchain defaults to -mfloat-abi=hard -mfpu=neon-vfpv4 and emits
    # NEON stores (vmov/vstr d16); U-Boot never enables the FPU -> "undefined
    # instruction". Keep the ABI (to link with this toolchain's libgcc; the
    # 2012.07 private libgcc lacks __aeabi_uldivmod) but forbid FP/SIMD regs.
    EXTRA_CFLAGS="-mgeneral-regs-only"
    EXTRA_MAKE=""
fi

# Old tree only knows gcc <= 7; gcc 13 is compatible with the gcc7 header.
GCCMAJ=$(${CC_PREFIX}gcc -dumpversion | cut -d. -f1)
[ -f include/linux/compiler-gcc$GCCMAJ.h ] || cp include/linux/compiler-gcc7.h include/linux/compiler-gcc$GCCMAJ.h

make ARCH=arm CROSS_COMPILE=$CC_PREFIX distclean >/dev/null
make ARCH=arm CROSS_COMPILE=$CC_PREFIX ipq806x_cdp_config
# Serial build: the old Makefile races on generated headers with -j.
# Target u-boot.bin only; the .mbn wrapper (needs python) is not used for RAM boot.
# Extra compiler flags go through QSDK_CFLAGS (this 2012.07 tree ignores KCFLAGS).
make ARCH=arm CROSS_COMPILE=$CC_PREFIX $EXTRA_MAKE \
    QSDK_CFLAGS="$EXTRA_CFLAGS" u-boot.bin "$@" 2>&1 | tee ../build.log | grep -E 'error|Error' || true

${CC_PREFIX}objcopy -O binary u-boot uboot_ap1852.bin
cp uboot_ap1852.bin "$OUT/"
ls -l "$OUT/uboot_ap1852.bin"
${CC_PREFIX}readelf -h u-boot | grep Entry
# guard: no FPU/NEON instructions may end up in U-Boot
N=$(${CC_PREFIX}objdump -d u-boot | grep -cE '\sv(ld|st|mov|dup|add|eor|orr|and|mul|cvt|ldr|str|push|pop)[.0-9a-z]*\s' || true)
echo "FPU/NEON instructions: $N"
[ "$N" = 0 ] || { echo "ERROR: FPU/NEON code in U-Boot"; exit 1; }
