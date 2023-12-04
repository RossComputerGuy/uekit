consts = %import("consts.s")

%section("code")
_start:
  lrp hellord
.loop:
  ldp
  cmp
  bz *-1
  stl consts.TX
  inp
  scf consts.Z
  bz .loop

%section("rodata")
hellord:
  %string("Hellord\n")
