GLOBAL syn_ramstyle=registers;

// Przywróć BSRAM dla całych modułów-wrapperów
// INS "zxnext_top/zxnext" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/bootrom_mod" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/copper_inst_msb_ram/ram_inst" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/copper_inst_lsb_ram/ram_inst" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/sprite_mod/attr0" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/sprite_mod/attr1" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/sprite_mod/attr2" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/sprite_mod/attr3" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/sprite_mod/attr4" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/sprite_mod/pattern" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/bank5_ram/ram_inst" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/bank7_ram/ram_inst" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/palette_utm/ram_inst" syn_ramstyle=block_ram;
INS "zxnext_top/zxnext/palette_l2s/ram_inst" syn_ramstyle=block_ram;
// INS "scandoubler" syn_ramstyle=block_ram;

INS "zxnext_top/zxnext/sprite_mod/linebuf0" syn_ramstyle=distributed_ram;
INS "zxnext_top/zxnext/sprite_mod/linebuf1" syn_ramstyle=distributed_ram;
INS "zxnext_top/zxnext/tilemap_mod/tilemem" syn_ramstyle=distributed_ram;

INS "zxnext_top/zxnext/cpu_mod/z80n" syn_ramstyle=registers;
INS "zxnext_top/zxnext/cpu_mod/z80n" syn_preserve=1;

// INS "zxnext_top/zxnext/cpu_mod" syn_preserve=1;
// INS "zxnext_top/zxnext/cpu_mod" syn_dont_touch=1;