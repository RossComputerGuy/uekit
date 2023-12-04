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

    pub fn format(self: Constant, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        try writer.writeAll(@typeName(Constant));
        try writer.print("{{ .location = {}, .name = {s}, .expr = {} }}", .{ self.location, self.name, self.expr });
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

    pub fn format(self: Data, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        try writer.writeAll(@typeName(Data));
        try writer.print("{{ .location = {}, .name = {s}, .expressions = {any} }}", .{ self.location, self.name, self.expressions.items });
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

    pub fn format(self: Union, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        try writer.writeAll(@typeName(Union));
        try writer.print("{{ .{s} = ", .{@tagName(std.meta.activeTag(self))});

        switch (self) {
            .constant => |c| try writer.print("{}", .{c}),
            .data => |d| try writer.print("{}", .{d}),
        }

        try writer.writeAll(" }");
    }
};