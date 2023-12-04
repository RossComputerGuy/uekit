const ptk = @import("parser-toolkit");
const Expression = @import("expr.zig").Expression;

pub const Constant = struct {
    location: ptk.Location,
    name: []const u8,
    expr: Expression,
};
