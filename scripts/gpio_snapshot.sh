#!/bin/sh
# Read-only snapshot of all IPQ8064 TLMM GPIO input levels (0..68).
# GPIO_IN_OUT_n = 0x00801004 + 0x10*n, bit 0 = current input level.
# Prints one line "n:level ..." so two snapshots can be diffed.
out=""
n=0
while [ $n -le 68 ]; do
	v=$(devmem $((0x00801004 + 0x10 * n)) 32)
	out="$out $n:$((v & 1))"
	n=$((n + 1))
done
echo "$out"
