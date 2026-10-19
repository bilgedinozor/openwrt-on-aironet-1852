#!/bin/bash
# Add raw UART progress markers to arch/arm/lib/board.c (idempotent).
# They poke the UART DM left configured by the stock bootloader (GSBI4,
# 0x16340000), bypassing the serial driver, to show how far boot gets:
#   A = board_init_f entered, a,b,c... = before each init_sequence step,
#   X = about to relocate, R = board_init_r entered.
set -e
cd ~/ap1852/uboot-ipq806x/uboot
F=arch/arm/lib/board.c
grep -q ap1852_dbg_putc $F && exit 0

perl -0pi -e 's/(init_fnc_t \*init_sequence\[\] = \{)/static void ap1852_dbg_putc(char c)
{
\tvolatile unsigned int *base = (volatile unsigned int *)0x16340000;
\tint t;
\tfor (t = 0; t < 1000000 && !(base[0x08 \/ 4] & (1 << 3)); t++)
\t\t;
\tbase[0x40 \/ 4] = 1;\t\/* NO_CHARS_FOR_TX *\/
\tbase[0x70 \/ 4] = c;\t\/* TF *\/
\tfor (t = 0; t < 1000000 && !(base[0x08 \/ 4] & (1 << 3)); t++)
\t\t;
}

$1/' $F

perl -0pi -e 's/(void board_init_f\(ulong bootflag\)\n\{\n(?:[^\n]*;\n)*?)/$1\tap1852_dbg_putc(\x27A\x27);\n/' $F
perl -0pi -e 's/(\tfor \(init_fnc_ptr = init_sequence; \*init_fnc_ptr; \+\+init_fnc_ptr\) \{\n)/$1\t\tap1852_dbg_putc(\x27a\x27 + (init_fnc_ptr - init_sequence));\n/' $F
perl -0pi -e 's/(\n\trelocate_code\(addr_sp, id, addr\);\n#endif)/\n\tap1852_dbg_putc(\x27X\x27);$1/' $F
perl -0pi -e 's/(void board_init_r\(gd_t \*id, ulong dest_addr\)\n\{\n(?:[^\n]*;\n)*?)/$1\tap1852_dbg_putc(\x27R\x27);\n/' $F

grep -n "ap1852_dbg_putc" $F
