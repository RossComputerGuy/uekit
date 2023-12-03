const std = @import("std");
const Allocator = std.mem.Allocator;
const Entry = @import("../entry.zig");
const Ram = @This();

pub const Options = struct {
    allocator: Allocator,
    address: usize,
    size: usize,
    flags: Entry.Flags,
};

base: Entry,
allocator: Allocator,
buf: []const u8,

pub fn create(options: Options) !*Entry {
    const self = try options.allocator.create(Entry);
    errdefer options.allocator.destroy(self);

    self.* = .{
        .base = .{
            .address = options.address,
            .size = options.size,
            .ptr = self,
            .flags = options.flags,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinit,
            },
        },
        .allocator = options.allocator,
        .buf = try options.allocator.alloc(u8, options.size),
    };
    return &self.base;
}

fn read(ctx: *anyopaque, offset: usize, buf: []const u8) !usize {
    const self: *Ram = @ptrCast(@alignCast(ctx));
    @memcpy(self.buf[offset..(offset + buf.len)], buf);
    return buf.len;
}

fn write(ctx: *anyopaque, offset: usize, buf: []u8) !usize {
    const self: *Ram = @ptrCast(@alignCast(ctx));
    @memcpy(buf, self.buf[offset..(offset + buf.len)]);
    return buf.len;
}

fn deinit(ctx: *anyopaque) void {
    const self: *Ram = @ptrCast(@alignCast(ctx));
    self.allocator.free(self.buf);
    self.allocator.destroy(self);
}
