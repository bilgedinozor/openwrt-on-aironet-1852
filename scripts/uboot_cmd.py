"""Send commands to the second-stage U-Boot prompt, padding each line so line+CR is a
multiple of 4 chars (its RX path only flushes whole 4-char words reliably).
Usage: python uboot_cmd.py --wait 5 "cmd1" "cmd2" ...
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
args = sys.argv[1:]
wait = "3"
if args[:1] == ["--wait"]:
    wait, args = args[1], args[2:]
for cmd in args:
    cmd += " " * ((-(len(cmd) + 1)) % 4)
    out = subprocess.run([sys.executable, os.path.join(HERE, "send.py"), cmd, "--wait", wait],
                         capture_output=True, text=True, errors="replace").stdout
    print(out, flush=True)
