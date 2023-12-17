const std = @import("std");
const ptk = @import("parser-toolkit");
const Parser = @import("parser.zig");
const Self = @This();

pub const Entry = struct {
    address: usize,
    size: usize,
    kind: Parser.Symbol.Data.Kind,
    name: []const u8,
    section: []const u8,
    location: ptk.Location,

    pub fn format(self: Entry, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try writer.writeAll(@typeName(Entry));
        try writer.print("{{ .address = 0x{x}, .size = {}, .kind = {s}, .name = {s}, .section = {s}, .location = {s} }}", .{
            self.address,
            std.fmt.fmtIntSizeBin(self.size),
            @tagName(self.kind),
            self.name,
            self.section,
            self.location,
        });
    }
};

list: std.ArrayList(Entry),

pub inline fn init(alloc: std.mem.Allocator) !Self {
    return .{ .list = std.ArrayList(Entry).init(alloc) };
}

pub inline fn deinit(self: Self) void {
    return self.list.deinit();
}

pub fn append(self: *Self, entry: Entry) !void {
    for (self.list.items) |e| {
        if (std.mem.eql(u8, e.name, entry.name)) return;
    }

    try self.list.append(entry);
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
