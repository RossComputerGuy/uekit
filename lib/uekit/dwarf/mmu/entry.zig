const Entry = @This();

pub const Flags = packed struct {
    readable: u1,
    writable: u1,
};

pub const VTable = struct {
    read: ?*const fn (*anyopaque, usize, []u8) anyerror!usize,
    write: ?*const fn (*anyopaque, usize, []const u8) anyerror!usize,
    deinit: ?*const fn (*anyopaque) void = null,
};

address: usize,
size: usize,
ptr: *anyopaque,
flags: Flags,
vtable: *const VTable,
type: []const u8,

pub inline fn read(self: *const Entry, offset: usize, buf: []u8) !usize {
    if (offset + buf.len > self.size) return error.OutOfBounds;
    if (self.flags.readable == 1) {
        if (self.vtable.read) |f| {
            return f(self.ptr, offset, buf);
        }
        return error.NotImplemented;
    }
    return error.AccessDenied;
}

pub inline fn write(self: *const Entry, offset: usize, buf: []const u8) !usize {
    if (offset + buf.len > self.size) return error.OutOfBounds;
    if (self.flags.writable == 1) {
        if (self.vtable.write) |f| {
            return f(self.ptr, offset, buf);
        }
        return error.NotImplemented;
    }
    return error.AccessDenied;
}

pub inline fn deinit(self: *const Entry) void {
    if (self.vtable.deinit) |f| f(self.ptr);
}

pub inline fn end(self: *const Entry) usize {
    return self.address + self.size;
}

pub const types = struct {
    pub const console = @import("types/console.zig");
    pub const file = @import("types/file.zig");
    pub const ram = @import("types/ram.zig");
};
