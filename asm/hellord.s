consts = %import("consts.s")

_start:
  %section("code")
  lrp hellord
.loop:
  ldp
  cmp zero
  bz %ip()
  stl consts.TX
  inp
  jmp _start.loop

hellord:
  %section("rodata")
  "Hellord\n"
zero: 0
