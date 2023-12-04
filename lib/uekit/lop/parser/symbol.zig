const ptk = @import("parser-toolkit");
const std = @import("std");
const Expression = @import("expr.zig").Expression;

pub const Constant = struct {
    location: ptk.Location,
    name: []const u8,
    expr: Expression,

    pub fn deinit(self: Constant) void {
        return self.expr.deinit();
    }
};

pub const Data = struct {
    location: ptk.Location,
    name: []const u8,
    expressions: std.ArrayList(Expression),

    pub fn deinit(self: Data) void {
        for (self.expressions.items) |expr| expr.deinit();
        self.expressions.deinit();
    }
};

pub const Union = union(enum) {
    constant: Constant,
    data: Data,

    pub fn deinit(self: Union) void {
        return switch (self) {
            .constant => |c| c.deinit(),
            .data => |d| d.deinit(),
        };
    }
};
