const std = @import("std");
const builtin = @import("builtin");

pub const Register = union {
    rra: u8,
    rrp: u12,
    c: u1,
    z: u1,
};

pub const Opcode = enum(u4) {
    bz,
    bl,
    lda,
    ldl,
    ldp,
    stl,
    stp,
    lrp,
    inp,
    scf,
    adc,
    cmp,
    srl,
    nand,
    ori,
    ore,

    pub fn parse(in: []const u8) ?Opcode {
        inline for (@typeInfo(Opcode).Enum.fields) |field| {
            const fieldValue: Opcode = @enumFromInt(field.value);
            if (std.mem.eql(u8, field.name, in)) return fieldValue;
        }
        return null;
    }

    pub fn operandCount(self: Opcode) usize {
        return switch (self) {
            .scf, .ldp, .stp, .inp, .srl => 0,
            else => 1,
        };
    }
};

pub const Instruction = packed struct {
    opcode: Opcode,
    address: u12,

    pub fn format(self: Instruction, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try writer.writeAll(@tagName(self.opcode));
        try writer.print(" 0x{x}", .{self.address});
    }

    pub inline fn write(self: Instruction, writer: anytype) !void {
        try writer.writeInt(u4, self.opcode, endian);
        try writer.writeInt(u12, self.address, endian);
    }

    pub inline fn readOrNull(reader: anytype) anyerror!?Instruction {
        return read(reader) catch |e| switch (e) {
            error.EndOfStream, error.OutOfBounds => null,
            else => e,
        };
    }

    pub inline fn read(reader: anytype) !Instruction {
        const ir = try reader.readInt(u16, endian);
        const opcode: Opcode = @enumFromInt(@shrExact(ir, 12));
        const address: u12 = @as(u12, @truncate(ir & 0xfff));

        return .{
            .opcode = opcode,
            .address = address,
        };
    }
};

pub const maxAddress = std.math.maxInt(u12);
pub const maxData = std.math.maxInt(u12);
pub const endian = std.builtin.Endian.big;

test "Instruction decoding" {
    const buff = &[_]u8{ 0x70, 0x10 };
    var stream = std.io.fixedBufferStream(buff);

    const instr = try Instruction.read(stream.reader());
    try std.testing.expectEqual(Opcode.lrp, instr.opcode);
    try std.testing.expectEqual(@as(u12, 0x10), instr.address);
}
