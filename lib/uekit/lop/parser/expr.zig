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

    pub fn format(self: Expression, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        try writer.writeAll(@typeName(Expression));
        try writer.print("{{ .{s} = ", .{ @tagName(std.meta.activeTag(self)) });

        switch (self) {
            .unsignedNumber => |un| try writer.print("{} ", .{ un }),
            .signedNumber => |sn| try writer.print("{} ", .{ sn }),
            .builtin => |bt| try writer.print("{} ", .{ bt }),
            .string, .literal => |sl| try writer.print("{s} ", .{ sl }),
            .instruction => |inst| {
                try writer.print("{{ .opcode = {} ", .{ inst.opcode });

                if (inst.operands) |operands| {
                    try writer.print(", .operands = {any} ", .{ operands.items });
                }

                try writer.writeAll("}");
            },
        }

        try writer.writeAll("}");
    }
};
