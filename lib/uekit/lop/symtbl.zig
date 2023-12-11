const std = @import("std");
const Self = @This();

pub const Entry = struct {
    address: usize,
    name: std.ArrayList(u8),
    section: std.ArrayList(u8),
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
        if (std.mem.eql(u8, name, entry.name.items)) return entry;
    }
    return null;
}
