const std = @import("std");
const ptk = @import("parser-toolkit");
const Expression = @import("expr.zig").Expression;
const Builtin = @This();

const BasicExpr = union(enum) {
    unsigned: usize,
    signed: isize,

    pub fn offset(a: BasicExpr, b: BasicExpr) !usize {
        if (a == .unsigned and b == .signed) return @intCast(@as(isize, @intCast(a.unsigned)) + b.signed);
        if (a == .unsigned and b == .unsigned) return a.unsigned + b.unsigned;
        return error.Unrecognied;
    }
};

pub const Method = enum {
    section,
    import,
    offset,
    ip,

    pub fn parse(in: []const u8) ?Method {
        inline for (@typeInfo(Method).Enum.fields) |field| {
            const fieldValue: Method = @enumFromInt(field.value);
            if (std.mem.eql(u8, field.name, in)) return fieldValue;
        }
        return null;
    }

    pub fn parameterCount(self: Method) usize {
        return switch (self) {
            .ip => 0,
            .section, .import => 1,
            .offset => 2,
        };
    }
};

location: ptk.Location,
method: Method,
params: std.ArrayList(Expression),

pub fn deinit(self: Builtin) void {
    for (self.params.items) |param| param.deinit();
    self.params.deinit();
}

pub fn eval(self: Builtin, addr: usize) !usize {
    if (self.method == .ip) return addr;
    if (self.method != .offset) return error.InvalidBuiltin;

    const base: BasicExpr = switch (self.params.items[0]) {
        .unsignedNumber => |un| .{ .unsigned = un },
        .signedNumber => |sn| .{ .signed = sn },
        .builtin => |bt| .{ .unsigned = try bt.eval(addr) },
        else => return error.InvalidBase,
    };

    const other: BasicExpr = switch (self.params.items[1]) {
        .unsignedNumber => |un| .{ .unsigned = un },
        .signedNumber => |sn| .{ .signed = sn },
        .builtin => |bt| .{ .unsigned = try bt.eval(addr) },
        else => return error.InvalidBase,
    };

    return try base.offset(other);
}
