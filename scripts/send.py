"""Send a command to serial_bridge.py and print the console output that follows.

Usage: python send.py "printenv" [--wait 3]
"""
import argparse
import os
import socket
import time

LOG = os.path.join(os.path.dirname(__file__), "..", "logs", "ap2_boot.log")

ap = argparse.ArgumentParser()
ap.add_argument("cmd")
ap.add_argument("--wait", type=float, default=2.0)
ap.add_argument("--port", type=int, default=5555)
a = ap.parse_args()

start = os.path.getsize(LOG)
with socket.create_connection(("127.0.0.1", a.port)) as s:
    s.sendall(a.cmd.encode() + b"\n")
time.sleep(a.wait)
with open(LOG, encoding="utf-8", errors="replace") as f:
    f.seek(start)
    print(f.read())
