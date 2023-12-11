const std = @import("std");
const ptk = @import("parser-toolkit");
const Expression = @import("expr.zig").Expression;
const Builtin = @This();

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
