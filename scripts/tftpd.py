"""Minimal TFTP server (RFC 1350 + blksize option) for the bench.

Reads AND writes, so the board can both fetch images from you (U-Boot) and
upload backups to you (from OpenWrt: `tftp -p -l /tmp/file -r file <PC_IP>`).

Usage: python tftpd.py [--bind 10.0.5.50] [--root .]
Files are read from / written into <root> only (no path escape).
Uploads overwrite an existing file of the same name in <root>.
"""
import argparse
import os
import socket
import struct
import threading

RRQ, WRQ, DATA, ACK, ERROR, OACK = 1, 2, 3, 4, 5, 6


def safe_path(root, filename):
    path = os.path.realpath(os.path.join(root, filename))
    if not path.startswith(os.path.realpath(root) + os.sep):
        return None
    return path


def send_wait_ack(s, client, pkt, block):
    """Send a packet, wait for ACK of `block` (retransmit up to 8 times)."""
    for _ in range(8):
        s.sendto(pkt, client)
        try:
            while True:
                resp, addr = s.recvfrom(1024)
                if addr != client or len(resp) < 4:
                    continue
                op, num = struct.unpack("!HH", resp[:4])
                if op == ACK and num == block:
                    return True
                if op == ERROR:
                    return False
        except socket.timeout:
            continue
    return False


def serve_read(root, client, filename, opts):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(1.0)
    path = safe_path(root, filename)
    if not path or not os.path.isfile(path):
        s.sendto(struct.pack("!HH", ERROR, 1) + b"File not found\0", client)
        print(f"[tftpd] {client[0]} GET {filename}: not found")
        return
    data = open(path, "rb").read()
    blksize = 512
    if "blksize" in opts:
        blksize = max(8, min(int(opts["blksize"]), 1468))
        oack = struct.pack("!H", OACK) + b"blksize\0" + str(blksize).encode() + b"\0"
        if not send_wait_ack(s, client, oack, 0):
            return
    nblocks = len(data) // blksize + 1
    for n in range(1, nblocks + 1):
        chunk = data[(n - 1) * blksize:n * blksize]
        if not send_wait_ack(s, client, struct.pack("!HH", DATA, n & 0xFFFF) + chunk, n & 0xFFFF):
            print(f"[tftpd] {client[0]} GET {filename}: timeout at block {n}")
            return
    print(f"[tftpd] {client[0]} GET {filename}: sent {len(data)} bytes")


def serve_write(root, client, filename, opts):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(1.0)
    path = safe_path(root, filename)
    if not path:
        s.sendto(struct.pack("!HH", ERROR, 2) + b"Bad path\0", client)
        return
    blksize = 512
    if "blksize" in opts:
        blksize = max(8, min(int(opts["blksize"]), 1468))
        ack0 = struct.pack("!H", OACK) + b"blksize\0" + str(blksize).encode() + b"\0"
    else:
        ack0 = struct.pack("!HH", ACK, 0)

    buf = bytearray()
    expect = 1
    # acknowledge the WRQ (OACK if options, else ACK 0), then collect DATA blocks
    for _ in range(8):
        s.sendto(ack0, client)
        try:
            resp, addr = s.recvfrom(blksize + 4)
        except socket.timeout:
            continue
        if addr == client and len(resp) >= 4 and struct.unpack("!HH", resp[:4]) == (DATA, 1):
            payload = resp[4:]
            buf += payload
            s.sendto(struct.pack("!HH", ACK, 1), client)
            expect = 2
            if len(payload) < blksize:
                break
            while True:
                try:
                    resp, addr = s.recvfrom(blksize + 4)
                except socket.timeout:
                    break
                if addr != client or len(resp) < 4:
                    continue
                op, num = struct.unpack("!HH", resp[:4])
                if op != DATA:
                    break
                if num == expect:
                    payload = resp[4:]
                    buf += payload
                    s.sendto(struct.pack("!HH", ACK, num), client)
                    expect = (expect + 1) & 0xFFFF
                    if len(payload) < blksize:
                        break
                else:
                    s.sendto(struct.pack("!HH", ACK, num), client)  # re-ack duplicate
            break
    open(path, "wb").write(bytes(buf))
    print(f"[tftpd] {client[0]} PUT {filename}: received {len(buf)} bytes -> {path}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bind", default="10.0.5.50")
    ap.add_argument("--root", default=".")
    a = ap.parse_args()
    root = os.path.realpath(a.root)
    srv = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    srv.bind((a.bind, 69))
    print(f"[tftpd] read+write, serving {root} on {a.bind}:69")
    while True:
        pkt, client = srv.recvfrom(1024)
        op = struct.unpack("!H", pkt[:2])[0]
        parts = pkt[2:].split(b"\0")
        filename = parts[0].decode(errors="replace")
        opts = {parts[i].decode().lower(): parts[i + 1].decode()
                for i in range(2, len(parts) - 1, 2) if parts[i]}
        if op == RRQ:
            print(f"[tftpd] {client[0]} RRQ {filename} {opts}")
            threading.Thread(target=serve_read, args=(root, client, filename, opts), daemon=True).start()
        elif op == WRQ:
            print(f"[tftpd] {client[0]} WRQ {filename} {opts}")
            threading.Thread(target=serve_write, args=(root, client, filename, opts), daemon=True).start()
        else:
            srv.sendto(struct.pack("!HH", ERROR, 4) + b"Illegal op\0", client)


if __name__ == "__main__":
    main()
