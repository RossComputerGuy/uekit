consts = %import("consts.s")

_start:
  %section("code")
  lrp hellord
.loop:
  ldp
  cmp zero
  bz %offset(%ip(), -1)
  stl consts.TX
  inp
  scf consts.Z
  bz .loop

hellord:
  %section("rodata")
  %string("Hellord\n")
zero:
  %byte(0)
