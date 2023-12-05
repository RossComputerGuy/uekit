const std = @import("std");
const ptk = @import("parser-toolkit");
const Expression = @import("expr.zig").Expression;

pub const Method = enum {
    section,
    import,
    offset,
    string,
    ip,
    byte,

    pub fn parse(in: []const u8) ?Method {
        inline for (@typeInfo(Method).Enum.fields) |field| {
            const fieldValue: Method = @enumFromInt(field.value);
            if (std.mem.eql(u8, field.name, in)) return fieldValue;
        }
        return null;
    }
};

location: ptk.Location,
method: Method,
params: std.ArrayList(Expression),
