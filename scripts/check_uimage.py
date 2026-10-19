"""Inspect the two legacy uImages inside a signed AP1852 boot image.

Prints each inner uImage's header fields (magic, type, OS, arch, compression,
load/entry address, size, name) and whether its header-CRC and data-CRC check
out — a quick sanity check that `sign_image.py --uboot` produced a well-formed
image before you flash or boot it. The layout it expects: kernel uImage at
offset 0x400, ramdisk uImage at 0x200000 (see docs/signature-format.md).

Usage: python check_uimage.py <image.bin>
"""
import struct, zlib, sys

d = open(sys.argv[1], "rb").read()
be = lambda b: int.from_bytes(b, "big")
print("img size", len(d), hex(len(d)))
print("hdr magic", d[:4].hex(), "payload_off", hex(be(d[4:8])), "size", hex(be(d[8:12])))


def chk(off, label):
    h = d[off:off + 64]
    magic, hcrc, t, size, load, ep, dcrc, os_, arch, typ, comp = struct.unpack(">IIIIIIIBBBB", h[:32])
    name = h[32:64].split(b"\x00")[0].decode(errors="replace")
    h0 = bytearray(h); h0[4:8] = b"\x00\x00\x00\x00"
    hcrc_ok = (zlib.crc32(bytes(h0)) & 0xffffffff) == hcrc
    data = d[off + 64:off + 64 + size]
    dcrc_ok = (zlib.crc32(data) & 0xffffffff) == dcrc
    print(f"{label} @0x{off:x}: magic={magic:08x} type={typ} os={os_} arch={arch} "
          f"comp={comp} load=0x{load:x} ep=0x{ep:x} size={size} name={name!r} "
          f"hcrc_ok={hcrc_ok} dcrc_ok={dcrc_ok}")


chk(0x400, "kernel uImage")
chk(0x200000, "ramdisk uImage")
