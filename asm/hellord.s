consts = %import("consts.s")

_start = %section("code")
_start:
  lrp hellord
.loop:
  ldp
  cmp
  bz -1
  stl consts.TX
  inp
  scf consts.Z
  bz .loop

hellord = %section("rodata")
hellord = %string("Hellord\n")
