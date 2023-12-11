const std = @import("std");
const ptk = @import("parser-toolkit");
const Self = @This();

pub const Entry = struct {
    address: usize,
    name: []const u8,
    section: []const u8,
    location: ptk.Location,

    pub fn format(self: Entry, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try writer.writeAll(@typeName(Entry));
        try writer.print("{{ .address = 0x{x}, .name = {s}, .section = {s}, .location = {s} }}", .{ self.address, self.name, self.section, self.location });
    }
};

list: std.ArrayList(Entry),

pub inline fn init(alloc: std.mem.Allocator) !Self {
    return .{ .list = std.ArrayList(Entry).init(alloc) };
}

pub inline fn deinit(self: Self) void {
    return self.list.deinit();
}

pub fn at(self: Self, addr: usize) ?*Entry {
    for (self.list.items) |*entry| {
        if (entry.address == addr) return entry;
    }
    return null;
}

pub fn of(self: Self, name: []const u8) ?*Entry {
    for (self.list.items) |*entry| {
        if (std.mem.eql(u8, name, entry.name)) return entry;
    }
    return null;
}
