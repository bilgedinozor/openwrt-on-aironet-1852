#!/bin/sh
# TEMPLATE — edit before use: set EXPECT_SS to YOUR signed image's sha256,
# EXPECT_P2 to YOUR unit's part2 sha256 (check with ubinfo + sha256sum), and the
# wget URL/IP to your own HTTP server. The hashes below are examples from my build.
# Safe part1 installer for unit 3. All critical ops self-verify and ABORT on mismatch.
# Delivered via HTTP (reliable), so serial char-drops cannot corrupt the flash write.
set -u
echo "INSTALL_SCRIPT_V3_BEGIN"

EXPECT_SS=d2f10bdf2175569d169059ef3e0cd368807f1f329e9f46a727e56432d974583c
EXPECT_P2=4b8d98dfd25aa8dc429e1129ad69a9dd17ea59fef9200608124447c36a87d04d
SS_LEN=2098161
P2_LEN=63741952

fail() { echo "INSTALL_RESULT=FAIL_$1"; exit 1; }

# quiet kernel console noise during the operation
dmesg -n 1 2>/dev/null

# 1) fetch image fresh and verify integrity
wget -q http://10.0.5.50:8080/tftp/selfsigned_boot.bin -O /tmp/ss.bin || fail WGET
GOT_SS=$(sha256sum /tmp/ss.bin | cut -d' ' -f1)
echo "SS_SHA=$GOT_SS"
[ "$GOT_SS" = "$EXPECT_SS" ] || fail SS_HASH

# 2) confirm target volume IDENTITY before any write
N1=$(ubinfo /dev/ubi0_1 | sed -n 's/^Name:[[:space:]]*//p')
N0=$(ubinfo /dev/ubi0_0 | sed -n 's/^Name:[[:space:]]*//p')
echo "UBI0_1_NAME=$N1"
echo "UBI0_0_NAME=$N0"
[ "$N1" = "part1" ] || fail TARGET_NOT_PART1
[ "$N0" = "part2" ] || fail PART2_NOT_FOUND

# 3) record part2 baseline BEFORE
P2_BEFORE=$(head -c $P2_LEN /dev/ubi0_0 | sha256sum | cut -d' ' -f1)
echo "P2_BEFORE=$P2_BEFORE"
[ "$P2_BEFORE" = "$EXPECT_P2" ] || fail P2_BASELINE

# 4) write to part1 (ubi0_1)
ubiupdatevol /dev/ubi0_1 /tmp/ss.bin || fail UBIUPDATEVOL
echo "WRITE_DONE"

# 5) verify readback of part1
RB=$(head -c $SS_LEN /dev/ubi0_1 | sha256sum | cut -d' ' -f1)
echo "PART1_READBACK=$RB"
[ "$RB" = "$EXPECT_SS" ] || fail READBACK

# 6) verify part2 UNCHANGED after
P2_AFTER=$(head -c $P2_LEN /dev/ubi0_0 | sha256sum | cut -d' ' -f1)
echo "P2_AFTER=$P2_AFTER"
[ "$P2_AFTER" = "$EXPECT_P2" ] || fail P2_CHANGED

echo "INSTALL_RESULT=PASS"
