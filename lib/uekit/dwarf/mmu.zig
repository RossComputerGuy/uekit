const std = @import("std");
const Allocator = std.mem.Allocator;
const Mmu = @This();

pub const Options = struct {
    allocator: Allocator,
    maxAddress: usize,
};

pub const Entry = @import("mmu/entry.zig");

allocator: Allocator,
maxAddress: usize,
entries: std.ArrayList(*Entry),

pub fn create(options: Options) !*Mmu {
    const self = try options.allocator.create(Mmu);
    errdefer options.allocator.destroy(self);

    self.* = .{
        .allocator = options.allocator,
        .maxAddress = options.maxAddress,
        .entries = std.ArrayList(*Entry).init(options.allocator),
    };
    return self;
}

pub fn deinit(self: *const Mmu) void {
    for (self.entries.items) |e| e.deinit();
    self.entries.deinit();
    self.allocator.destroy(self);
}

pub fn entry(self: *const Mmu, addr: usize) !?*Entry {
    if (addr > self.maxAddress) return error.OutOfBounds;

    for (self.entries.items) |e| {
        if (addr >= e.address and addr - e.address < e.size) return e;
    }
    return null;
}

pub fn read(self: *const Mmu, offset: usize, buf: []u8) anyerror!usize {
    if (offset + buf.len >= self.maxAddress) return error.OutOfBounds;

    if (self.entry(offset) catch null) |e| {
        return e.read(offset, buf);
    } else {
        @memset(buf, 0);
    }
    return buf.len;
}

pub fn write(self: *const Mmu, offset: usize, buf: []const u8) anyerror!usize {
    if (offset + buf.len >= self.maxAddress) return error.OutOfBounds;

    if (self.entry(offset) catch null) |e| {
        return e.write(offset, buf);
    }

    // TODO: find the last "ram" type memory entry and expand it.
    return error.NotMapped;
}
