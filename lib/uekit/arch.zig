const std = @import("std");

pub const versions = struct {
    pub const v2 = @import("arch/v2.zig");
};

pub const Version = enum {
    v2,

    pub fn endian(self: Version) std.builtin.Endian {
        inline for (@typeInfo(Version).Enum.fields) |field| {
            const fieldValue: Version = @enumFromInt(field.value);
            if (self == fieldValue) {
                const archImpl = @field(versions, field.name);
                return archImpl.endian;
            }
        }
        unreachable;
    }

    pub fn instructionSize(self: Version) usize {
        inline for (@typeInfo(Version).Enum.fields) |field| {
            const fieldValue: Version = @enumFromInt(field.value);
            if (self == fieldValue) {
                const archImpl = @field(versions, field.name);
                return @sizeOf(archImpl.Instruction);
            }
        }
        unreachable;
    }
};

pub const Opcode = union(enum) {
    v2: versions.v2.Opcode,

    pub fn parse(version: Version, in: []const u8) ?Opcode {
        inline for (@typeInfo(Version).Enum.fields) |field| {
            const fieldValue: Version = @enumFromInt(field.value);
            if (version == fieldValue) {
                const archImpl = @field(versions, field.name);
                if (archImpl.Opcode.parse(in)) |value| {
                    return @unionInit(Opcode, field.name, value);
                }
                return null;
            }
        }
        unreachable;
    }

    pub fn operandCount(self: Opcode) usize {
        return switch (self) {
            .v2 => |v| v.operandCount(),
        };
    }
};

pub const Instruction = union(enum) {
    v2: versions.v2.Instruction,

    const Formatted = struct {
        instr: Instruction,
        version: Version,

        fn func(self: Formatted, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            inline for (@typeInfo(Version).Enum.fields) |field| {
                const fieldValue: Version = @enumFromInt(field.value);
                if (self.version == fieldValue) {
                    const value = @field(self.instr, field.name);
                    return std.fmt.formatType(value, fmt, options, writer, 3);
                }
            }
        }
    };

    pub fn formatFor(self: Instruction, version: Version) std.fmt.Formatter(Formatted.func) {
        return .{
            .data = .{
                .instr = self,
                .version = version,
            },
        };
    }

    pub fn readOrNull(version: Version, reader: anytype) !?Instruction {
        inline for (@typeInfo(Version).Enum.fields) |field| {
            const fieldValue: Version = @enumFromInt(field.value);
            if (version == fieldValue) {
                const archImpl = @field(versions, field.name);
                if (try archImpl.Instruction.readOrNull(reader)) |instr| {
                    return @unionInit(Instruction, field.name, instr);
                }
                return null;
            }
        }
        unreachable;
    }

    pub fn read(version: Version, reader: anytype) !Instruction {
        inline for (@typeInfo(Version).Enum.fields) |field| {
            const fieldValue: Version = @enumFromInt(field.value);
            if (version == fieldValue) {
                const archImpl = @field(versions, field.name);
                return @unionInit(Instruction, field.name, try archImpl.Instruction.read(reader));
            }
        }
        unreachable;
    }
};

pub const Register = union(enum) {
    v2: versions.v2.Register,
};

test {
    _ = versions.v2;
}
