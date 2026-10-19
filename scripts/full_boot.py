"""Full bench cycle for unit 2, all in RAM (nothing written to flash):
reboot (from OpenWrt or the second-stage U-Boot) -> stock U-Boot prompt (auto-ESC by the
bridge) -> second-stage U-Boot (run_ram.py) -> OpenWrt (boot_openwrt.py).

Usage: python full_boot.py [name]      (default name: ap1852)
       python full_boot.py --uboot-only (stop at the second-stage U-Boot; its bootcmd runs)
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(HERE, "..", "logs", "ap2_boot.log")
uboot_only = "--uboot-only" in sys.argv
args = [a for a in sys.argv[1:] if not a.startswith("--")]
name = args[0] if args else "ap1852"


def run(*args):
    print(">>", " ".join(args), flush=True)
    subprocess.run([sys.executable, os.path.join(HERE, args[0]), *args[1:]], check=True)


def last_prompt():
    with open(LOG, "rb") as f:
        f.seek(max(0, os.path.getsize(LOG) - 600))
        tail = f.read().decode("utf-8", "replace")
    for p in ("(RNAQ-C7) #", "(IPQ) #", "root@OpenWrt"):
        tail = tail.replace(p, "\x00" + p)
    parts = [s for s in tail.split("\x00") if s.startswith(("(RNAQ", "(IPQ", "root@"))]
    return parts[-1][:12] if parts else ""


print("rebooting board ...", flush=True)
run("send.py", "reboot", "--wait", "2")
for _ in range(60):
    time.sleep(3)
    if last_prompt().startswith("(RNAQ"):
        break
else:
    sys.exit("stock U-Boot prompt not seen")
print("stock U-Boot prompt caught", flush=True)
run("run_ram.py", "uboot_ap1852.bin", "--wait", "4")
# The second-stage U-Boot only kicks the watchdog armed by run_ram.py once console RX has
# worked; send a key right away (not the "gl" stop key, so autoboot goes on).
run("send.py", "<ENTER>", "--wait", "10")
if uboot_only:
    sys.exit(0)
run("boot_openwrt.py", name, "--wait", "5")
print("kernel started; watch the AP1852 konsol tab", flush=True)
