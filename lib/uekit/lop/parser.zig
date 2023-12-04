const std = @import("std");
const ptk = @import("parser-toolkit");
const arch = @import("../arch.zig");
const Parser = @This();

pub const Builtin = @import("parser/builtin.zig");
pub const Expression = @import("parser/expr.zig").Expression;
pub const Symbol = @import("parser/symbol.zig");

pub const Message = struct {
    location: ptk.Location,
    err: []const u8,
    msg: []const u8,
};

pub const Options = struct {
    allocator: std.mem.Allocator,
    version: arch.Version,
};

pub const TokenType = enum {
    number,
    identifier,
    whitespace,
    symbol,
    string,
    @"(",
    @")",
    @"=",
    @",",
    @"*",
    @"-",
    @".",
    @"%",
    @":",
};

pub const Pattern = ptk.Pattern(TokenType);

pub const Tokenizer = ptk.Tokenizer(TokenType, &[_]Pattern{
    Pattern.create(.number, ptk.matchers.decimalNumber),
    Pattern.create(.identifier, ptk.matchers.identifier),
    Pattern.create(.whitespace, ptk.matchers.whitespace),
    Pattern.create(.whitespace, ptk.matchers.linefeed),
    Pattern.create(.string, ptk.matchers.sequenceOf(.{
        ptk.matchers.literal("\""),
        ptk.matchers.takeNoneOf("\"\n"),
        ptk.matchers.literal("\""),
    })),
    Pattern.create(.@"(", ptk.matchers.literal("(")),
    Pattern.create(.@")", ptk.matchers.literal(")")),
    Pattern.create(.@"=", ptk.matchers.literal("=")),
    Pattern.create(.@",", ptk.matchers.literal(",")),
    Pattern.create(.@"-", ptk.matchers.literal("-")),
    Pattern.create(.@"*", ptk.matchers.literal("*")),
    Pattern.create(.@".", ptk.matchers.literal(".")),
    Pattern.create(.@"%", ptk.matchers.literal("%")),
    Pattern.create(.@":", ptk.matchers.literal(":")),
});

pub const SymbolStream = struct {
    parser: *Parser,

    pub fn location(self: *SymbolStream) ptk.Location {
        return self.parser.core.tokenizer.current_location;
    }

    pub fn next(self: *SymbolStream) !?Symbol.Union {
        return self.parser.acceptSymbol() catch |err| switch (err) {
            error.EndOfStream => null,
            else => err,
        };
    }

    pub fn deinit(self: *SymbolStream) void {
        self.parser.options.allocator.destroy(self.parser);
    }
};

const ParserCore = ptk.ParserCore(Tokenizer, .{.whitespace});
const ruleset = ptk.RuleSet(TokenType);

const Mode = enum {
    normal,
    symbol,
};

const State = struct {
    mode: Mode = .normal,
    core: ParserCore.State,
};

core: ParserCore,
options: Options,
mode: Mode,

pub fn init(options: Options, expression: []const u8, path: ?[]const u8) Parser {
    var tokenizer = Tokenizer.init(expression, path);

    return .{
        .core = ParserCore.init(&tokenizer),
        .options = options,
        .mode = .normal,
    };
}

pub fn parse(options: Options, messages: *std.ArrayList(Message), expression: []const u8, path: ?[]const u8) !std.ArrayList(Symbol.Union) {
    var parser = init(options, expression, path);
    var syms = std.ArrayList(Symbol.Union).init(options.allocator);
    errdefer syms.deinit();

    while (try parser.accept(messages)) |sym| try syms.append(sym);
    return syms;
}

fn saveState(self: *Parser) State {
    return .{
        .mode = self.mode,
        .core = self.core.saveState(),
    };
}

fn restoreState(self: *Parser, state: State) void {
    self.mode = state.mode;
    self.core.restoreState(state.core);
}

fn accept(self: *Parser, messages: *std.ArrayList(Message)) !?Symbol.Union {
    return self.acceptSymbol() catch |err| switch (err) {
        error.EndOfStream => return null,
        else => {
            try messages.append(.{
                .location = self.core.tokenizer.current_location,
                .err = @errorName(err),
                .msg = "TODO: analyze the error",
            });
            return err;
        },
    };
}

fn acceptSymbolConstant(self: *Parser) !Symbol.Constant {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const variable = try self.core.accept(comptime ruleset.is(.identifier));
    _ = try self.core.accept(comptime ruleset.is(.@"="));

    return .{
        .location = variable.location,
        .name = variable.text,
        .expr = try self.acceptExpression(),
    };
}

fn acceptSymbolData(self: *Parser) !Symbol.Data {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const symbol = try self.core.accept(comptime ruleset.is(.identifier));
    _ = try self.core.accept(comptime ruleset.is(.@":"));

    var exprs = std.ArrayList(Expression).init(self.options.allocator);
    errdefer exprs.deinit();

    const prevMode = self.mode;
    self.mode = .symbol;
    defer self.mode = prevMode;

    while (self.acceptExpression() catch null) |expr| {
        try exprs.append(expr);
    }

    return .{
        .location = symbol.location,
        .name = symbol.text,
        .expressions = exprs,
    };
}

fn acceptSymbol(self: *Parser) !Symbol.Union {
    const constant: ?Symbol.Constant = self.acceptSymbolConstant() catch |err| switch (err) {
        error.EndOfStream => return err,
        else => null,
    };

    const data: ?Symbol.Data = self.acceptSymbolData() catch |err| switch (err) {
        error.EndOfStream => return err,
        else => null,
    };

    if (constant != null) return .{ .constant = constant.? };
    if (data != null) return .{ .data = data.? };
    return error.UnexpectedToken;
}

fn acceptBuiltin(self: *Parser) anyerror!Builtin {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const token = try self.core.accept(comptime ruleset.is(.@"%"));
    const name = try self.core.accept(comptime ruleset.is(.identifier));

    _ = try self.core.accept(comptime ruleset.is(.@"("));

    var params = std.ArrayList(Expression).init(self.options.allocator);
    errdefer params.deinit();

    while (true) {
        try params.append(try self.acceptExpression());

        const t = try self.core.peek() orelse return error.EndOfStream;
        if ((comptime ruleset.is(.@")"))(t.type)) break;
        if ((comptime ruleset.is(.@","))(t.type)) {
            _ = try self.core.nextToken();
        }
        return error.UnexpectedToken;
    }

    return .{
        .location = token.location,
        .method = Builtin.Method.read(name.text) orelse return error.InvalidBuiltin,
        .params = params,
    };
}

fn acceptExpression(self: *Parser) !Expression {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const token = (try self.core.nextToken()) orelse return error.EndOfStream;

    if ((comptime ruleset.is(.number))(token.type)) {
        var text = token.text;
        var base: u8 = 10;
        if (std.mem.eql(u8, token.text, "0")) {
            if (try self.core.nextToken()) |id| {
                if ((comptime ruleset.is(.identifier))(id.type)) {
                    base = switch (id.text[0]) {
                        'x' => 16,
                        'o' => 8,
                        'b' => 2,
                        else => return error.UnexpectedToken,
                    };

                    text = id.text[1..];
                }
            }
        }
        return .{ .unsignedNumber = try std.fmt.parseInt(usize, text, base) };
    }

    if ((comptime ruleset.is(.@"-"))(token.type)) {
        return .{ .signedNumber = @as(isize, @intCast((try self.acceptExpression()).unsignedNumber)) * @as(isize, -1) };
    }

    if ((comptime ruleset.is(.@"%"))(token.type)) {
        self.core.restoreState(state);
        return .{ .builtin = try self.acceptBuiltin() };
    }

    if ((comptime ruleset.is(.string))(token.type)) {
        return .{ .string = token.text[1..(token.text.len - 1)] };
    }

    return switch (self.mode) {
        .normal => {
            if ((comptime ruleset.is(.identifier))(token.type)) {
                return .{ .literal = token.text };
            }
            return error.InvalidExpression;
        },
        .symbol => {
            if ((comptime ruleset.is(.identifier))(token.type)) {
                const opcode = arch.Opcode.parse(self.options.version, token.text) orelse return error.UnexpectedToken;
                return .{
                    .instruction = .{
                        .opcode = opcode,
                        .operands = if (opcode.operandCount() == 0) null else blk: {
                            var operands = try std.ArrayList(*Expression).initCapacity(self.options.allocator, opcode.operandCount());
                            errdefer operands.deinit();

                            const prevMode = self.mode;
                            self.mode = .normal;
                            defer self.mode = prevMode;

                            var i: usize = 0;
                            while (i < opcode.operandCount()) : (i += 1) {
                                const value = try self.options.allocator.create(Expression);
                                errdefer self.options.allocator.destroy(value);
                                value.* = try self.acceptExpression();

                                try operands.append(value);

                                if ((i + 1) == opcode.operandCount()) break;
                                _ = try self.core.accept(comptime ruleset.is(.@","));
                            }
                            break :blk operands;
                        },
                    },
                };
            }
            return error.InvalidExpression;
        },
    };
}

test "Parsing expressions" {
    const options = Options{
        .allocator = std.testing.allocator,
        .version = .v2,
    };

    try std.testing.expectEqual(@as(usize, 0b11), (try @constCast(&init(options, "0b11", null)).acceptExpression()).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 0o11), (try @constCast(&init(options, "0o11", null)).acceptExpression()).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 0x11), (try @constCast(&init(options, "0x11", null)).acceptExpression()).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 11), (try @constCast(&init(options, "11", null)).acceptExpression()).unsignedNumber);

    try std.testing.expectEqualStrings("Hellord", (try @constCast(&init(options, "\"Hellord\"", null)).acceptExpression()).string);
}

test "Parsing builtin" {
    const section = try @constCast(&init(.{
        .allocator = std.testing.allocator,
        .version = .v2,
    }, "%section(\"code\")", null)).acceptBuiltin();
    defer section.params.deinit();

    try std.testing.expectEqual(@as(usize, 1), section.location.line);
    try std.testing.expectEqual(@as(usize, 1), section.location.column);
    try std.testing.expectEqual(@as(?[]const u8, null), section.location.source);
    try std.testing.expectEqual(Builtin.Method.section, section.method);
    try std.testing.expectEqual(@as(usize, 1), section.params.items.len);
    try std.testing.expectEqualStrings("code", section.params.items[0].string);
}

test "Parsing symbol constant" {
    const options = Options{
        .allocator = std.testing.allocator,
        .version = .v2,
    };

    const symbol = try @constCast(&init(options, "std = %import(\"std\")", null)).acceptSymbolConstant();
    defer symbol.expr.builtin.params.deinit();

    try std.testing.expectEqual(@as(usize, 1), symbol.location.line);
    try std.testing.expectEqual(@as(usize, 1), symbol.location.column);
    try std.testing.expectEqual(@as(?[]const u8, null), symbol.location.source);
    try std.testing.expectEqual(Builtin.Method.import, symbol.expr.builtin.method);
    try std.testing.expectEqual(@as(usize, 1), symbol.expr.builtin.location.line);
    try std.testing.expectEqual(@as(usize, 7), symbol.expr.builtin.location.column);
    try std.testing.expectEqual(@as(usize, 1), symbol.expr.builtin.params.items.len);
    try std.testing.expectEqualStrings("std", symbol.expr.builtin.params.items[0].string);
}
