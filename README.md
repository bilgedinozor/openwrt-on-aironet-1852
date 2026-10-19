# OpenWrt on the Cisco Aironet AP1852I

Give a decommissioned Cisco **AIR-AP1852I** access point a second life running mainline
**OpenWrt** — on hardware you own, without an external flash programmer, and without
bricking it.

These access points turn up by the crate-load on the second-hand market when enterprises
refresh their Wi-Fi. They're a genuinely nice little dual-core router board (IPQ8064,
1 GiB RAM, 2× GbE) that would otherwise become e-waste. This repo is the write-up and the
tooling I used to port OpenWrt to one, including the dead ends, so you can repeat it on
yours.

> ⚠️ **Read [Before you start](#2-before-you-start-please) first.** You're replacing
> boot-time firmware. Done the way described here it's reversible and low-risk, but a
> shortcut can leave you with a paperweight. One of my units got bricked early on exactly
> that way — that's *why* the safe path below exists.

> 🧭 **New to serial consoles / U-Boot?** Follow the gentle, checkpointed
> **[step-by-step walkthrough](docs/step-by-step.md)** instead of the condensed [§6](#6-install-step-by-step)
> below. Same procedure, more hand-holding, with a "you should see this" after each step.

---

## Table of contents

1. [What you get & how it works](#1-what-you-get--how-it-works)
2. [Before you start (please)](#2-before-you-start-please)
3. [The hardware](#3-the-hardware)
4. [What you'll need](#4-what-youll-need)
5. [Build OpenWrt](#5-build-openwrt)
6. [Install, step by step](#6-install-step-by-step)
7. [Wi-Fi](#7-wi-fi)
8. [Gotchas worth knowing](#8-gotchas-worth-knowing)
9. [What I tried that didn't work](#9-what-i-tried-that-didnt-work)
10. [Recovering a bricked unit](#10-recovering-a-bricked-unit)
11. [Going back to Cisco](#11-going-back-to-cisco)
12. [Repo layout](#12-repo-layout)
13. [License & credits](#13-license--credits)

---

## 1. What you get & how it works

End state: the AP **cold-boots straight into OpenWrt** with no cable attached and nothing to
press — just like a normal router — and (bonus) its **Wi-Fi works again** through the mainline
`ath10k` driver. Both of the module's radios are ordinary ath10k devices; I've got **2.4 GHz
running as an AP**. **5 GHz is not tested yet**: the radio enumerates the same way, and I
expect it to work once its board-data file is packaged for ath10k (see [§7](#7-wi-fi)), but
I haven't brought it up on any unit so far.

The trick that makes it possible: the stock Cisco U-Boot verifies the firmware image it's
about to boot, but it reads the RSA public key **from inside the image's own certificate**
— there is no separate burned-in root key to check against (the SoC's secure-boot fuses
aren't set). So an image **you** sign with **your own** key is accepted. You wrap a small
second-stage U-Boot as a signed image, put it in one of the two Cisco firmware slots in
NAND, and point the boot selector at it. From then on:

```
power on → stock U-Boot → your signed image (verified against your own key)
         → your U-Boot → OpenWrt in NAND
```

Crucially, this **never writes the SPI flash bootloader** (that's what bricks these boards)
and **keeps the second Cisco slot untouched**, so you can always boot back to stock.

---

## 2. Before you start (please)

- **This is for hardware you own.** It's a right-to-repair / reuse project. Don't point any
  of this at devices or networks that aren't yours.
- **Take backups first — this is the single most important step.** Before writing anything,
  dump and keep, per unit:
  1. the **full 4 MiB SPI NOR** (the boot chain + settings) — *this is the backup that turns
     a future brick into a recoverable unit;*
  2. the **full 256 MiB NAND**, and at least the **Cisco `part2` volume** image;
  3. the **stock U-Boot environment** (`printenv` / `printshenv`).

  Record the **sha256 of `part2`** and re-check it after every NAND write — the method never
  touches `part2`, and verifying that each time is your safety net.
- **Mind the radio.** Transmit power and channels are capped by law per country. Set your
  regulatory domain (see [§8](#8-gotchas-worth-knowing)); the default comes up at a power
  level that's both illegal in most places and disruptive to the Wi-Fi around you.
- **No warranties.** You can brick the unit. If that happens, [§10](#10-recovering-a-bricked-unit).

---

## 3. The hardware

| | |
|---|---|
| **SoC** | Qualcomm IPQ8064, 2× Krait (ARMv7, 32-bit) ~1.4 GHz. *No aarch64.* |
| **RAM / NAND / SPI** | 1 GiB DDR3 / 256 MiB NAND (holds OpenWrt) / 4 MiB SPI NOR (MX25U3235F, **1.8 V**) |
| **Ethernet** | 2× GbE (AR8033 PHY, SGMII), no switch — eth0 = PoE/main, eth1 = aux |
| **Wi-Fi** | Cisco dual-radio module = 2× Qualcomm Atheros QCA9980/9990 (AR900B) |
| **Console** | RJ45 serial, **9600 8N1** |
| **Board** | codename CORSICA, `machid` 0x1260 (same as the AP148 reference board) |

**⚠️ The Wi-Fi slot is a trap.** It looks like mini-PCIe, but Cisco runs two radios over one
connector using *both* of the SoC's PCIe root complexes. Plug a generic mini-PCIe Wi-Fi card in
here and **the board won't power up at all** — no LEDs, no console (I tried this —
[§9](#9-what-i-tried-that-didnt-work)). It's **not damaged, though**: pull the card out and the
board boots normally again. Just use the original Cisco module — it's a perfectly standard
ath10k part once you enable PCIe.

**U-Boot versions differ between production runs** and it matters: newer units (`release 42`,
2023) drop the `go`/`md`/`mw` commands older ones had, but still have `bootipq` / `verify_lx`
/ `ubi` / `tftpboot`, which is all the install needs.

---

## 4. What you'll need

- A **USB RS-232 serial adapter** plus a standard **Cisco RJ45 console cable** — plug it into
  the AP's RJ45 console port, into the adapter, into your PC. Plug-and-play: no soldering, no
  jumper wires, no TTL adapter (the console is RS-232, like other Cisco consoles). 9600 8N1.
- A workstation running a **TFTP server** and a small **HTTP server** on the same LAN
  segment as the AP's eth0.
- A **Linux / WSL build host** to build OpenWrt and the second-stage U-Boot.
- Your **own RSA-2048 signing key** (`e = 65537`). Generate your own — never reuse someone
  else's. Either let `scripts/sign_image.py` create one on first run, or make it yourself:
  `openssl genrsa -out scripts/signing_key.pem 2048`. Keep it private (it's git-ignored).
- A **genuine Cisco boot image** (e.g. from your `part1`/`part2` backup) for `sign_image.py`
  to use as a signature-block *template* — the signer copies that block's layout and drops in
  **your** key and signature; the template itself does no signing.
- The **Cisco board-data blob for the radio**, extracted from *your own* unit's stock
  firmware (not shipped here — see [§7](#7-wi-fi)).

> **⚠️ The IP addresses in this repo are just my examples — use your own.** Throughout the
> guide, `10.0.5.50` is *your workstation's* IP and `10.0.5.201` is a *free* IP on the same
> subnet for the board; substitute values that fit your network (and change the serial port
> `COM8` and the source-tree path `~/ap1852/` too). These appear near the top of the scripts and
> in the two template scripts — edit them before running. The
> [step-by-step walkthrough](docs/step-by-step.md) lists exactly which values to set.

---

## 5. Build OpenWrt

```bash
# builds OpenWrt 24.10.8 for the AP1852 (device profile + DTS + overlay are added for you)
scripts/build_openwrt_release.sh
# builds the small second-stage U-Boot (RAM-loadable, chains OpenWrt from NAND)
scripts/build_uboot.sh
```

What's in `openwrt/`:
- `qcom-ipq8064-ap1852.dts` — the device tree. **PCIe is enabled** for the radio
  (`&pcie0`/`&pcie1 okay`), and the SMB208 CPU/L2 regulators are wired up (without them the
  L2 cache won't clock up and routing throughput stays low).
- `add_ap1852.sh` — drops the DTS, image recipe (`nand-sysupgrade.bin`), network defaults and
  sysupgrade hook into an OpenWrt tree.
- `ap1852_packages.config` — `ath10k-ct` + firmware, `wpad`, LuCI and a router stack.
- `files/` — first-boot defaults applied once via `uci-defaults` scripts:
  - `99-ap1852-perf` — performance (flow offload + packet steering → ~930 Mbit/s routing).
  - `99-ap1852-wifi` — **out-of-the-box Wi-Fi.** The device already boots as a normal OpenWrt
    router (LAN `192.168.1.1` + DHCP + LuCI); edit the three values at the top of this file
    (`COUNTRY`, `SSID`, `KEY`) **before building** and it also brings up a 2.4 GHz AP on first
    power-up. It stays disabled until you set a country **and** a key (no wrong-region or
    insecure default is shipped) — or just leave it and enable Wi-Fi later in LuCI.

**Radio board data:** `add_ap1852.sh` copies `files/` into the image, but the Cisco radio
board file is **not included in this repo** (it's Cisco's proprietary blob). Extract it from
your own unit's stock firmware and drop it at
`openwrt/files/lib/firmware/ath10k/QCA99X0/hw2.0/board.bin` before building — see [§7](#7-wi-fi).

---

## 6. Install, step by step

The order below keeps a known-good Cisco boot available until the very last step, and never
touches the SPI bootloader or `part2`. Prefer the
**[step-by-step walkthrough](docs/step-by-step.md)** if this feels terse — it's the same thing,
slower. **Remember the `10.0.5.x` addresses here are examples — use your own** (your PC's IP and
a free IP on its subnet).

1. **Get to stock U-Boot.** Start the serial bridge in a terminal you can watch, then
   power-cycle; it stops autoboot for you.
   ```bash
   python scripts/serial_bridge.py COM8          # omit --no-auto-esc to catch U-Boot
   python scripts/tftpd.py --bind 10.0.5.50 --root .
   ```
2. **RAM-test first — no writes.** TFTP-boot your signed image and confirm it comes up:
   ```
   setenv serverip 10.0.5.50; setenv ipaddr 10.0.5.201
   setenv bootfile selfsigned.bin; bootipq tftp
   ```
   You should see *"Signature … returns 0"*, your U-Boot, then OpenWrt's RAM image. Check the
   radio here ([§7](#7-wi-fi)) before committing anything.
3. **Create the OpenWrt NAND volumes** with `sysupgrade -n` from that RAM system — it adds
   `kernel`/`rootfs`/`rootfs_data` and **leaves the Cisco `part1`/`part2` volumes alone**.
   First check the layout with `ubinfo -a`: if your unit has **only one UBI volume (`part1`)
   filling the whole NAND** and no `part2`, there's no free space for OpenWrt — read
   [Single-volume units](#single-volume-units-no-part2) in §8 before going on.
4. **Write your signed image into `part1`** from the running system. Use
   `scripts/install_to_part1.sh` — it re-checks the image hash, **confirms the target volume
   is really named `part1`**, records `part2`'s hash before and after, writes, and verifies
   the read-back. (Do flash writes through a checking script like this, not by hand — see
   [§8](#8-gotchas-worth-knowing).)
5. **Point the boot selector at it:** `setshenv BOOT part1; saveshenv` (on units whose Cisco
   firmware already lived in `part1`, it's already set).
6. **Cold-boot test:** power-cycle with no key pressed → it should come straight up in
   OpenWrt.
7. **That's it for a router.** It boots out of the box as a normal OpenWrt router
   (`192.168.1.1` + DHCP + LuCI), and if you set `COUNTRY`/`SSID`/`KEY` in `99-ap1852-wifi`
   (see [§5](#5-build-openwrt)) the 2.4 GHz AP is already up. **Don't plug the LAN into another
   router** (two DHCP servers clash). To instead run it as a **dumb AP** behind an existing
   router, apply `scripts/configure_dumb_ap.sh` (static IP, DHCP server off, Wi-Fi bridged).

If `part1` is ever empty or bad, `bootipq` just falls back to `part2` (Cisco) — so a botched
`part1` doesn't brick the unit.

---

## 7. Wi-Fi

With PCIe enabled, **both** Cisco radios show up as ordinary ath10k devices (`168c:0040`,
QCA9980) — there's nothing special or "broken" about either band; each just needs its matching
Cisco **board-data** file (RF calibration for that radio). Extract these from *your own* unit's
stock firmware; they live under `.../lib/firmware/AR900B/hw.2/` in the Cisco rootfs (a 2.4 GHz
file and a 5 GHz file).

- **2.4 GHz** — working here as an AP. Drop the Cisco 2.4 GHz board file in as
  `board.bin` (see [§5](#5-build-openwrt)) and it comes up.
- **5 GHz** — **not tested yet.** I did 2.4 GHz first and haven't brought 5 GHz up on any
  unit so far. The plan: package the Cisco **5 GHz** board file into an ath10k
  **`board-2.bin`** keyed by the board id (`168c:0002`), rather than a single `board.bin`.
  I expect it to work the same way as 2.4 GHz, but until someone confirms it on hardware,
  treat that as an expectation and not a result. Reports and PRs welcome.

(If a radio is genuinely faulty on a given unit that's a hardware fault, unrelated to the above.)

**Set your regulatory domain.** Out of the box the radio comes up under US/FCC rules at
**30 dBm (1 W)**. At that power this board actually *drowns out* nearby Wi-Fi — other people's
devices drop their connections — and its own throughput suffers. Set your country code and a
sane power (~17 dBm) and it behaves: ~55–60 Mbit/s on 2.4 GHz HT20 to a typical phone. "Long
range" isn't just shouting louder — the link is two-way; use better antennas and legal power.

---

## 8. Gotchas worth knowing

- **The signature check has no root of trust** — this is the whole enabler. Sign with your own
  key; see `docs/signature-format.md` and `scripts/sign_image.py` / `scripts/verify_signature.py`.
- **UBI volume order differs between units.** On one unit `part1` was `ubi0_0`; on another it
  was `ubi0_1`. **Always confirm with `ubinfo /dev/ubi0_<N>` before writing** — a blind write
  to the wrong node overwrites the Cisco slot you meant to keep. The install script checks
  this for you.
- **Serial at 9600 drops characters** when a whole line is sent at once, especially while the
  board is printing. The repo's `serial_bridge.py` paces output **character-by-character**; still,
  send a blank line before each command, send only when the console is quiet, and — above all
  — **run risky flash writes from a self-checking script fetched over HTTP**, not typed. A
  dropped character in a `ubiupdatevol` is how you overwrite the wrong volume.
- **CH340 adapters** sometimes come up "not functioning"; a baud-rate toggle on open fixes it
  (the bridge does this) — no replug needed.
- **Windows blocks ICMP by default**, so `ping` to your workstation fails even when HTTP/SSH
  work. Test reachability with a TCP connect.
- **NAND is only 256 MiB** (the 1 GiB is RAM). On the usual two-slot layout the Cisco slots
  reserve ~60 MiB each; some units have a single-volume layout instead (below).
- Once OpenWrt is on NAND with a reachable IP, do the rest over **SSH/LuCI** — far nicer than
  the 9600-baud console.

### Single-volume units (no `part2`)

Not every unit has the two-slot layout. One of mine had **a single UBI volume, `part1`,
filling the whole NAND** (2024 LEBs, ~245 MiB, holding a Cisco tar archive) and **no `part2`
at all**. On a unit like that `sysupgrade` has no free space, and there's no second Cisco
slot to fall back to.

What I did on that unit (from the RAM-booted OpenWrt, through a checking script):

1. **Back up the volume first:** copy `/dev/ubi0_0` to your PC and compare the sha256 on both
   ends. That image is now your only way back to Cisco on this unit.
2. Have the script **abort before writing anything** unless the volume count is 1, the
   volume is named `part1`, and its hash still matches the backup.
3. Remove the volume and create a **small `part1`** (4 MiB, same name, id 0), then write your
   signed image into it and verify the read-back.
4. Cold-boot test: stock `bootipq` (release 42) accepted the raw signed image from the small
   `part1` and booted into the second-stage U-Boot.
5. Then install OpenWrt as usual. With the whole NAND free, `/overlay` came out at
   **~206 MiB** (vs. ~108 MiB on a two-slot unit).

**The trade-off:** this deletes the only Cisco firmware copy on the unit, so
`setshenv BOOT part2` (§11) won't work there. To go back, recreate a full-size `part1` and
write the backup from step 1 into it.

---

## 9. What I tried that didn't work

Honest dead ends, so you don't repeat them:

- **A generic Intel mini-PCIe Wi-Fi card → board wouldn't power up.** With the card in, no LEDs
  and no console. It did **not** damage anything — removing the card and the board booted
  normally again. The slot is Cisco's proprietary dual-radio wiring, not standard mini-PCIe
  ([§3](#3-the-hardware)); use the original module with ath10k instead.
- **Rewriting the SPI bootloader → brick.** An early attempt left a unit stuck in a
  *"BL signing verification failure"* loop, unrecoverable without an external 1.8 V
  programmer. The entire NAND self-sign method exists specifically to **avoid touching SPI.**
- **Driving the stock environment to auto-chain** was flaky; I reverted it and used the NAND
  self-sign path instead.
- **Trying to boot a RAM image the "simple" way on newer units** fails — `release 42` U-Boot
  lacks `go`/`mw`; use `bootipq tftp` to reach your own U-Boot.
- **Expecting the `files/` overlay in the RAM/initramfs image** — it only lands in the
  installed squashfs, so a pure RAM radio test needs the board file live-patched in.
- **Getting the signature right** took a few tries (modulus vs. signature placement, and the
  exponent is a fixed 65537, not the byte in the cert). The working layout is in
  `docs/signature-format.md`.

---

## 10. Recovering a bricked unit

If the **SPI bootloader** got damaged, the board can't run any of the above and needs the SPI
NOR reflashed externally. Full, **tested** procedure: **[docs/recovery-unbrick.md](docs/recovery-unbrick.md)**.
The short version: the chip is a 1.8 V `MX25U3235F`, so you need **1.8 V-safe** tooling (a CH341A
with a 1.8 V adapter, or a Pi Pico `pico-serprog` + 1.8 V level shifter) and a SOIC-8 clip, plus
the **full SPI backup you took in [§2](#2-before-you-start-please)** — then `flashrom -w` it back.

---

## 11. Going back to Cisco

`setshenv BOOT part2; saveshenv` in stock U-Boot (and/or blank `part1`). Because `part2` was
never written, the original Cisco firmware boots again. That's the whole point of keeping it.

On a [single-volume unit](#single-volume-units-no-part2) there's no `part2`. There, going
back means recreating a full-size `part1` and writing your backup of the original volume
into it.

---

## 12. Repo layout

```
.
├── README.md                 ← you are here
├── docs/
│   ├── step-by-step.md       gentle, checkpointed walkthrough (start here if unsure)
│   ├── signature-format.md   image container + launch ABI (the self-sign details)
│   └── recovery-unbrick.md   SPI reflash recovery (tested procedure)
├── scripts/                  host-side tooling (serial bridge, signer, boot/install helpers, build)
├── openwrt/                  OpenWrt board support: DTS, image recipe, packages, first-boot overlay
└── uboot/patches/            patches for the second-stage U-Boot (GPL-2.0; see uboot/patches)
```

A map of every script is in [`scripts/`](scripts/); each file has a header comment explaining
what it does.

---

## 13. License & credits

- The code and docs in this repo: **MIT** (see [`LICENSE`](LICENSE)).
- The U-Boot patches under `uboot/patches/` are modifications to
  [U-Boot](https://source.denx.de/u-boot/u-boot) / the
  [adron-s/uboot-ipq806x](https://github.com/adron-s/uboot-ipq806x) tree and are therefore
  **GPL-2.0**, inheriting the license of the code they patch.
- OpenWrt, U-Boot and ath10k/ath10k-ct belong to their respective projects.
- **No Cisco firmware or proprietary blobs are redistributed here.** Where the radio needs
  Cisco board data, extract it from your own device.

Built as a right-to-repair / e-waste-reuse project. If you revive a unit with this, a note in
the issues is always welcome — and so are PRs (5 GHz, cleanups, more tested units).
