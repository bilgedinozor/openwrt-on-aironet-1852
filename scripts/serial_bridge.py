"""Serial console bridge for the AP1852 bench.

Owns the COM port, prints everything live to this terminal, appends it to a
log file, and accepts commands from:
  - this terminal's keyboard (type a line + Enter), and
  - TCP 127.0.0.1:5555 (one line per command; see send.py).

Autoboot is stopped automatically (ESC sent when "stop autoboot" is seen)
unless started with --no-auto-esc. Since OpenWrt boots by itself (MANUAL_BOOT=1)
auto-ESC must be off for normal boots and on only to reach the stock prompt.
Special commands: <ENTER> sends a bare CR, <INTERRUPT> sends a few CRs/spaces
quickly (to stop U-Boot autoboot), <AUTOESC_ON>/<AUTOESC_OFF> toggle auto-ESC,
<QUIT> exits.
"""
import argparse
import datetime
import os
import socket
import sys
import threading
import time

import serial

LOG_LOCK = threading.Lock()


def stamp():
    return datetime.datetime.now().strftime("%H:%M:%S")


def open_port(name, baud):
    # CH341A sometimes hangs on first open; toggling baud fixes it.
    try:
        s = serial.Serial(name, 115200, timeout=0.1)
        s.close()
    except serial.SerialException:
        pass
    return serial.Serial(name, baud, timeout=0.1)


class Bridge:
    def __init__(self, port, baud, log_path, auto_esc=True):
        self.ser = open_port(port, baud)
        self.log = open(log_path, "a", encoding="utf-8", errors="replace")
        self.running = True
        self.auto_esc = auto_esc

    def emit(self, text):
        with LOG_LOCK:
            sys.stdout.write(text)
            sys.stdout.flush()
            self.log.write(text)
            self.log.flush()

    def send(self, line):
        line = line.rstrip("\r\n")
        self.emit(f"\n[bridge {stamp()}] sent: {line!r}\n")
        if line == "<QUIT>":
            self.running = False
        elif line in ("<AUTOESC_ON>", "<AUTOESC_OFF>"):
            self.auto_esc = line == "<AUTOESC_ON>"
            self.emit(f"[bridge {stamp()}] auto-ESC {'on' if self.auto_esc else 'off'}\n")
        elif line == "<ENTER>":
            self.ser.write(b"\r")
        elif line == "<INTERRUPT>":
            for _ in range(20):
                self.ser.write(b"\r")
                time.sleep(0.05)
        else:
            # 9600-baud RX on the AP drops characters when a whole line is
            # written at once, so pace it char-by-char with a small delay.
            for ch in line.encode():
                self.ser.write(bytes([ch]))
                self.ser.flush()
                time.sleep(0.012)
            self.ser.write(b"\r")
            self.ser.flush()

    def reader(self):
        tail = b""
        while self.running:
            data = self.ser.read(4096)
            if data:
                self.emit(data.decode("utf-8", errors="replace"))
                # Stock U-Boot only stops autoboot on ESC; answer the prompt immediately.
                tail = (tail + data)[-64:]
                if self.auto_esc and b"stop autoboot" in tail:
                    self.ser.write(b"\x1b" * 3)
                    self.emit(f"\n[bridge {stamp()}] auto-ESC\n")
                    tail = b""

    def keyboard(self):
        for line in sys.stdin:
            self.send(line)
            if not self.running:
                break

    def tcp(self, port):
        srv = socket.socket()
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", port))
        srv.listen()
        srv.settimeout(0.5)
        while self.running:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            with conn:
                buf = b""
                while chunk := conn.recv(4096):
                    buf += chunk
                for line in buf.decode().splitlines():
                    self.send(line)
                    time.sleep(0.2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", nargs="?", default="COM8")
    ap.add_argument("--baud", type=int, default=9600)
    ap.add_argument("--log", default=os.path.join(os.path.dirname(__file__), "..", "logs", "ap2_boot.log"))
    ap.add_argument("--tcp", type=int, default=5555)
    ap.add_argument("--no-auto-esc", action="store_true")
    a = ap.parse_args()

    b = Bridge(a.port, a.baud, a.log, auto_esc=not a.no_auto_esc)
    b.emit(f"\n[bridge {stamp()}] opened {a.port} @ {a.baud}, tcp {a.tcp}, "
           f"auto-ESC {'on' if b.auto_esc else 'off'}\n")
    for fn, args in ((b.reader, ()), (b.keyboard, ()), (b.tcp, (a.tcp,))):
        threading.Thread(target=fn, args=args, daemon=True).start()
    try:
        while b.running:
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    b.emit(f"\n[bridge {stamp()}] closed\n")


if __name__ == "__main__":
    main()
