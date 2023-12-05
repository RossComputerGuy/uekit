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

    pub fn format(self: Message, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try writer.print("{} ({s}): {s}", .{ self.location, self.err, self.msg });
    }
};

pub const Options = struct {
    allocator: std.mem.Allocator,
    version: arch.Version,
};

pub const TokenType = enum {
    number,
    identifier,
    whitespace,
    linefeed,
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
    Pattern.create(.linefeed, ptk.matchers.linefeed),
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

const ParserCore = ptk.ParserCore(Tokenizer, .{ .whitespace, .linefeed });
const ruleset = ptk.RuleSet(TokenType);

const Mode = enum {
    normal,
    symbol,
};

const State = struct {
    mode: Mode = .normal,
    core: ParserCore.State,
};

tokenizer: Tokenizer,
core: ParserCore,
options: Options,
mode: Mode,

pub fn init(options: Options, expression: []const u8, path: ?[]const u8) Parser {
    var self = Parser{
        .tokenizer = Tokenizer.init(expression, path),
        .core = undefined,
        .options = options,
        .mode = .normal,
    };

    self.core = ParserCore.init(&self.tokenizer);
    return self;
}

pub fn create(options: Options, expression: []const u8, path: ?[]const u8) !*Parser {
    const self = try options.allocator.create(Parser);
    errdefer options.allocator.destroy(self);

    self.* = .{
        .tokenizer = Tokenizer.init(expression, path),
        .core = undefined,
        .options = options,
        .mode = .normal,
    };

    self.core = ParserCore.init(&self.tokenizer);
    return self;
}

pub fn parse(options: Options, messages: *std.ArrayList(Message), expression: []const u8, path: ?[]const u8) !std.ArrayList(Symbol.Union) {
    var parser = try create(options, expression, path);
    defer options.allocator.destroy(parser);

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

fn peekDepth(self: *Parser, n: usize) !?Tokenizer.Token {
    const state = self.saveState();
    defer self.restoreState(state);

    var token: ?Tokenizer.Token = null;
    var i: usize = 0;
    while (i < n) : (i += 1) token = try self.core.nextToken();
    return token;
}

fn accept(self: *Parser, messages: *std.ArrayList(Message)) !?Symbol.Union {
    var msg: ?Message = null;
    return self.acceptSymbol(&msg) catch |err| switch (err) {
        error.EndOfStream => return null,
        else => {
            try messages.append(msg orelse .{
                .location = self.core.tokenizer.current_location,
                .err = @errorName(err),
                .msg = "TODO: analyze the error",
            });
            return err;
        },
    };
}

fn acceptSymbolName(self: *Parser, msg: *?Message) ![]const u8 {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    var list = std.ArrayList(u8).init(self.options.allocator);
    errdefer list.deinit();

    const begin = (try self.core.peek()) orelse return error.EndOfStream;

    while (try self.tokenizer.next()) |token| {
        if (token.type == .@"." or token.type == .identifier) {
            try list.writer().writeAll(token.text);
        } else if (token.type == .whitespace) {
            if (list.items.len > 0) break;
        } else {
            self.tokenizer.offset -= token.text.len;
            break;
        }
    }

    if (list.items.len < 1) {
        msg.* = .{
            .location = begin.location,
            .err = "UnexpectedToken",
            .msg = try std.fmt.allocPrint(self.options.allocator, "Expected identifier or separator token, got {s} as {s}", .{ begin.text, @tagName(begin.type) }),
        };
        return error.UnexpectedToken;
    }
    return list.items;
}

fn acceptSymbolConstant(self: *Parser, msg: *?Message) !Symbol.Constant {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const location = self.core.tokenizer.current_location;
    const variable = try self.acceptSymbolName(msg);
    _ = try self.core.accept(comptime ruleset.is(.@"="));

    const prevMode = self.mode;
    self.mode = .symbol;
    defer self.mode = prevMode;

    return .{
        .location = location,
        .name = variable,
        .expr = try self.acceptExpression(msg),
    };
}

fn acceptSymbolData(self: *Parser, msg: *?Message) !Symbol.Data {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const location = self.core.tokenizer.current_location;
    const symbol = try self.acceptSymbolName(msg);
    _ = try self.core.accept(comptime ruleset.is(.@":"));

    var exprs = std.ArrayList(Expression).init(self.options.allocator);
    errdefer exprs.deinit();

    const prevMode = self.mode;
    self.mode = .symbol;
    defer self.mode = prevMode;

    while (try self.core.peek()) |token| {
        if (token.type == .@":" or token.type == .@".") break;
        if (try self.peekDepth(2)) |tokenSplit| {
            if (tokenSplit.type == .@"=") break;
        }

        try exprs.append(try self.acceptExpression(msg));
    }

    return .{
        .location = location,
        .name = symbol,
        .expressions = exprs,
    };
}

fn acceptSymbol(self: *Parser, msg: *?Message) !Symbol.Union {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const beginToken = (try self.core.peek()) orelse return error.EndOfStream;
    self.options.allocator.free(self.acceptSymbolName(msg) catch |err| {
        msg.* = .{
            .location = beginToken.location,
            .err = "UnexpectedToken",
            .msg = try std.fmt.allocPrint(self.options.allocator, "Expected identifier, got {s} as {s}", .{ beginToken.text, @tagName(beginToken.type) }),
        };
        return err;
    });

    const token = (try self.core.nextToken()) orelse return error.EndOfStream;
    self.core.restoreState(state);

    if ((comptime ruleset.is(.@"="))(token.type)) {
        return .{ .constant = try self.acceptSymbolConstant(msg) };
    }

    if ((comptime ruleset.is(.@":"))(token.type)) {
        return .{ .data = try self.acceptSymbolData(msg) };
    }

    msg.* = .{
        .location = token.location,
        .err = "UnexpectedToken",
        .msg = try std.fmt.allocPrint(self.options.allocator, "Expected constant assignment or data declaration token, got {s} as {s}", .{ token.text, @tagName(token.type) }),
    };
    return error.UnexpectedToken;
}

fn acceptBuiltin(self: *Parser, msg: *?Message) anyerror!Builtin {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const token = try self.core.accept(comptime ruleset.is(.@"%"));
    const name = try self.core.accept(comptime ruleset.is(.identifier));

    _ = try self.core.accept(comptime ruleset.is(.@"("));

    var params = std.ArrayList(Expression).init(self.options.allocator);
    errdefer params.deinit();

    while (true) {
        const before = try self.core.peek() orelse return error.EndOfStream;
        if ((comptime ruleset.is(.@")"))(before.type)) {
            _ = try self.core.nextToken();
            break;
        }

        try params.append(try self.acceptExpression(msg));

        const after = try self.core.peek() orelse return error.EndOfStream;
        if ((comptime ruleset.is(.@")"))(after.type)) {
            _ = try self.core.nextToken();
            break;
        }
        if ((comptime ruleset.is(.@","))(after.type)) {
            _ = try self.core.nextToken();
            continue;
        }
        return error.UnexpectedToken;
    }

    return .{
        .location = token.location,
        .method = Builtin.Method.parse(name.text) orelse return error.InvalidBuiltin,
        .params = params,
    };
}

fn acceptExpression(self: *Parser, msg: *?Message) !Expression {
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
        return .{ .signedNumber = @as(isize, @intCast((try self.acceptExpression(msg)).unsignedNumber)) * @as(isize, -1) };
    }

    if ((comptime ruleset.is(.@"%"))(token.type)) {
        self.core.restoreState(state);
        return .{ .builtin = try self.acceptBuiltin(msg) };
    }

    if ((comptime ruleset.is(.string))(token.type)) {
        return .{ .string = token.text[1..(token.text.len - 1)] };
    }

    return switch (self.mode) {
        .normal => {
            self.core.restoreState(state);
            return .{ .literal = try self.acceptSymbolName(msg) };
        },
        .symbol => {
            if ((comptime ruleset.is(.identifier))(token.type)) {
                const opcode = arch.Opcode.parse(self.options.version, token.text) orelse {
                    msg.* = .{
                        .location = token.location,
                        .err = "UnexpectedToken",
                        .msg = try std.fmt.allocPrint(self.options.allocator, "{s} is not a valid UE {s} instruction", .{ token.text, @tagName(self.options.version) }),
                    };
                    return error.UnexpectedToken;
                };
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
                                value.* = try self.acceptExpression(msg);

                                try operands.append(value);

                                if ((i + 1) == opcode.operandCount()) break;
                                _ = try self.core.accept(comptime ruleset.is(.@","));
                            }
                            break :blk operands;
                        },
                    },
                };
            }

            msg.* = .{
                .location = token.location,
                .err = "InvalidExpression",
                .msg = try std.fmt.allocPrint(self.options.allocator, "Unexpected {s} as {s}", .{ token.text, @tagName(token.type) }),
            };
            return error.InvalidExpression;
        },
    };
}

test "Parsing expressions" {
    const options = Options{
        .allocator = std.testing.allocator,
        .version = .v2,
    };

    var msg: ?Message = null;

    try std.testing.expectEqual(@as(usize, 0b11), (try @constCast(&init(options, "0b11", null)).acceptExpression(&msg)).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 0o11), (try @constCast(&init(options, "0o11", null)).acceptExpression(&msg)).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 0x11), (try @constCast(&init(options, "0x11", null)).acceptExpression(&msg)).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 11), (try @constCast(&init(options, "11", null)).acceptExpression(&msg)).unsignedNumber);

    try std.testing.expectEqualStrings("Hellord", (try @constCast(&init(options, "\"Hellord\"", null)).acceptExpression(&msg)).string);
}

test "Parsing builtin" {
    var msg: ?Message = null;
    const section = try @constCast(&init(.{
        .allocator = std.testing.allocator,
        .version = .v2,
    }, "%section(\"code\")", null)).acceptBuiltin(&msg);
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

    var msg: ?Message = null;
    const symbol = try @constCast(&init(options, "std = %import(\"std\")", null)).acceptSymbolConstant(&msg);
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
