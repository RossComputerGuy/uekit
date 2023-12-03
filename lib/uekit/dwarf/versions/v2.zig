const std = @import("std");
const Emulator = @import("../emu.zig");
const arch = @import("../../arch/v2.zig");

pub fn execute(self: *Emulator, instr: arch.Instruction) !void {
    _ = self;
    std.debug.print("{}\n", .{instr});
}
