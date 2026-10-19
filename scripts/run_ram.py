"""Load an image into RAM from the stock U-Boot prompt and jump to it, with the
APCS watchdog armed so a hang reboots the board by itself (stock boot is then
caught again by serial_bridge.py's auto-ESC). Nothing is written to flash.

Usage: python run_ram.py uboot_ap1852.bin [--wdt 20] [--wait 25]
"""
import argparse
import os
import subprocess
import sys

SEND = os.path.join(os.path.dirname(os.path.abspath(__file__)), "send.py")
WDT = 0x0200A000           # APCS_WDT0 (MSM_TMR_BASE)
WDOG_EXPIRED_EN = 0x00903820
TICKS_PER_S = 32768


def send(cmd, wait):
    out = subprocess.run([sys.executable, SEND, cmd, "--wait", str(wait)],
                         capture_output=True, text=True, errors="replace").stdout
    return out


ap = argparse.ArgumentParser()
ap.add_argument("image")
ap.add_argument("--addr", default="0x44000000")
ap.add_argument("--wdt", type=int, default=20, help="seconds; 0 = leave watchdog off")
ap.add_argument("--wait", type=float, default=25)
a = ap.parse_args()

send("<ENTER>", 1)
send("setenv ipaddr 10.0.5.201", 1)
send("setenv serverip 10.0.5.50", 1)
out = send(f"tftpboot {a.addr} {a.image}", 20)
print("\n".join(l for l in out.splitlines() if "Bytes" in l or "rror" in l))
if "Bytes transferred" not in out:
    sys.exit("tftpboot failed")

if a.wdt:
    bite = a.wdt * TICKS_PER_S
    for cmd in (f"mw {WDT + 0x40:#x} 0",            # EN off
                f"mw {WDT + 0x38:#x} 1",            # RST (kick)
                f"mw {WDT + 0x4C:#x} {5 * bite:#x}",  # BARK after BITE
                f"mw {WDT + 0x5C:#x} {bite:#x}",      # BITE -> reset
                f"mw {WDT + 0x40:#x} 1",            # EN on
                f"mw {WDOG_EXPIRED_EN:#x} 1"):
        send(cmd, 0.5)
    print(f"watchdog armed: reset in {a.wdt}s unless kicked")

print(send(f"go {a.addr}", a.wait))
