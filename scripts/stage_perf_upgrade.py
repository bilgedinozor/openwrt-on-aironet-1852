"""Sysupgrade unit 2 to the image with L2 scaling + perf defaults, keeping
the configuration. Runs over the serial console; the board fetches the image
from the PC over its WAN port (python -m http.server on 10.0.5.50:8080 serving
C:\\Dev\\Claude\\Cisco). Stops at the first failed check.
"""
import hashlib
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TFTP = os.path.join(HERE, "..", "tftp")
FW = "openwrt-24.10.8-ipq806x-generic-cisco_ap1852-squashfs-nand-sysupgrade.bin"
URL = "http://10.0.5.50:8080/tftp/" + FW
PART2_SHA = "4b8d98dfd25aa8dc429e1129ad69a9dd17ea59fef9200608124447c36a87d04d"


def sh(cmd, wait):
    out = subprocess.run([sys.executable, os.path.join(HERE, "send.py"), cmd, "--wait", str(wait)],
                         capture_output=True, text=True, errors="replace").stdout
    return out.replace("\r", "")


def fail(msg):
    print("STOP:", msg, flush=True)
    sys.exit(1)


def step(t):
    print("\n=== " + t + " ===", flush=True)


step("1. pre-checks")
out = sh("cat /tmp/sysinfo/board_name; for v in /sys/class/ubi/ubi0_*; do cat $v/name; done | tr '\\n' ' '; echo", 4)
print(out)
if "cisco,ap1852" not in out or "part1 part2 owrt_uboot kernel rootfs rootfs_data" not in out:
    fail("unexpected board or UBI layout")

step("2. part2 hash before")
out = sh("head -c 63741952 /dev/ubi0_1 | sha256sum", 45)
if PART2_SHA not in out:
    fail("part2 hash mismatch before upgrade:\n" + out)
print("part2 OK", PART2_SHA)

step("3. fetch image")
local = hashlib.sha256(open(os.path.join(TFTP, FW), "rb").read()).hexdigest()
out = sh(f"wget -q -O /tmp/fw.bin {URL} && sha256sum /tmp/fw.bin", 30)
m = re.search(r"([0-9a-f]{64})\s+/tmp/fw.bin", out)
print("local ", local)
print("board ", m.group(1) if m else out)
if not m or m.group(1) != local:
    fail("image download mismatch")

step("4. sysupgrade -T and keep-list")
out = sh("tar tf /tmp/fw.bin; sysupgrade -T /tmp/fw.bin && echo T_OK; sysupgrade -l | head -40", 10)
print(out)
if "T_OK" not in out:
    fail("sysupgrade -T rejected the image")

step("5. sysupgrade (config kept); board reboots to stock U-Boot, bridge stops it")
print(sh("sysupgrade -v /tmp/fw.bin", 20))
print("STAGE_PERF_UPGRADE_DONE", flush=True)
