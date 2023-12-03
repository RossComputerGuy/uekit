const std = @import("std");
const Allocator = std.mem.Allocator;
const Entry = @import("../entry.zig");
const File = @This();

pub const Options = struct {
    allocator: Allocator,
    address: usize,
    flags: Entry.Flags,
    path: []const u8,
};

base: Entry,
allocator: Allocator,
file: std.fs.File,

pub fn create(options: Options) !*Entry {
    const self = try options.allocator.create(File);
    errdefer options.allocator.destroy(self);

    const file = try std.fs.openFileAbsolute(options.path, .{
        .mode = if (options.flags.readable == 1 and options.flags.writable == 1) .read_write else if (options.flags.readable == 1 and options.flags.writable == 0) .read_only else .write_only,
    });

    self.* = .{
        .base = .{
            .address = options.address,
            .size = (try file.metadata()).size(),
            .ptr = self,
            .flags = options.flags,
            .vtable = &.{
                .read = read,
                .write = write,
                .deinit = deinit,
            },
        },
        .allocator = options.allocator,
        .file = file,
    };
    return &self.base;
}

fn read(ctx: *anyopaque, offset: usize, buf: []u8) !usize {
    const self: *File = @ptrCast(@alignCast(ctx));
    try self.file.seekTo(offset);
    return self.file.read(buf);
}

fn write(ctx: *anyopaque, offset: usize, buf: []const u8) !usize {
    const self: *File = @ptrCast(@alignCast(ctx));
    try self.file.seekTo(offset);
    return self.file.write(buf);
}

fn deinit(ctx: *anyopaque) void {
    const self: *File = @ptrCast(@alignCast(ctx));
    self.file.close();
    self.allocator.destroy(self);
}
