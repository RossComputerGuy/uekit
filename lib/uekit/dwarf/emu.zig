const std = @import("std");
const Allocator = std.mem.Allocator;
const arch = @import("../arch.zig");
const Register = @import("reg.zig");
const Mmu = @import("mmu.zig");
const Emulator = @This();

pub const versions = struct {
    pub const v2 = @import("versions/v2.zig");
};

pub const MemoryReader = std.io.Reader(Emulator, anyerror, read);

pub const Options = struct {
    allocator: Allocator,
    version: arch.Version,
};

allocator: Allocator,
version: arch.Version,
registers: []Register,
mmu: *Mmu,
pc: usize,

pub fn create(options: Options) !*Emulator {
    const self = try options.allocator.create(Emulator);
    errdefer options.allocator.destroy(self);

    self.* = .{
        .allocator = options.allocator,
        .version = options.version,
        .registers = undefined,
        .pc = 0,
        .mmu = undefined,
    };

    inline for (@typeInfo(arch.Version).Enum.fields) |field| {
        const fieldValue: arch.Version = @enumFromInt(field.value);
        if (self.version == fieldValue) {
            const archImpl = @field(arch.versions, field.name);

            self.mmu = try Mmu.create(.{
                .allocator = options.allocator,
                .maxAddress = archImpl.maxAddress,
            });

            self.registers = try options.allocator.alloc(Register, @typeInfo(archImpl.Register).Union.fields.len);
            errdefer options.allocator.free(self.registers);

            inline for (@typeInfo(archImpl.Register).Union.fields, 0..) |unionField, i| {
                self.registers[i] = .{
                    .name = unionField.name,
                    .version = self.version,
                    .value = 0,
                };
            }
            return self;
        }
    }
    unreachable;
}

pub fn deinit(self: *const Emulator) void {
    self.mmu.deinit();
    self.allocator.free(self.registers);
    self.allocator.destroy(self);
}

pub fn register(self: *Emulator, name: []const u8) !*Register {
    for (&self.registers) |*reg| {
        if (std.mem.eql(u8, reg.name, name)) return reg;
    }
    return error.InvalidRegister;
}

pub fn read(self: *Emulator, buf: []u8) !usize {
    if (self.pc + buf.len >= self.maxAddress) return error.OutOfBounds;

    if (self.mmu.entry(self.pc)) |entry| {
        if (entry.read(self.pc, buf)) |size| {
            self.pc += size;
            return size;
        } else |err| {
            return err;
        }
    } else {
        @memcpy(buf, 0);
    }

    self.pc += buf.len;
    return buf.len;
}

pub fn reader(self: *Emulator) MemoryReader {
    return .{ .context = self };
}

pub fn fetch(self: *Emulator) !?arch.Instruction {
    inline for (@typeInfo(arch.Version).Enum.fields) |field| {
        const fieldValue: arch.Version = @enumFromInt(field.value);
        if (self.version == fieldValue) {
            const archImpl = @field(arch.versions, field.name);
            return archImpl.Instruction.readOrNull(self.reader());
        }
    }
    unreachable;
}

pub fn exec(self: *Emulator, instr: arch.Instruction) !void {
    if (@intFromEnum(std.meta.activeTag(instr)) != @intFromEnum(self.version)) return error.IncompatibleInstruction;

    inline for (@typeInfo(arch.Version).Enum.fields) |field| {
        const fieldValue: arch.Version = @enumFromInt(field.value);
        if (self.version == fieldValue) {
            return @field(versions, field.name).execute(self, @field(instr, field.name));
        }
    }
}

pub fn run(self: *Emulator) !void {
    while (try self.fetch()) |instr| {
        try self.exec(instr);
    }
}
