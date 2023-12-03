const std = @import("std");
const Allocator = std.mem.Allocator;
const arch = @import("../arch.zig");
const Register = @import("reg.zig");
const Mmu = @import("mmu.zig");
const Emulator = @This();

pub const versions = struct {
    pub const v2 = @import("versions/v2.zig");
};

pub const MemoryReader = std.io.Reader(*Emulator, anyerror, read);

pub const Options = struct {
    allocator: Allocator,
    version: arch.Version,
};

allocator: Allocator,
version: arch.Version,
registers: []Register,
mmu: *Mmu,
instr: ?arch.Instruction,
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
        .instr = null,
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
    return error.InvalidVersion;
}

pub fn deinit(self: *const Emulator) void {
    self.mmu.deinit();
    self.allocator.free(self.registers);
    self.allocator.destroy(self);
}

pub fn register(self: *Emulator, name: []const u8) !*Register {
    for (self.registers) |*reg| {
        if (std.mem.eql(u8, reg.name, name)) return reg;
    }
    return error.InvalidRegister;
}

pub fn read(self: *Emulator, buf: []u8) anyerror!usize {
    const s = try self.mmu.read(self.pc, buf);
    self.pc += s;
    return s;
}

pub fn reader(self: *Emulator) MemoryReader {
    return .{ .context = self };
}

pub fn fetch(self: *Emulator) !?arch.Instruction {
    inline for (@typeInfo(arch.Version).Enum.fields) |field| {
        const fieldValue: arch.Version = @enumFromInt(field.value);
        if (self.version == fieldValue) {
            const archImpl = @field(arch.versions, field.name);
            if (try archImpl.Instruction.readOrNull(self.reader())) |instr| {
                return @unionInit(arch.Instruction, field.name, instr);
            }
            return null;
        }
    }
    return error.InvalidVersion;
}

pub fn exec(self: *Emulator, instr: arch.Instruction) !void {
    if (@intFromEnum(std.meta.activeTag(instr)) != @intFromEnum(self.version)) return error.IncompatibleInstruction;

    inline for (@typeInfo(arch.Version).Enum.fields) |field| {
        const fieldValue: arch.Version = @enumFromInt(field.value);
        if (self.version == fieldValue) {
            return @field(versions, field.name).execute(self, @field(instr, field.name));
        }
    }
    return error.InvalidVersion;
}

pub fn run(self: *Emulator) !void {
    while (try self.fetch()) |instr| {
        self.instr = instr;
        try self.exec(instr);
    }

    self.instr = null;
}

pub fn format(self: *const Emulator, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    try writer.writeAll(@typeName(Emulator));

    try writer.writeAll("{ .registers = .{");
    for (self.registers, 0..) |reg, i| {
        try writer.print(" .{s} = {}", .{ reg.name, reg.value });
        if (i + 1 != self.registers.len) try writer.writeAll(",");
    }
    try writer.writeAll("}, .pc = ");

    try writer.print("0x{x} }}", .{self.pc});
}
