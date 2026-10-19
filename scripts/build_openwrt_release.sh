#!/bin/bash
# Build OpenWrt 24.10.8 for the Cisco AP1852 from the release tag, with the
# official ipq806x config.buildinfo (CONFIG_ALL_KMODS kept so the kernel
# vermagic matches the official kmod repository) and pinned feeds.
# Only the AP1852 device is built; SDK/ImageBuilder/all-profiles are switched off.
set -e
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
REL=24.10.8
SRC=~/ap1852/openwrt-$REL
REPO="${REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
CISCO="$REPO"
OUT=$CISCO/tftp

if [ ! -d "$SRC" ]; then
    git clone --depth 1 -b v$REL https://git.openwrt.org/openwrt/openwrt.git "$SRC"
fi
cd "$SRC"
# reuse source downloads from the first tree
[ -e dl ] || ln -s ~/ap1852/openwrt/dl dl

# feeds pinned exactly as the official release (feeds.buildinfo)
cat > feeds.conf <<'EOF'
src-git packages https://git.openwrt.org/feed/packages.git^23abaa6f3b0fdfd76b570031107e5718476ff0c8
src-git luci https://git.openwrt.org/project/luci.git^cac97ed67cfbcad90db49f5f3b1245c2c4cbfae5
src-git routing https://git.openwrt.org/feed/routing.git^946e9ff93be935fce6c03f4c02124833c35c2f56
src-git telephony https://git.openwrt.org/feed/telephony.git^92892fa285360b8981f62bf4e0a097e6449e7e33
EOF
[ -d feeds/packages ] || { ./scripts/feeds update -a; ./scripts/feeds install -a; }

bash "$CISCO/openwrt/add_ap1852.sh" "$SRC"

# official config, minus the parts not needed here
grep -vE '^CONFIG_(TARGET_MULTI_PROFILE|TARGET_ALL_PROFILES|TARGET_PER_DEVICE_ROOTFS|SDK|SDK_LLVM_BPF|IB|IB_STANDALONE|MAKE_TOOLCHAIN|COLLECT_KERNEL_DEBUG|BUILDBOT|ALL_NONSHARED|TARGET_DEVICE_)' \
    $CISCO/openwrt/config.buildinfo-$REL > .config
cat $CISCO/openwrt/ap1852_packages.config >> .config
make defconfig

make -j"$(nproc)" download
make -j"$(nproc)" 2>&1 | tee ../openwrt-$REL-build.log | grep -E '^make\[[12]\]|ERROR|error:' || true

B=bin/targets/ipq806x/generic
ls -l $B | grep -i ap1852 || { echo "BUILD FAILED, see ~/ap1852/openwrt-$REL-build.log"; exit 1; }
cp $B/*cisco_ap1852*initramfs* $B/*cisco_ap1852*sysupgrade* "$OUT/"
echo "kernel package: $(ls $B/packages/kernel_* 2>/dev/null | xargs -n1 basename)"
echo "OPENWRT_BUILD_DONE"
