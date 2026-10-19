"""From the second-stage U-Boot prompt "(IPQ) #", TFTP an OpenWrt kernel
(uncompressed legacy uImage from split_fit.sh) + DTB into RAM and boot it.
Nothing is written to flash.

Usage: python boot_openwrt.py ap1852      (uses tftp/ap1852.uimg + ap1852.dtb)
"""
import argparse
import os
import subprocess
import sys

SEND = os.path.join(os.path.dirname(os.path.abspath(__file__)), "send.py")


def send(cmd, wait):
    # The U-Boot RX path only flushes whole 4-char words reliably; pad the
    # line (plus its CR) to a multiple of 4 with trailing spaces.
    cmd += " " * ((-(len(cmd) + 1)) % 4)
    return subprocess.run([sys.executable, SEND, cmd, "--wait", str(wait)],
                          capture_output=True, text=True, errors="replace").stdout


ap = argparse.ArgumentParser()
ap.add_argument("name", help="file prefix in tftp/, e.g. ap1852")
ap.add_argument("--mac", default="00:7E:95:CE:0F:B0")
ap.add_argument("--wait", type=float, default=40)
a = ap.parse_args()

send("", 1)
for cmd in (f"setenv ethaddr {a.mac}", "setenv ipaddr 10.0.5.201",
            "setenv serverip 10.0.5.50", "setenv bootargs console=ttyMSM0,9600n8"):
    send(cmd, 1.5)
for addr, f, w in (("0x47000000", f"{a.name}.dtb", 6), ("0x48000000", f"{a.name}.uimg", 45)):
    out = send(f"tftpboot {addr} {f}", w)
    line = next((l for l in out.splitlines() if "Bytes transferred" in l), None)
    if not line:
        sys.exit(f"tftpboot {f} failed:\n{out}")
    print(f, "->", line.strip())
send("mw 0x0200A040 0", 1.5)          # watchdog off: Linux takes over
print(send("bootm 0x48000000 - 0x47000000", a.wait))
