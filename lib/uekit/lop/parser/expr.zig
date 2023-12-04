const Builtin = @import("builtin.zig");

pub const Expression = union(enum) {
    number: usize,
    builtin: Builtin,
    string: []const u8,
    literal: []const u8,
};
