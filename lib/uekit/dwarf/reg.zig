const arch = @import("../arch.zig");
const std = @import("std");
const Register = @This();

name: []const u8,
version: arch.Version,
value: usize,

pub fn size(self: *const Register) !usize {
    inline for (@typeInfo(arch.Version).Enum.fields) |field| {
        const fieldValue: arch.Version = @enumFromInt(field.value);
        if (self.version == fieldValue) {
            const archImpl = @field(arch.versions, field.name);
            inline for (@typeInfo(archImpl.Register).Union.fields) |unionField| {
                if (std.mem.eql(u8, unionField.name, self.name)) {
                    return std.math.maxInt(unionField.type);
                }
            }
            return error.InvalidRegister;
        }
    }
    unreachable;
}

pub fn set(self: *Register, value: usize) !void {
    if (value >= try self.size()) return error.RegisterOverflow;
    self.value = value;
}
