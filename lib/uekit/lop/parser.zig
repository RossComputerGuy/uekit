const std = @import("std");
const ptk = @import("parser-toolkit");
const arch = @import("../arch.zig");
const Parser = @This();

pub const Builtin = @import("parser/builtin.zig");
pub const Expression = @import("parser/expr.zig").Expression;
pub const Symbol = @import("parser/symbol.zig");

pub const Error = error{
    InvalidExpression,
    InvalidBuiltin,
    UnexpectedToken,
    UnexpectedCharacter,
    DuplicateSymbol,
    EndOfStream,
} || std.mem.Allocator.Error || std.fmt.ParseIntError;

pub const Message = struct {
    location: ptk.Location,
    err: []const u8,
    msg: []const u8,

    pub fn format(self: Message, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try writer.print("{} ({s}): {s}", .{ self.location, self.err, self.msg });
    }

    pub inline fn init(allocator: std.mem.Allocator, location: ptk.Location, err: anyerror, comptime fmt: []const u8, args: anytype) !Message {
        return .{
            .location = location,
            .err = @errorName(err),
            .msg = try std.fmt.allocPrint(allocator, fmt, args),
        };
    }

    pub const errors = struct {
        pub inline fn UnexpectedToken(allocator: std.mem.Allocator, token: Tokenizer.Token, comptime expected: anytype) !Message {
            return Message.init(allocator, token.location, Error.UnexpectedToken, "{s}, got {s} as {s}", .{
                if (@typeInfo(@TypeOf(expected)) == .Null) "Unexpected token" else comptime blk: {
                    const expectedList: [expected.len]TokenType = expected;
                    var value: []const u8 = "";
                    if (expectedList.len > 1) value = value ++ "s";
                    value = value ++ " ";
                    inline for (expectedList, 0..) |expectedToken, i| {
                        value = value ++ @tagName(expectedToken);
                        if ((i + 1) < expectedList.len) value = value ++ ", ";
                    }
                    break :blk "Expected token" ++ value;
                },
                token.text,
                @tagName(token.type),
            });
        }

        pub inline fn EndOfStream(allocator: std.mem.Allocator, location: ptk.Location, comptime expected: anytype) !Message {
            return Message.init(allocator, location, Error.EndOfStream, "{s}, got end of stream", .{
                if (@typeInfo(@TypeOf(expected)) == .Null) "End of stream" else comptime blk: {
                    const expectedList: [expected.len]TokenType = expected;
                    var value: []const u8 = "";
                    if (expectedList.len > 1) value = value ++ "s";
                    value = value ++ " ";
                    inline for (expectedList, 0..) |expectedToken, i| {
                        value = value ++ @tagName(expectedToken);
                        if ((i + 1) < expectedList.len) value = value ++ ", ";
                    }
                    break :blk "Expected token" ++ value;
                },
            });
        }

        pub inline fn OutOfMemory(allocator: std.mem.Allocator, location: ptk.Location, comptime T: type) !Message {
            return Message.init(allocator, location, Error.OutOfMemory, "Internal error, failed to allocate {s}", .{@typeName(T)});
        }

        pub inline fn DuplicateSymbol(allocator: std.mem.Allocator, location: ptk.Location, orig: ptk.Location) !Message {
            return Message.init(allocator, location, Error.DuplicateSymbol, "Symbol already exists at {}", .{orig});
        }
    };
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

pub const Mode = enum {
    normal,
    symbol,
};

pub const State = struct {
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
    errdefer {
        for (syms.items) |sym| sym.deinit();
        syms.deinit();
    }

    while (try parser.accept(messages)) |sym| {
        errdefer sym.deinit();

        for (syms.items) |s| {
            if (std.mem.eql(u8, s.name().items, sym.name().items)) {
                try messages.append(try Message.errors.DuplicateSymbol(options.allocator, sym.location(), s.location()));
                return error.DuplicateSymbol;
            }
        }

        const hasNext = if (syms.items.len > 0) blk: {
            const s = syms.items[syms.items.len - 1];
            break :blk s == .data and s.data.next != null;
        } else false;

        try syms.append(sym);

        if (sym == .data and std.mem.startsWith(u8, sym.name().items, ".") and hasNext) {
            syms.items[syms.items.len - 1].data.prev = try syms.items[syms.items.len - 2].data.name.clone();

            const oldName = try syms.items[syms.items.len - 1].data.name.clone();
            defer oldName.deinit();

            syms.items[syms.items.len - 1].data.name.clearAndFree();
            try syms.items[syms.items.len - 1].data.name.appendSlice(syms.items[syms.items.len - 1].data.prev.?.items);
            try syms.items[syms.items.len - 1].data.name.appendSlice(oldName.items);

            syms.items[syms.items.len - 2].data.next = try syms.items[syms.items.len - 1].data.name.clone();
        }
    }
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

fn peekUnfiltered(self: *Parser) !?Tokenizer.Token {
    const state = self.saveState();
    defer self.restoreState(state);
    return try self.tokenizer.next();
}

fn peekDepthUnfiltered(self: *Parser, n: usize) !?Tokenizer.Token {
    const state = self.saveState();
    defer self.restoreState(state);

    var token: ?Tokenizer.Token = null;
    var i: usize = 0;
    while (i < n) : (i += 1) token = try self.tokenizer.next();
    return token;
}

fn peekDepth(self: *Parser, n: usize) !?Tokenizer.Token {
    const state = self.saveState();
    defer self.restoreState(state);

    var token: ?Tokenizer.Token = null;
    var i: usize = 0;
    while (i < n) : (i += 1) token = try self.core.nextToken();
    return token;
}

fn accept(self: *Parser, messages: *std.ArrayList(Message)) Error!?Symbol.Union {
    var msg: ?Message = null;
    return self.acceptSymbol(&msg) catch |err| switch (err) {
        error.EndOfStream => {
            return if (msg != null) err else null;
        },
        else => {
            try messages.append(msg orelse try Message.init(self.options.allocator, self.tokenizer.current_location, err, "Unrecognized error", .{}));
            return err;
        },
    };
}

fn acceptSymbolName(self: *Parser, msg: *?Message) Error!std.ArrayList(u8) {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    var list = std.ArrayList(u8).init(self.options.allocator);
    errdefer list.deinit();

    const begin = (try self.core.peek()) orelse return error.EndOfStream;

    while (try self.tokenizer.next()) |token| {
        if (token.type == .@"." or token.type == .identifier) {
            list.writer().writeAll(token.text) catch |err| {
                msg.* = switch (err) {
                    error.OutOfMemory => try Message.errors.OutOfMemory(self.options.allocator, token.location, []const u8),
                };
                return err;
            };
        } else if (token.type == .whitespace) {
            if (list.items.len > 0) {
                self.tokenizer.offset -= token.text.len;
                break;
            }
        } else {
            self.tokenizer.offset -= token.text.len;
            break;
        }
    }

    if (list.items.len < 1) {
        msg.* = try Message.errors.UnexpectedToken(self.options.allocator, begin, .{ .@".", .identifier });
        return error.UnexpectedToken;
    }
    return list;
}

fn acceptSymbolConstant(self: *Parser, msg: *?Message) Error!Symbol.Constant {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const location = self.core.tokenizer.current_location;
    const variable = try self.acceptSymbolName(msg);
    errdefer variable.deinit();

    _ = self.core.accept(comptime ruleset.is(.@"=")) catch |err| {
        const token = (try self.core.peek()) orelse {
            msg.* = try Message.errors.EndOfStream(self.options.allocator, self.core.tokenizer.current_location, .{.@"="});
            return error.EndOfStream;
        };
        msg.* = try Message.errors.UnexpectedToken(self.options.allocator, token, .{.@"="});
        return err;
    };

    const prevMode = self.mode;
    self.mode = .symbol;
    defer self.mode = prevMode;

    return .{
        .location = location,
        .name = variable,
        .expr = try self.acceptExpression(msg),
    };
}

fn acceptSymbolData(self: *Parser, msg: *?Message) Error!Symbol.Data {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const location = self.core.tokenizer.current_location;
    const symbol = try self.acceptSymbolName(msg);
    errdefer symbol.deinit();

    _ = self.core.accept(comptime ruleset.is(.@":")) catch |err| {
        const token = (try self.core.peek()) orelse {
            msg.* = try Message.errors.EndOfStream(self.options.allocator, self.core.tokenizer.current_location, .{.@"="});
            return error.EndOfStream;
        };
        msg.* = try Message.errors.UnexpectedToken(self.options.allocator, token, .{.@":"});
        return err;
    };

    var exprs = std.ArrayList(Expression).init(self.options.allocator);
    errdefer {
        for (exprs.items) |item| item.deinit();
        exprs.deinit();
    }

    const prevMode = self.mode;
    self.mode = .symbol;
    defer self.mode = prevMode;

    while (try self.core.peek()) |token| {
        if (token.type == .@".") break;
        if (try self.peekDepth(2)) |tokenSplit| {
            if (tokenSplit.type == .@"=" or tokenSplit.type == .@":") break;
        }

        const expr = try self.acceptExpression(msg);
        errdefer expr.deinit();
        exprs.append(expr) catch |err| {
            msg.* = switch (err) {
                error.OutOfMemory => try Message.errors.OutOfMemory(self.options.allocator, token.location, Expression),
            };
            return err;
        };
    }

    return .{
        .location = location,
        .name = symbol,
        .expressions = exprs,
        .next = if (try self.peekDepthUnfiltered(2)) |token| blk: {
            if (token.type == .@".") {
                const s = self.core.saveState();
                const name = try self.acceptSymbolName(msg);
                self.core.restoreState(s);
                break :blk name;
            }
            break :blk null;
        } else null,
        .prev = null,
    };
}

fn acceptSymbol(self: *Parser, msg: *?Message) Error!Symbol.Union {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    (try self.acceptSymbolName(msg)).deinit();

    const token = (try self.core.nextToken()) orelse return error.EndOfStream;
    self.core.restoreState(state);

    if ((comptime ruleset.is(.@"="))(token.type)) {
        return .{ .constant = try self.acceptSymbolConstant(msg) };
    }

    if ((comptime ruleset.is(.@":"))(token.type)) {
        return .{ .data = try self.acceptSymbolData(msg) };
    }

    msg.* = try Message.errors.UnexpectedToken(self.options.allocator, token, .{ .@"=", .@":" });
    return error.UnexpectedToken;
}

fn acceptBuiltin(self: *Parser, msg: *?Message) Error!Builtin {
    const state = self.core.saveState();
    errdefer self.core.restoreState(state);

    const token = try self.core.accept(comptime ruleset.is(.@"%"));
    const name = try self.core.accept(comptime ruleset.is(.identifier));
    const method = Builtin.Method.parse(name.text) orelse return error.InvalidBuiltin;

    _ = try self.core.accept(comptime ruleset.is(.@"("));

    var params = std.ArrayList(Expression).init(self.options.allocator);
    errdefer {
        for (params.items) |param| param.deinit();
        params.deinit();
    }

    var i: usize = 0;
    while (i < method.parameterCount()) : (i += 1) {
        try params.append(try self.acceptExpression(msg));
        if ((i + 1) == method.parameterCount()) break;
        _ = try self.core.accept(comptime ruleset.is(.@","));
    }

    _ = try self.core.accept(comptime ruleset.is(.@")"));

    return .{
        .location = token.location,
        .method = Builtin.Method.parse(name.text) orelse return error.InvalidBuiltin,
        .params = params,
    };
}

fn acceptExpression(self: *Parser, msg: *?Message) Error!Expression {
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
                        else => {
                            msg.* = try Message.errors.UnexpectedToken(self.options.allocator, token, .{.identifier});
                            return error.UnexpectedToken;
                        },
                    };

                    text = id.text[1..];
                }
            }
        }
        return .{ .unsignedNumber = try std.fmt.parseInt(usize, text, base) };
    }

    if ((comptime ruleset.is(.@"-"))(token.type)) {
        const expr = try self.acceptExpression(msg);
        if (expr != .unsignedNumber) {
            msg.* = try Message.errors.UnexpectedToken(self.options.allocator, token, .{.number});
            return error.UnexpectedToken;
        }
        return .{ .signedNumber = @as(isize, @intCast(expr.unsignedNumber)) * @as(isize, -1) };
    }

    if ((comptime ruleset.is(.@"%"))(token.type)) {
        self.core.restoreState(state);
        return .{ .builtin = try self.acceptBuiltin(msg) };
    }

    if ((comptime ruleset.is(.string))(token.type)) {
        var list = std.ArrayList(u8).init(self.options.allocator);
        try list.appendSlice(token.text[1..(token.text.len - 1)]);
        return .{ .string = list };
    }

    return switch (self.mode) {
        .normal => {
            self.core.restoreState(state);
            return .{ .literal = try self.acceptSymbolName(msg) };
        },
        .symbol => {
            if ((comptime ruleset.is(.identifier))(token.type)) {
                const opcode = arch.FullOpcode.parse(self.options.version, token.text) orelse {
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
                            errdefer {
                                for (operands.items) |item| {
                                    item.*.deinit();
                                    self.options.allocator.destroy(item);
                                }
                                operands.deinit();
                            }

                            const prevMode = self.mode;
                            self.mode = .normal;
                            defer self.mode = prevMode;

                            var i: usize = 0;
                            while (i < opcode.operandCount()) : (i += 1) {
                                const value = try self.options.allocator.create(Expression);
                                errdefer self.options.allocator.destroy(value);
                                value.* = try self.acceptExpression(msg);
                                errdefer value.*.deinit();

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
    errdefer {
        if (msg) |value| options.allocator.free(value.msg);
    }

    try std.testing.expectEqual(@as(usize, 0b11), (try @constCast(&init(options, "0b11", null)).acceptExpression(&msg)).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 0o11), (try @constCast(&init(options, "0o11", null)).acceptExpression(&msg)).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 0x11), (try @constCast(&init(options, "0x11", null)).acceptExpression(&msg)).unsignedNumber);
    try std.testing.expectEqual(@as(usize, 11), (try @constCast(&init(options, "11", null)).acceptExpression(&msg)).unsignedNumber);

    const str = (try @constCast(&init(options, "\"Hellord\"", null)).acceptExpression(&msg)).string;
    defer str.deinit();
    try std.testing.expectEqualStrings("Hellord", str.items);
}

test "Parsing builtin" {
    var msg: ?Message = null;
    errdefer {
        if (msg) |value| std.testing.allocator.free(value.msg);
    }

    const section = try @constCast(&init(.{
        .allocator = std.testing.allocator,
        .version = .v2,
    }, "%section(\"code\")", null)).acceptBuiltin(&msg);
    defer section.deinit();

    try std.testing.expectEqual(@as(usize, 1), section.location.line);
    try std.testing.expectEqual(@as(usize, 1), section.location.column);
    try std.testing.expectEqual(@as(?[]const u8, null), section.location.source);
    try std.testing.expectEqual(Builtin.Method.section, section.method);
    try std.testing.expectEqual(@as(usize, 1), section.params.items.len);
    try std.testing.expectEqualStrings("code", section.params.items[0].string.items);
}

test "Parsing symbol constant" {
    const options = Options{
        .allocator = std.testing.allocator,
        .version = .v2,
    };

    var msg: ?Message = null;
    errdefer {
        if (msg) |value| options.allocator.free(value.msg);
    }

    // FIXME: this works in a file but not here.
    const symbol = @constCast(&init(options, "std = %import(\"std\")", null)).acceptSymbolConstant(&msg) catch |err| {
        std.debug.print("Parser error message: {?any}\n", .{msg});
        return err;
    };
    defer symbol.deinit();

    try std.testing.expectEqual(@as(usize, 1), symbol.location.line);
    try std.testing.expectEqual(@as(usize, 1), symbol.location.column);
    try std.testing.expectEqual(@as(?[]const u8, null), symbol.location.source);
    try std.testing.expectEqual(Builtin.Method.import, symbol.expr.builtin.method);
    try std.testing.expectEqual(@as(usize, 1), symbol.expr.builtin.location.line);
    try std.testing.expectEqual(@as(usize, 7), symbol.expr.builtin.location.column);
    try std.testing.expectEqual(@as(usize, 1), symbol.expr.builtin.params.items.len);
    try std.testing.expectEqualStrings("std", symbol.expr.builtin.params.items[0].string.items);
}

test "Parsing symbol data" {
    const options = Options{
        .allocator = std.testing.allocator,
        .version = .v2,
    };

    var msg: ?Message = null;
    errdefer {
        if (msg) |value| options.allocator.free(value.msg);
    }

    const symbol = @constCast(&init(options, "loop:\n\tscf\n\tbz loop\n", null)).acceptSymbolData(&msg) catch |err| {
        std.debug.print("Parser error message: {?any}\n", .{msg});
        return err;
    };
    defer symbol.deinit();

    try std.testing.expectEqual(@as(usize, 1), symbol.location.line);
    try std.testing.expectEqual(@as(usize, 1), symbol.location.column);
    try std.testing.expectEqual(@as(?[]const u8, null), symbol.location.source);
    try std.testing.expectEqual(@as(usize, 1), symbol.expressions.items.len);
    try std.testing.expectEqual(arch.PseudoOpcode.jmp, symbol.expressions.items[0].instruction.opcode.pseudo);
}
