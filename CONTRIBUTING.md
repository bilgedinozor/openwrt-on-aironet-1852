# Contributing

Thanks for wanting to help revive these boards instead of binning them.

## Good first contributions

- **5 GHz Wi-Fi.** The second radio enumerates but needs the Cisco 5 GHz board data packaged
  into an ath10k `board-2.bin` keyed by the board id. See [README §7](README.md#7-wi-fi).
- **The recovery/unbrick guide.** `docs/recovery-unbrick.md` is a stub — if you've reflashed
  the 1.8 V SPI on one of these, please fill in the wiring and exact commands.
- **Script cleanups / parameterisation.** The bench values (IPs, serial port, source-tree
  paths under `~/ap1852`) are still hard-coded in a few places; moving them to a config file
  or env vars would help.
- **Testing on other AP1852 variants / U-Boot revisions** and reporting what differs.

## Ground rules

- **This is a right-to-repair / reuse project for hardware you own.** Keep it that way.
- **Never commit secrets or proprietary blobs.** No private signing keys (generate your own),
  no Cisco firmware/board-data binaries, no device backups. `.gitignore` already blocks the
  obvious ones — double-check your diffs.
- **Flash-write code must self-verify.** Anything that writes NAND/UBI should check the target
  volume name and image hash and be safe to re-run. See `scripts/install_to_part1.sh`.
- Include enough detail in issues to reproduce: unit's U-Boot version string, `ubinfo`
  output, serial logs.

## License

By contributing you agree your changes are licensed under this repo's terms: **MIT** for
tooling/docs, **GPL-2.0** for anything under `uboot/patches/` (it patches GPL U-Boot code).
