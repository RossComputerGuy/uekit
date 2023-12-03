const std = @import("std");
const builtin = @import("builtin");
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
queue: std.ArrayList(u8),

pub fn create(options: Options) !*Entry {
    const self = try options.allocator.create(Console);
    errdefer options.allocator.destroy(self);

    if (builtin.os.tag == .linux) {
        var t = try std.os.tcgetattr(options.stdin.handle);
        t.lflag &= ~(std.os.linux.ECHO | std.os.linux.ICANON);
        t.cc[std.os.linux.V.MIN] = 0;
        t.cc[std.os.linux.V.TIME] = 0;
        try std.os.tcsetattr(options.stdin.handle, .NOW, t);
    }

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
        .queue = std.ArrayList(u8).init(options.allocator),
    };
    return &self.base;
}

fn read(ctx: *anyopaque, offset: usize, buf: []u8) !usize {
    const self: *Console = @ptrCast(@alignCast(ctx));

    return switch (offset) {
        1 => blk: {
            buf[0] = self.queue.popOrNull() orelse 0;
            break :blk 1;
        },
        2 => blk: {
            var byte: [1]u8 = undefined;
            byte[0] = 0;
            _ = try self.stdin.read(&byte);

            if (byte[0] > 0) {
                try self.queue.append(std.ascii.toUpper(byte[0]));
            }

            buf[0] = if (self.queue.items.len > 0) @as(u8, 1) else @as(u8, 0);
            break :blk 1;
        },
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
    self.queue.deinit();
    self.allocator.destroy(self);
}
