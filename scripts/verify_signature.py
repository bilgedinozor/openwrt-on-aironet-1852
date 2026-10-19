"""Offline, read-only confirmation of the AP1852 stock U-Boot image signature
scheme, against a KNOWN-GOOD Cisco image (part.bin). Nothing touches the board.

It parses the Cisco container + signature block, pulls the RSA public key out of
the embedded certificate, recovers the expected SHA-512 digest from the signature
(sig^e mod n -> PKCS#1 v1.5), then searches which data coverage reproduces that
digest. If a coverage matches, the self-signed-image finding is confirmed and the
exact byte layout for a signer is known.

Usage: python3 sig_poc_verify.py ./cisco-stock-part.bin
"""
import hashlib
import sys

MAGIC_IMG = 0x8e73ed8a
MAGIC_SIG = 0xAB1234CD
SHA512_DIGESTINFO = bytes.fromhex("3051300d060960864801650304020305000440")


def be(b):
    return int.from_bytes(b, "big")


def tlv_walk(buf, start, end):
    """Yield (type, length, value_offset, value) for [type:1][len:2 BE][value]."""
    i = start
    while i + 3 <= end:
        t = buf[i]
        ln = be(buf[i + 1:i + 3])
        vo = i + 3
        if vo + ln > end:
            break
        yield t, ln, vo, buf[vo:vo + ln]
        i = vo + ln


def main():
    path = sys.argv[1]
    data = open(path, "rb").read()
    n = len(data)
    print(f"file: {path}  size: {n} (0x{n:x})")

    assert be(data[0:4]) == MAGIC_IMG, "image magic mismatch"
    size_field = be(data[8:12])
    print(f"magic ok; header size field @0x08 = {size_field} (0x{size_field:x})")

    # Locate signature block by its magic 0xAB1234CD.
    sig_magic_off = data.find(MAGIC_SIG.to_bytes(4, "big"))
    print(f"sig magic 0xAB1234CD @ 0x{sig_magic_off:x}")
    # TLV for the signature region begins 3 bytes before the magic value
    # (type 0xae, 2-byte len, then value starting with the magic).
    sig_tlv_start = sig_magic_off - 3
    print(f"sig TLV start @ 0x{sig_tlv_start:x}  type=0x{data[sig_tlv_start]:02x} "
          f"len=0x{be(data[sig_tlv_start+1:sig_tlv_start+3]):x}")

    # Certificate starts right after the separator marker 'ef ca fe'.
    sep = data.find(b"\xef\xca\xfe", sig_tlv_start)
    cert_start = sep + 3
    print(f"separator 'ef ca fe' @ 0x{sep:x}  cert_start @ 0x{cert_start:x} "
          f"(= sig_tlv_start+0x{cert_start - sig_tlv_start:x})")
    modulus = exponent = None
    cert_end = None
    for t, ln, vo, val in tlv_walk(data, cert_start, n):
        if t == 0x0b and ln == 256:
            modulus = val
            print(f"  TLV 0x0b modulus (256) @ 0x{vo:x}")
        elif t == 0x0c and modulus is not None and exponent is None:
            exponent = be(val)
            cert_end = vo + ln
            print(f"  TLV 0x0c exponent len {ln} @ 0x{vo:x} value={exponent}; "
                  f"cert_end @ 0x{cert_end:x} (file end 0x{n:x})")
            break
    assert modulus and exponent, "could not extract modulus/exponent"
    nmod = be(modulus)
    print(f"RSA modulus bits: {nmod.bit_length()}  exponent: {exponent}")

    # The 256-byte RSA signature lives inside the signature TLV value.
    sig_val_start = sig_magic_off  # value starts at the magic
    sig_val_len = be(data[sig_tlv_start + 1:sig_tlv_start + 3])
    sig_val = data[sig_val_start:sig_val_start + sig_val_len]
    # The signature is the last 256 bytes of a modexp-sized field; try the last
    # 256 bytes of the value, and also a scan for a 256-byte run that verifies.
    candidates = []
    if len(sig_val) >= 256:
        candidates.append(("tail", sig_val[-256:]))
    # also every 256-byte aligned-ish window in the sig value
    for off in range(0, max(1, len(sig_val) - 256 + 1)):
        candidates.append((f"off+{off}", sig_val[off:off + 256]))

    def recover_digest(sig_bytes):
        s = be(sig_bytes)
        if s >= nmod:
            return None
        m = pow(s, exponent, nmod)
        em = m.to_bytes(256, "big")
        # EM = 00 01 FF..FF 00 || DigestInfo || hash
        if em[0] != 0x00 or em[1] != 0x01:
            return None
        try:
            sep = em.index(0x00, 2)
        except ValueError:
            return None
        tail = em[sep + 1:]
        if not tail.startswith(SHA512_DIGESTINFO):
            return None
        return tail[len(SHA512_DIGESTINFO):len(SHA512_DIGESTINFO) + 64]

    expected = None
    sig_used = None
    for label, cand in candidates:
        d = recover_digest(cand)
        if d:
            expected = d
            sig_used = (label, cand)
            print(f"VALID PKCS#1 v1.5 structure from signature [{label}]")
            print(f"expected SHA-512 digest = {d.hex()}")
            break
    if not expected:
        print("No candidate signature yielded a valid PKCS#1 v1.5 SHA-512 structure.")
        print("(Need to refine signature location / padding.)")
        return

    # Now find which data coverage reproduces this digest.
    def sha(*chunks):
        h = hashlib.sha512()
        for c in chunks:
            h.update(c)
        return h.digest()

    img = data[0:sig_tlv_start]          # header+payload = up to the sig block
    trials = {
        "img only [0:sig_tlv_start]": (img,),
        "img + cert[cert_start:end]": (img, data[cert_start:n]),
        "img + cert[cert_start:cert_end]": (img, data[cert_start:cert_end]),
        "img + sep..end [sig_tlv:end minus sig?]": (img, data[sep:n]),
        "img + wholecert incl sep": (img, data[sig_tlv_start + 0x228:n]),
    }
    hit = False
    for name, chunks in trials.items():
        if sha(*chunks) == expected:
            total = sum(len(c) for c in chunks)
            print(f"*** MATCH: coverage = '{name}'  ({total} bytes) ***")
            hit = True
    if not hit:
        print("No tried coverage matched; will iterate on exact regions.")
        print(f"(img_end=0x{img_end:x}, file end=0x{n:x})")


if __name__ == "__main__":
    main()
