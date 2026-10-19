# Image container & signature format

Reference for the stock AP1852 boot image format, so you can build and verify your own
signed image. This is a factual description of how the platform validates its own firmware;
the working implementations are [`scripts/sign_image.py`](../scripts/sign_image.py) (build +
sign) and [`scripts/verify_signature.py`](../scripts/verify_signature.py) (independent
check). Everything here is derived from a genuine image on hardware I own.

## Why self-signing is possible

The stock U-Boot path is `bootipq` → `verify_lx` (signature check) → `do_bootm_linux`. The
verifier reads the RSA **public key out of the certificate embedded in the image itself** and
checks the signature against that key. There is no separate burned-in/root key to compare
against, and the SoC secure-boot fuses aren't set. So an image signed with your own key, whose
public key you place in the certificate, verifies successfully (`verify_lx` prints
*"Signature ... returns 0"*). Confirmed on both the older and newer stock bootloaders.

This is what lets you run your own OpenWrt on your own board without an external programmer.

## Container layout

```
0x000  magic 8e73ed8a
0x004  payload offset  = 0x00000400  (big-endian)
0x008  payload size    (big-endian, 32-bit)
0x00c  SHA1(payload)   (20 bytes)
0x020  0xFF padding → 0x400
0x400  payload
       + signature region (templated from a genuine image):
           TLV type 0xae: ... type3 → type4 (256 B) = RSA MODULUS (your public n)
           separator: eb eb eb eb be ef ca fe
           certificate (384 B): ... type11 (256 B) = RSA SIGNATURE ... type12
```

## Signing

- Scheme: **RSA-2048, PKCS#1 v1.5, SHA-512**.
- Public exponent: **65537** (fixed — the verifier uses this, not any exponent byte in the cert).
- Digest input (what gets hashed and signed):
  ```
  SHA512( header + payload + cert[0:120] + cert[379:384] )
  ```
  The `0xae`/modulus block is **not** hashed; the certificate's own signature field is **not**
  hashed.
- Put your key's modulus in the `0xae` type4 field; put your signature in the certificate's
  type11 field.

Common mistakes: swapping the modulus and signature fields, or using an exponent byte from the
certificate instead of the fixed 65537.

## What the payload is

On a successful verify, `bootipq` runs the equivalent of
`bootm 0x45000400 0x45200000` via `do_bootm_linux`. The payload is **two concatenated legacy
uImages**, not a FIT/tar:

- **uImage #1 (kernel)** at payload offset `0x400` (RAM `0x45000400`).
- **uImage #2 (ramdisk)** at payload offset `0x200000` (RAM `0x45200000`).
- The whole image loads at `0x45000000`; boot is **ATAGS** (not FDT), `machid` ≈ `0x1260`.

The practical approach used here: make uImage #1 a small **second-stage U-Boot**
(load/entry `0x44000000`) and uImage #2 a dummy ramdisk. Stock `bootipq` verifies and launches
your U-Boot, which then chains OpenWrt from NAND with its own `bootcmd`.
`scripts/check_uimage.py` dumps the inner uImage headers so you can sanity-check offsets/CRCs.
