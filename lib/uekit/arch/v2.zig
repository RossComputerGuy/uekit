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
};

pub const Instruction = packed struct {
    opcode: Opcode,
    address: u12,
    data: u8,

    pub inline fn write(self: Instruction, writer: anytype) !void {
        try writer.writeInt(u4, self.opcode, endian);
        try writer.writeInt(u12, self.address, endian);

        switch (self.opcode) {
            .ldl, .ldp, .adc, .cmp, .nand, .ori, .ore => try writer.writeInt(u8, self.data, endian),
        }
    }

    pub inline fn readOrNull(reader: anytype) !?Instruction {
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
            .data = switch (opcode) {
                .ldl, .ldp, .adc, .cmp, .nand, .ori, .ore => try reader.readInt(u8, endian),
                else => 0,
            },
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
    try std.testing.expectEqual(@as(u8, 0), instr.data);
}
