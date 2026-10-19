# Recovering a bricked unit (external SPI reflash)

If the **SPI NOR bootloader** got corrupted, the board can't run any of the normal method — it
needs the 4 MiB SPI chip reflashed with an external programmer. This procedure is **proven**:
I used it to bring a unit back that was stuck in a *"BL signing verification failure"* loop
(its U-Boot had 16 bytes changed — a version string overwritten — which was enough to break the
signature and stop it booting).

> You only need this if SPI got damaged. The normal install never writes SPI, so if you followed
> the main guide you should never end up here.

## ⚠️ Voltage — read this first

The chip is a **Macronix MX25U3235F, 1.8 V**. **A plain 3.3 V/5 V programmer will damage it.**
You must drive it at **1.8 V logic**. Two setups that work:

- A **CH341A** programmer **with a 1.8 V adapter** (the bare black CH341A board is 3.3 V — not
  safe on its own; the 1.8 V adapter sits between it and the chip). ← this is what I used.
- A **Raspberry Pi Pico** running `pico-serprog` with a **1.8 V level shifter**.

Either way you also want a **SOIC-8 test clip** so you can reflash in-circuit without
desoldering, and `flashrom` on your host.

## What you need

- The programmer + 1.8 V adapter/level-shifter + SOIC-8 clip + jumper wires.
- Your **full SPI backup** from before you started (main README §2). This is what you write
  back. *Without it, recovery is much harder — this is why that backup matters.*
- `flashrom` (Linux; on Windows use WSL and pass the USB device in with `usbipd`).

## Steps

### 1. Clip onto the chip (power off)

Attach the SOIC-8 clip to the SPI chip. **Find pin 1** by the dot/bevel on the chip; if it's
unclear, a continuity check helps — **pin 4 is GND**, so the pin that beeps to a known ground is
pin 4, which orients the rest. Connect the programmer through the 1.8 V adapter. Keep the AP
powered off while you probe.

### 2. (Windows) hand the programmer to WSL

If you're on Windows driving flashrom from WSL, pass the USB device in with `usbipd`:

```bash
usbipd list                                 # find the programmer's BUSID (e.g. 1-9)
usbipd bind   --busid <BUSID>               # once, as admin
usbipd attach --wsl --busid <BUSID>
```
Then run flashrom inside WSL as root (`wsl -u root`, or `sudo`).

### 3. Confirm a stable chip ID — reseat until consistent

A bad clip contact is the most common problem and gives wrong/garbage reads. Probe a few times:

```bash
flashrom -p ch341a_spi          # (or: -p serprog:dev=/dev/ttyACM0 for a Pico)
```

**You should see** it detect `MX25U3235E/F` (JEDEC id **C2 25 36**) **the same way several times
in a row**. On my run the first seatings gave garbage/unstable ids (e.g. `0x00` / `0xC0`);
after reseating the clip it read correctly and consistently (5/5). Do **not** write until you
get three-plus identical, correct reads.

### 4. Back up the broken state first

Even though it's broken, dump it — it's evidence and a fallback:

```bash
flashrom -p ch341a_spi -c "MX25U3235E/F" -r broken-spi.bin
flashrom -p ch341a_spi -c "MX25U3235E/F" -r broken-spi-2.bin
sha256sum broken-spi.bin broken-spi-2.bin     # the two should match
```

### 5. Write your known-good backup

```bash
flashrom -p ch341a_spi -c "MX25U3235E/F" -w your-spi-backup.bin
```
flashrom writes and then **verifies** automatically. For extra confidence, read it back twice
and confirm both match your backup's sha256:

```bash
flashrom -p ch341a_spi -c "MX25U3235E/F" -r check-1.bin
flashrom -p ch341a_spi -c "MX25U3235E/F" -r check-2.bin
sha256sum check-1.bin check-2.bin your-spi-backup.bin   # all three identical
```

### 6. Power on and confirm

Remove the clip, power the AP, watch the serial console.

**You should see** the bootloader reach *"BL signing verification success"* and go on to boot
(whatever is in its NAND slots). That's the chip recovered — from here the normal method works
again.

## Notes from the real recovery

- The damage was tiny: **16 bytes** at one offset (a U-Boot version string). A single changed
  byte in the signed region is enough to brick it — which is exactly why the normal method never
  touches SPI, and why the pre-work SPI backup is non-negotiable.
- The console serial adapter and the SPI programmer are two different USB devices; don't confuse
  their ports.
- If you had removed Cisco entirely from NAND, note that SPI recovery only fixes the bootloader
  — you still boot whatever is in NAND afterwards (your OpenWrt, or re-install it).
