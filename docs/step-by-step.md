# Step-by-step walkthrough — for absolute beginners

This guide assumes you know **nothing** about serial consoles, U-Boot, or OpenWrt. If you have
the access point, an **RS-232-to-USB adapter**, a **Cisco RJ45 console cable**, and a computer,
you can do this by copying each command exactly. Take it slowly; there's a checkpoint after
almost every step so you know it worked before continuing.

Just follow the parts **in order, top to bottom** — no jumping around.

> 🛟 **The golden safety rule:** nothing you do is permanent until **Part 6**. Parts 0–5 only
> read the device or load things into its memory (RAM), which a power-cycle wipes. If anything
> looks wrong, pull the power, plug it back in, and start the part over. Don't improvise flash
> (permanent memory) commands.

---

## How to read this guide: two windows

You will constantly switch between **two different places to type**. Every command below is
tagged so you always know which one:

- 💻 **PC window** — a normal terminal on your computer (PowerShell on Windows, Terminal on
  Mac/Linux). These run programs *on your computer*.
- 🖧 **AP window** — the "serial bridge" window you'll open in Part 1. Whatever you type here
  travels down the console cable and runs **on the access point itself**.

(For building the firmware in Part 2 you'll also use a 🐧 **Linux window** — WSL/Ubuntu.)

If you type an AP command into the PC window (or vice-versa) it just won't work — no harm done,
just check the tag and try again.

There's a plain-language **[glossary](#glossary)** at the bottom. If a word is unfamiliar, look
there first.

---

## Part 0 — Set up your computer (one time)

You need **Python** (runs the repo's helper tools) and, for building the firmware, a **Linux
environment**.

### 0.1 Install Python

- **Windows:** 💻 open PowerShell and run:
  ```powershell
  winget install Python.Python.3.12
  ```
  Close and reopen PowerShell, then check:
  ```powershell
  python --version
  ```
  **You should see:** something like `Python 3.12.x`.
- **Mac:** `brew install python`  •  **Linux:** it's almost certainly already there.

### 0.2 Install the one Python add-on you need

💻 In the PC window:
```
python -m pip install pyserial
```
This lets the tools talk to the serial adapter.

### 0.3 Get these files onto your PC

Download/clone this repository to a folder, e.g. `Documents\ap1852`. 💻 Then move into it:
```
cd Documents\ap1852\openwrt-on-aironet-1852
```
Every command that mentions `scripts/...` assumes you're sitting in this folder.

### 0.4 (For building firmware) install Linux / WSL

Building OpenWrt needs Linux. On Windows the easy route is **WSL**. 💻 In PowerShell **as
Administrator**:
```powershell
wsl --install -d Ubuntu
```
Reboot if asked, pick a username/password when Ubuntu first opens, then inside the 🐧 **Ubuntu**
window install the build tools:
```
sudo apt update
sudo apt install -y build-essential clang flex bison g++ gawk gcc-multilib g++-multilib gettext git libncurses-dev libssl-dev python3-distutils rsync unzip zlib1g-dev file wget
```
> Building from source is the most involved part of this whole project. If it's too much, that's
> OK — the hard-to-follow bits are *building*, not *installing*. You can ask someone to build the
> images for you; everything else is the easy part.

---

## Part 1 — Connect to the access point and reach its prompt

### 1.1 Plug in the cable

Connect: **AP console port (RJ45) → Cisco console cable → RS-232-to-USB adapter → PC USB port.**
No soldering, no loose wires. The console port is the RJ45 socket labelled "CONSOLE".

### 1.2 Find which "COM port" the adapter is

- **Windows:** open **Device Manager** → expand **Ports (COM & LPT)** → find your adapter, e.g.
  **USB-SERIAL CH340 (COM8)**. The `COM8` part is what you need (yours may be COM3, COM5, …).
- **Mac/Linux:** 💻 run `ls /dev/tty.*` or `ls /dev/ttyUSB*` and note the name (e.g.
  `/dev/ttyUSB0`).

Wherever you see **`COM8`** below, use *your* port name.

### 1.3 Open the "AP window" (serial bridge)

💻 In the PC window, start the bridge — this becomes your **🖧 AP window** from now on:
```
python scripts/serial_bridge.py COM8
```
**You should see:** `[bridge ...] opened COM8 @ 9600`. Leave this window open. To send a command
to the AP, **type it in this window and press Enter.**

### 1.4 Power on the AP and catch it

Plug in the AP's power (or PoE injector). Watch the 🖧 AP window.

**You should see:** lots of startup text, then it stops at a prompt like:
```
(RNAQ-C7) #
```
(Letters may differ.) That's the AP's **bootloader** waiting for you — the bridge pressed the
"stop" key automatically. **You're now in control of the AP.**

> 💡 If it booted all the way into old Cisco software (you see `Username:`), just pull the power
> and plug it back in — the bridge will catch it this time.
>
> 💡 **The first thing you type after it stops is sometimes ignored.** Always press **Enter**
> once in the AP window before your first real command.

---

## Part 2 — Build the firmware and sign it (Linux/WSL)

This makes the two files you'll load onto the AP: the **OpenWrt** system image and a small
**signed boot image** (`selfsigned.bin`) that the AP's bootloader will accept.

### 2.1 Build OpenWrt and the little boot loader

🐧 In the Ubuntu/Linux window:
```
scripts/build_openwrt_release.sh
scripts/build_uboot.sh
```
These download OpenWrt, add support for this AP, and compile. First run takes tens of minutes.
When done you have an OpenWrt `...-nand-sysupgrade.bin` and a `uboot_ap1852.bin`.

### 2.2 Make your own signing key (one time)

The bootloader accepts a boot image if it's signed by the key **inside that image** — so you
sign with **your own** key. Make one:
```
openssl genrsa -out scripts/signing_key.pem 2048
```
Keep this file private (the repo's `.gitignore` already hides it). It isn't a master key — the AP would
accept anyone's — but treat it like a password. Lose it? Just make a new one and redo Part 5.

### 2.3 Get a genuine Cisco image to use as a *template*

The signing tool copies the **structure** of the signature block from a real Cisco image, then
drops in **your** key and signature. So you need one genuine Cisco AP1852 firmware image, saved
as `cisco-stock-part.bin` in the repo folder. Where to get it:

- If you **already have** a Cisco AP1852 firmware image or an earlier dump → use that.
- If not → you'll make a dump of it in **Part 4** (the backup step). On most units the simplest
  path is: do a one-off and keep the `part2` dump from Part 4 as this template. **If you have no
  image at all yet,** the catch is that signing (needed to boot OpenWrt in Part 3) wants the
  template first. Two ways out:
  - **Easiest:** obtain the AP1852's Cisco firmware image from your own device/records and use it.
  - **Older units only:** if your bootloader has a `go` command, you can boot OpenWrt in RAM
    *without* signing, dump `part2`, and use that (ask in the issues — this is the one advanced
    branch).

The signer only reads the template's layout; your key is what actually signs.

### 2.4 Build the signed boot image

With `cisco-stock-part.bin` in the repo folder:
```
scripts/sign_image.py --uboot uboot_ap1852.bin --template ./cisco-stock-part.bin --key scripts/signing_key.pem --out selfsigned.bin
```
**You should see:** a line ending `self-verify: PASS`. That means an independent check matched
exactly what the AP will do — your image will be accepted. If it says `FAIL`, stop and re-check
the two file paths.

### 2.5 (Optional, for Wi-Fi) add the radio's calibration file *before* building

If you want Wi-Fi, copy the Cisco **board-data** file out of the stock firmware to
`openwrt/files/lib/firmware/ath10k/QCA99X0/hw2.0/board.bin` **before** running
`build_openwrt_release.sh` in 2.1. See the main README's "Wi-Fi" section for where it lives. You
can skip this and add Wi-Fi later.

---

## Part 3 — Try OpenWrt in RAM (nothing permanent yet)

This proves your images work on *your* unit before you write anything. A power-cycle undoes it.

### 3.1 Start the file server on your PC

This tool sends files to the AP (and later receives backups from it). 💻 Open a **second** PC
window, `cd` into the repo folder, and start it with **your PC's own IP**.

First find your PC's IP — 💻 `ipconfig` (Windows) or `ip addr` (Mac/Linux); note the IPv4 address
of the network the AP is cabled to, e.g. `10.0.5.50`. **That's an example — use yours.** Then:
```
python scripts/tftpd.py --bind 10.0.5.50 --root .
```
**You should see:** `[tftpd] read+write, serving ... on 10.0.5.50:69`. Leave it running.

> From here on, your PC's address is called **PC_IP**. Pick an unused address on the same
> network for the AP and call it **BOARD_IP** (e.g. PC_IP `10.0.5.50` → BOARD_IP `10.0.5.201`).
> Make sure nothing else uses BOARD_IP.

### 3.2 Load OpenWrt into the AP's memory and run it

Make sure `selfsigned.bin` and the OpenWrt `...-nand-sysupgrade.bin` are in the repo folder (the
server is sharing it). In the 🖧 AP window, at the `(RNAQ-C7) #` prompt, press **Enter** once,
then type these one at a time (replace PC_IP / BOARD_IP with your numbers):
```
setenv serverip PC_IP
setenv ipaddr BOARD_IP
setenv bootfile selfsigned.bin
bootipq tftp
```
(`setenv` = "remember this value"; `bootipq tftp` = "download the boot image from my PC and run
it".)

**You should see:** `Signature ... returns 0` (your image was accepted ✅), then boot text,
ending at a Linux prompt:
```
root@OpenWrt:~#
```
🎉 OpenWrt is running in memory. If you **didn't** reach `root@OpenWrt`, stop — don't continue.
Re-check Part 2 and your PC_IP/BOARD_IP.

---

## Part 4 — Back up the AP (still nothing written)

Now that OpenWrt is running, taking backups is easy — and this is your safety net if a later
step goes wrong. **Do not skip this.** You're still only *reading* the AP here.

### 4.1 See what's on the flash

In the 🖧 AP window (at `root@OpenWrt`):
```
cat /proc/mtd
ubinfo -a
```
`/proc/mtd` lists the small **boot flash** partitions (names start with `0:`). `ubinfo` lists the
big NAND volumes, including **part1** and **part2** (the two Cisco firmware slots).

### 4.2 Dump the important bits to files on the AP

The **full boot flash** is the precious one (it needs special hardware to restore). Dump it, and
the **part2** Cisco slot:
```
for d in $(grep '"0:' /proc/mtd | cut -d: -f1); do cat /dev/$d; done > /tmp/spi-backup.bin
```
For part2: run `ubinfo -a`, find the block that says `Name: part2`, note its `Volume ID` number
(say it's `0`), then:
```
cat /dev/ubi0_0 > /tmp/part2-backup.bin
```
(Use *your* number instead of `0` if different.)

### 4.3 Send the backups to your PC

The file server from Part 3 also receives uploads:
```
tftp -p -l /tmp/spi-backup.bin -r spi-backup.bin PC_IP
tftp -p -l /tmp/part2-backup.bin -r part2-backup.bin PC_IP
```
**You should see:** two `PUT ... received N bytes` lines in your PC's tftpd window. The files are
now in your repo folder. **Keep them safe, labelled with this unit.**

### 4.4 This also gave you your signing template

If you didn't have a Cisco image for the template back in Part 2.3, **`part2-backup.bin` is one.**
💻 On your PC, in the repo folder:
```
copy part2-backup.bin cisco-stock-part.bin     ::  Windows
# cp  part2-backup.bin cisco-stock-part.bin     #  Mac/Linux
```
(If you reached Part 3 at all you already had a template — but keep this fresh copy anyway.)

---

## Part 5 — Install to the AP permanently (the first real writes)

> From here, writes are permanent — but still reversible (Part 7). One step at a time; keep your
> backups safe.

### 5.1 Make room for OpenWrt on the AP's storage

In the 🖧 AP window, at the `root@OpenWrt` prompt:
```
sysupgrade -n openwrt-*-cisco_ap1852-squashfs-nand-sysupgrade.bin
```
This copies OpenWrt into the AP's storage **without touching Cisco's two slots**. The AP reboots
itself; the bridge catches it back at `(RNAQ-C7) #`.

### 5.2 Boot back into OpenWrt to run the install from

Repeat Part 3.2 (`setenv ... ; bootipq tftp`) to get back to `root@OpenWrt`. (OpenWrt is on the
AP now, but it still boots only via the signed image — which you install next.)

### 5.3 Start a web server for the AP to fetch the scripts

OpenWrt fetches scripts over normal web. 💻 Open one more PC window in the repo folder:
```
python -m http.server 8080 --bind 10.0.5.50
```
(Use your PC_IP.)

### 5.4 Write the signed boot image into the AP's "part1" slot

💻 First open `scripts/install_to_part1.sh` in a text editor and set the three values at the top
to match **your** build — your image's checksum, your part2's checksum, and your PC_IP in the URL
(the file explains each). Save it. Then in the 🖧 AP window:
```
wget http://PC_IP:8080/scripts/install_to_part1.sh -O /tmp/install.sh
sh /tmp/install.sh
```
This script is careful: it checks it's writing to the right slot and that Cisco's `part2` stays
untouched, and **aborts** if anything is off.

**You should see:** it ends with `INSTALL_RESULT=PASS`. If it prints `FAIL_...`, nothing bad
happened — read which check failed, fix it, run again.

### 5.5 Tell the AP to boot your slot from now on

Reboot to the bootloader (type `reboot` in the AP window and let the bridge catch it at
`(RNAQ-C7) #`), press **Enter** once, then:
```
setshenv BOOT part1
saveshenv
```
(`setshenv`/`saveshenv` = set, and permanently save, the "which slot do I boot" setting.)

### 5.6 (Optional) choose a different network role

**You usually don't need this step.** Out of the box the AP is a normal router: after Part 6 it
comes up at `192.168.1.1` with its own DHCP and the LuCI web page, and — if you filled in
`COUNTRY`/`SSID`/`KEY` in `openwrt/files/etc/uci-defaults/99-ap1852-wifi` before building — the
2.4 GHz Wi-Fi is already on. Just **don't plug its LAN into your existing router** (two DHCP
servers would clash).

Only if you want it to be a **dumb access point** *behind* your existing router instead: boot
back into OpenWrt (Part 3.2), 💻 edit the IP/SSID at the top of `scripts/configure_dumb_ap.sh`,
then in the 🖧 AP window:
```
wget http://PC_IP:8080/scripts/configure_dumb_ap.sh -O /tmp/cfg.sh
sh /tmp/cfg.sh
```

---

## Part 6 — The moment of truth

**Unplug the AP's power, wait five seconds, plug it back in. Don't touch anything.**

**You should see** (in the 🖧 AP window): the bootloader start, `Signature ... returns 0`, then
OpenWrt boot all by itself, ending at a login prompt. **It's now a normal OpenWrt device.** 🎉

You don't need the serial cable anymore — manage it from your web browser (**LuCI**) or over
**SSH** at the IP you set.

**Do this right away:**
- Set a password: in the 🖧 AP window type `passwd` and follow the prompts (or set it in LuCI).

If you baked Wi-Fi in (the `99-ap1852-wifi` values), your AP is already broadcasting on your
chosen country/power. If you left it off, turn the radio on in LuCI — and **set your country
code first**, because the raw default is both illegal in most places and disruptive to nearby
Wi-Fi.

---

## Part 7 — If something goes wrong

- **It booted back into old Cisco software / your slot didn't stick:** redo Part 5.5; and make
  sure in 5.4 you wrote to the volume actually named `part1` (the script checks this).
- **You want to go back to Cisco entirely:** at the bootloader, `setshenv BOOT part2; saveshenv`.
  Cisco was never touched, so it just boots again.
- **Totally dead — no text at all in the AP window, even after a power-cycle, with no Wi-Fi card
  installed:** the one serious case — see **[recovery-unbrick.md](recovery-unbrick.md)**. This is
  exactly what your Part 4 SPI backup is for.
- **It won't power up but there's a Wi-Fi card in the slot:** that card is incompatible — remove
  it, the AP is fine (see the README).
- **Garbled text / dropped characters in the AP window:** type slower, press Enter once before a
  command, and do flash-write steps via the scripts (as above) rather than typing them.
- **Any doubt mid-install:** power-cycle and RAM-boot (Part 3). Nothing on flash changed until
  Part 5, and even that's reversible.

---

## Glossary

- **Serial console / COM port:** an old, simple text connection. The cable lets your PC type
  commands to the AP's bootloader and OS when no network/screen is available.
- **Bootloader (U-Boot):** the tiny program that runs first at power-on and decides what to boot.
  The `(RNAQ-C7) #` prompt is it, waiting for you.
- **OpenWrt:** the open-source router operating system you're installing.
- **Flash / NAND / SPI:** the AP's permanent storage. **NAND** (256 MB) holds the OS; **SPI**
  (4 MB) holds the bootloader and settings. "Writing flash" = permanent change.
- **RAM:** temporary memory. "Booting in RAM" runs something without saving it — a power-cycle
  wipes it. That's why Parts 2–4 are safe.
- **part1 / part2:** the AP's two Cisco firmware "slots". Your boot image goes in **part1**, and
  you keep **part2** as the untouched way back to Cisco.
- **Signing / signed image:** the bootloader only runs an image carrying a valid signature. The
  trick here is it checks the signature against a key *inside the image*, so your own key works.
- **sysupgrade:** OpenWrt's own command to install/update itself into flash.
- **LuCI:** OpenWrt's web interface — the friendly way to configure it afterwards.
- **PC_IP / BOARD_IP:** your computer's network address, and a spare address you pick for the AP.
