const std = @import("std");
const Allocator = std.mem.Allocator;
const Entry = @import("../entry.zig");
const Console = @This();

pub const Options = struct {
    allocator: Allocator,
    stdout: std.fs.File,
    stdin: std.fs.File,
};

base: Entry,
allocator: Allocator,
stdout: std.fs.File,
stdin: std.fs.File,

pub fn create(options: Options) !*Entry {
    const self = try options.allocator.create(Console);
    errdefer options.allocator.destroy(self);

    self.* = .{
        .base = .{
            .address = 0xffc,
            .size = 4,
            .ptr = self,
            .flags = .{
                .readable = 1,
                .writable = 1,
            },
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinit,
            },
            .type = @typeName(Console),
        },
        .allocator = options.allocator,
        .stdout = options.stdout,
        .stdin = options.stdin,
    };
    return &self.base;
}

fn read(ctx: *anyopaque, offset: usize, buf: []u8) !usize {
    const self: *Console = @ptrCast(@alignCast(ctx));

    return switch (offset) {
        1 => self.stdin.read(buf),
        2 => 1,
        else => error.AccessDenied,
    };
}

fn write(ctx: *anyopaque, offset: usize, buf: []const u8) !usize {
    const self: *Console = @ptrCast(@alignCast(ctx));

    return switch (offset) {
        0 => self.stdout.write(&[_]u8{buf[0]}),
        3 => error.Halt,
        else => error.AccessDenied,
    };
}

fn deinit(ctx: *anyopaque) void {
    const self: *Console = @ptrCast(@alignCast(ctx));
    self.allocator.destroy(self);
}