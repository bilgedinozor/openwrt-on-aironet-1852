"""Chain-boot OpenWrt from NAND by hand, without writing the stock env.
(Older release-38 units only, which still have `go`/`mw`; on release-42 use
`bootipq tftp` to reach the second-stage U-Boot instead.)
Reboots the board (OpenWrt or the second-stage U-Boot), waits for the stock U-Boot prompt
(the bridge auto-ESCs), sets mtdids/mtdparts in RAM, loads the second-stage U-Boot from UBI
volume owrt_uboot and jumps to it; its own bootcmd then boots OpenWrt.

Usage: python chain_boot.py [--no-reboot] [--stop]
  --stop  interrupt the second-stage U-Boot's autoboot ("gl") and stay at "(IPQ) #"
"""
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
LOG = os.path.join(HERE, "..", "logs", "ap2_boot.log")


def send(cmd, wait):
    out = subprocess.run([sys.executable, os.path.join(HERE, "send.py"), cmd, "--wait", str(wait)],
                         capture_output=True, text=True, errors="replace").stdout
    print(out, flush=True)
    return out


def last_prompt():
    with open(LOG, "rb") as f:
        f.seek(max(0, os.path.getsize(LOG) - 600))
        tail = f.read().decode("utf-8", "replace")
    for p in ("(RNAQ-C7) #", "(IPQ) #", "root@"):
        tail = tail.replace(p, "\x00" + p)
    parts = [s for s in tail.split("\x00") if s.startswith(("(RNAQ", "(IPQ", "root@"))]
    return parts[-1][:12] if parts else ""


if "--no-reboot" not in sys.argv:
    send("reboot", 2)
    for _ in range(80):
        time.sleep(3)
        if last_prompt().startswith("(RNAQ"):
            break
    else:
        sys.exit("stock U-Boot prompt not seen")
print(">> stock U-Boot prompt", flush=True)
send("", 1)
send("setenv mtdids nand0=nand0", 1)
send("setenv mtdparts mtdparts=nand0:256m@0(ubi)", 1)
send("ubi part ubi", 25)
out = send("ubi read 0x44000000 owrt_uboot 0x54e14", 10)
if "Read 347668 bytes" not in out:
    sys.exit("could not read owrt_uboot")
if "--stop" in sys.argv:
    send("go 0x44000000", 0.5)
    for _ in range(12):            # bootstopkey "gl" during the 2 s countdown
        out = send("gl", 0.4)
        if "(IPQ) #" in out:
            break
    print(">> stopped at the second-stage U-Boot prompt", flush=True)
    sys.exit(0)
send("go 0x44000000", 3)
print(">> second-stage U-Boot started; it boots OpenWrt from UBI (watch the console tab)", flush=True)
