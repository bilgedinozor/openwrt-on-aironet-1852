"""Build a Cisco-AP1852-format signed image around an arbitrary payload, using
your OWN RSA key, so the user's own OpenWrt boots on the user's own AP1852.
The stock U-Boot's bootipq/verify_lx reads the RSA public modulus from the
image's own certificate, so an image signed with your own key, carrying that
key's public half, is accepted. Right-to-repair / reuse; offline, nothing here touches
the board.

Scheme (confirmed against the genuine part.bin, see docs/sig_analysis.md):
  header(0x400): magic 8e73ed8a | off=0x400 | payload_size BE | SHA1(payload) | FF
  payload @ 0x400
  sig region (944B, templated from a genuine image):
    0xae TLV: ... type3 -> type4(256B) = MODULUS  (your public n)
    separator: eb eb eb eb be ef ca fe
    cert(384B): ... type11(256B) = SIGNATURE (your RSA signature)
  verify: pow(sig, 65537, modulus) == PKCS#1v1.5( SHA512(
             header+payload  +  cert[0:120]  +  cert[379:384] ) )

Usage:
  python3 sign_image.py --payload tftp/uboot_ap1852.bin --out tftp/selfsigned.bin \
      --template ./cisco-stock-part.bin --key tools/signing_key.pem
"""
import argparse
import hashlib
import os
import struct
import sys
import zlib

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa, utils

MAGIC_IMG = bytes.fromhex("8e73ed8a")
MAGIC_SIG = (0xAB1234CD).to_bytes(4, "big")
E = 65537

# --- legacy uImage (what stock bootipq feeds to do_bootm_linux) ---------------
UIMG_MAGIC = 0x27051956
IH_OS_LINUX, IH_ARCH_ARM = 5, 2
IH_TYPE_KERNEL, IH_TYPE_RAMDISK = 2, 3
IH_COMP_NONE = 0
# bootipq hardcodes: bootm 0x45000400 (kernel @ image+0x400) 0x45200000 (rd @ image+0x200000)
RAMDISK_IMG_OFF = 0x200000
HDR_LEN = 0x400
# the second-stage U-Boot is built for TEXT_BASE 0x44000000 (same as `go 0x44000000`)
UBOOT_LOADADDR = 0x44000000


def mkuimage(data, ih_type, load, ep, name, comp=IH_COMP_NONE,
             os_=IH_OS_LINUX, arch=IH_ARCH_ARM):
    """Build a 64-byte legacy uImage header + data (all fields big-endian)."""
    name_b = name.encode()[:31].ljust(32, b"\x00")
    dcrc = zlib.crc32(data) & 0xffffffff
    hdr = struct.pack(">IIIIIIIBBBB32s",
                      UIMG_MAGIC, 0, 0, len(data), load, ep, dcrc,
                      os_, arch, ih_type, comp, name_b)
    hcrc = zlib.crc32(hdr) & 0xffffffff
    hdr = struct.pack(">IIIIIIIBBBB32s",
                      UIMG_MAGIC, hcrc, 0, len(data), load, ep, dcrc,
                      os_, arch, ih_type, comp, name_b)
    return hdr + data


def build_uboot_payload(uboot):
    """Two concatenated uImages, the layout stock bootipq expects:
    kernel uImage (= the second-stage U-Boot) at payload offset 0, ramdisk uImage at the
    offset that lands it at image+0x200000. bootipq's do_bootm_linux copies the
    'kernel' to UBOOT_LOADADDR and jumps there; the second-stage U-Boot then chains OpenWrt."""
    kern = mkuimage(uboot, IH_TYPE_KERNEL, UBOOT_LOADADDR, UBOOT_LOADADDR, "ap1852-uboot")
    rd = mkuimage(b"\x00", IH_TYPE_RAMDISK, 0, 0, "ap1852-dummy-rd")
    rd_off = RAMDISK_IMG_OFF - HDR_LEN            # offset within payload
    assert len(kern) <= rd_off, "U-Boot uImage overruns the ramdisk slot"
    return kern + b"\xff" * (rd_off - len(kern)) + rd


def load_or_make_key(path):
    if os.path.exists(path):
        with open(path, "rb") as f:
            return serialization.load_pem_private_key(f.read(), password=None)
    key = rsa.generate_private_key(public_exponent=E, key_size=2048)
    with open(path, "wb") as f:
        f.write(key.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption()))
    print(f"generated new RSA-2048 key -> {path}")
    return key


def sig_region_layout(tpl):
    """Locate, in a genuine image, the 944-byte signature region and the
    offsets (within it) of the modulus field and the signature field."""
    sm = tpl.find(MAGIC_SIG)
    sig_tlv_start = sm - 3
    region = tpl[sig_tlv_start:]
    mod_off = (sm - sig_tlv_start) + 18            # 0xae value[18:] = type4 modulus
    sep = region.find(b"\xef\xca\xfe")
    cert_off = sep + 3
    # signature field = cert TLV type 0x0b (len 256)
    t11 = region.find(b"\x0b\x01\x00", cert_off) + 3
    return region, mod_off, cert_off, t11


def build(payload, key, tpl):
    region, mod_off, cert_off, sig_off = sig_region_layout(tpl)
    region = bytearray(region)

    # header
    hdr = bytearray(b"\xff" * 0x400)
    hdr[0:4] = MAGIC_IMG
    hdr[4:8] = (0x400).to_bytes(4, "big")
    hdr[8:12] = len(payload).to_bytes(4, "big")
    hdr[0x0c:0x20] = hashlib.sha1(payload).digest()

    # modulus of your key into the 0xae type4 field
    n = key.public_key().public_numbers().n
    region[mod_off:mod_off + 256] = n.to_bytes(256, "big")

    # hash coverage: header+payload + cert[0:120] + cert[379:384]
    cert = region[cert_off:cert_off + 384]
    digest = hashlib.sha512(bytes(hdr) + payload + bytes(cert[0:120]) + bytes(cert[379:384])).digest()

    # sign the prehashed digest, PKCS#1 v1.5 / SHA-512
    signature = key.sign(digest, padding.PKCS1v15(), utils.Prehashed(hashes.SHA512()))
    assert len(signature) == 256
    region[sig_off:sig_off + 256] = signature

    return bytes(hdr) + payload + bytes(region)


def verify(image, tpl):
    """Independent check that bootipq/verify_lx would accept this image."""
    be = lambda b: int.from_bytes(b, "big")
    size = be(image[8:12])
    assert hashlib.sha1(image[0x400:0x400 + size]).digest() == image[0x0c:0x20], "SHA1 hdr bad"
    region, mod_off, cert_off, sig_off = sig_region_layout(image)
    n = be(region[mod_off:mod_off + 256])
    s = be(region[sig_off:sig_off + 256])
    em = pow(s, E, n).to_bytes(256, "big")
    if em[:2] != b"\x00\x01":
        return False, "padding"
    sep = em.index(0, 2)
    OID = bytes.fromhex("3051300d060960864801650304020305000440")
    if not em[sep + 1:].startswith(OID):
        return False, "digestinfo"
    want = em[sep + 1 + len(OID):sep + 1 + len(OID) + 64]
    cert = region[cert_off:cert_off + 384]
    got = hashlib.sha512(image[0:size + 0x400] + cert[0:120] + cert[379:384]).digest()
    return (got == want), got.hex()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--payload", help="raw payload bytes (verify_lx-only test image)")
    ap.add_argument("--uboot", help="wrap this U-Boot binary as kernel uImage + dummy "
                                    "ramdisk uImage (bootable via stock bootipq)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--template", default="./cisco-stock-part.bin")
    ap.add_argument("--key", default=os.path.join(os.path.dirname(__file__), "signing_key.pem"))
    a = ap.parse_args()

    if a.uboot:
        payload = build_uboot_payload(open(a.uboot, "rb").read())
        kind = f"two-uImage (U-Boot kernel @0x400 + ramdisk @0x{RAMDISK_IMG_OFF:x})"
    elif a.payload:
        payload = open(a.payload, "rb").read()
        kind = "raw"
    else:
        ap.error("give --uboot or --payload")

    tpl = open(a.template, "rb").read()
    key = load_or_make_key(a.key)
    img = build(payload, key, tpl)
    open(a.out, "wb").write(img)
    ok, info = verify(img, tpl)
    print(f"payload={len(payload)}B ({kind})  image={len(img)}B -> {a.out}")
    print(f"self-verify: {'PASS' if ok else 'FAIL'}  hash/{info[:32]}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
