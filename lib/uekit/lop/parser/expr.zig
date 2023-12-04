const arch = @import("../../arch.zig");
const Builtin = @import("builtin.zig");
const std = @import("std");

pub const Expression = union(enum) {
    unsignedNumber: usize,
    signedNumber: isize,
    builtin: Builtin,
    string: []const u8,
    literal: []const u8,
    instruction: struct {
        opcode: arch.Opcode,
        operands: ?std.ArrayList(*Expression),
    },

    pub fn deinit(self: Expression) void {
        if (self == .instruction) {
            if (self.instruction.operands) |operands| {
                for (operands.items) |op| {
                    op.deinit();
                    operands.allocator.destroy(op);
                }

                operands.deinit();
            }
        }
    }
};
