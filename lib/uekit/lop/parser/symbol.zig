const ptk = @import("parser-toolkit");
const std = @import("std");
const arch = @import("../../arch.zig");
const Expression = @import("expr.zig").Expression;

pub const Constant = struct {
    location: ptk.Location,
    name: std.ArrayList(u8),
    expr: Expression,

    pub fn deinit(self: Constant) void {
        self.name.deinit();
        self.expr.deinit();
    }

    pub fn format(self: Constant, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        try writer.writeAll(@typeName(Constant));
        try writer.print("{{ .location = {}, .name = {s}, .expr = {} }}", .{ self.location, self.name.items, self.expr });
    }
};

pub const Data = struct {
    location: ptk.Location,
    name: std.ArrayList(u8),
    expressions: std.ArrayList(Expression),
    next: ?std.ArrayList(u8),
    prev: ?std.ArrayList(u8),

    pub const Kind = enum {
        code,
        value,
        mixed,
    };

    pub fn deinit(self: Data) void {
        self.name.deinit();
        for (self.expressions.items) |expr| expr.deinit();
        self.expressions.deinit();

        if (self.next) |n| n.deinit();
        if (self.prev) |p| p.deinit();
    }

    pub fn format(self: Data, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        try writer.writeAll(@typeName(Data));
        try writer.print("{{ .location = {}, .name = {s}, .expressions = {any}, .kind = {s}, .section = {s}, ", .{
            self.location,
            self.name.items,
            self.expressions.items,
            @tagName(self.kind()),
            self.section(),
        });

        try writer.writeAll(".next = ");
        try writer.writeAll(if (self.next) |n| n.items else "null");

        try writer.writeAll(", .prev = ");
        try writer.writeAll(if (self.prev) |p| p.items else "null");
        try writer.writeAll(" }");
    }

    pub fn size(self: Data, version: arch.Version) usize {
        var value: usize = 0;
        for (self.expressions.items) |expr| {
            value += switch (expr) {
                .instruction => |instr| @as(usize, switch (instr.opcode) {
                    .real => 1,
                    .pseudo => |pseudo| pseudo.appendInstructions(version, null, &.{}) catch @panic("Expected no errors"),
                }) * version.instructionSize(),
                .literal => 0,
                .builtin => 0,
                .unsignedNumber, .signedNumber => 1,
                .string => |str| str.items.len,
            };
        }
        return value;
    }

    pub fn kind(self: Data) Kind {
        var icount: usize = 0;
        var count: usize = 0;
        for (self.expressions.items) |expr| {
            if (expr == .instruction) {
                icount += 1;
                count += 1;
            } else if (expr != .builtin) count += 1;
        }

        return if (icount == count) .code else if (icount == 0 and count > 0) .value else .mixed;
    }

    pub fn section(self: Data) []const u8 {
        if (self.expressions.items.len >= 1) {
            if (self.expressions.items[0] == .builtin) {
                if (self.expressions.items[0].builtin.method == .section) return self.expressions.items[0].builtin.params.items[0].string.items;
            }
        }

        return switch (self.kind()) {
            .code => "code",
            .value => "data",
            .mixed => "rodata",
        };
    }
};

pub const Union = union(enum) {
    constant: Constant,
    data: Data,

    pub inline fn location(self: Union) ptk.Location {
        return switch (self) {
            .constant => |c| c.location,
            .data => |d| d.location,
        };
    }

    pub inline fn name(self: Union) std.ArrayList(u8) {
        return switch (self) {
            .constant => |c| c.name,
            .data => |d| d.name,
        };
    }

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
