const clap = @import("clap");
const uekit = @import("uekit");
const std = @import("std");

pub const allocator = std.heap.page_allocator;

pub const ver = clap.parsers.enumeration(uekit.arch.Version);

pub fn path(in: []const u8) error{ Unexpected, OutOfMemory, CurrentWorkingDirectoryUnlinked }![]const u8 {
    return if (std.fs.path.isAbsolute(in)) try allocator.dupe(u8, in) else blk: {
        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);
        break :blk try std.fs.path.join(allocator, &.{ cwd, in });
    };
}

pub fn mod(in: []const u8) error{ Unexpected, OutOfMemory, CurrentWorkingDirectoryUnlinked, NoSeparator }!struct { []const u8, []const u8 } {
    const s = std.mem.indexOf(u8, in, "=") orelse return error.NoSeparator;
    return .{
        in[0..s],
        try path(in[(s + 1)..]),
    };
}

pub inline fn getStdErr() std.fs.File.Writer {
    return std.io.getStdErr().writer();
}

pub inline fn getStdOut() std.fs.File.Writer {
    return std.io.getStdOut().writer();
}

pub const parsers = .{
    .string = clap.parsers.string,
    .str = clap.parsers.string,
    .u8 = clap.parsers.int(u8, 0),
    .u16 = clap.parsers.int(u16, 0),
    .u32 = clap.parsers.int(u32, 0),
    .u64 = clap.parsers.int(u64, 0),
    .usize = clap.parsers.int(usize, 0),
    .i8 = clap.parsers.int(i8, 0),
    .i16 = clap.parsers.int(i16, 0),
    .i32 = clap.parsers.int(i32, 0),
    .i64 = clap.parsers.int(i64, 0),
    .isize = clap.parsers.int(isize, 0),
    .f32 = clap.parsers.float(f32),
    .f64 = clap.parsers.float(f64),
    .version = ver,
    .ver = ver,
    .path = path,
    .module = mod,
    .mod = mod,
};
