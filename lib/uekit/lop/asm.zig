const std = @import("std");
const Allocator = std.mem.Allocator;
const arch = @import("../arch.zig");
const ptk = @import("parser-toolkit");
const Parser = @import("parser.zig");
const metap = @import("meta+");
const SymbolTable = @import("symtbl.zig");
const Assembler = @This();

pub const OutputFormat = enum {
    usagi,
    binary,
};

pub const Module = struct {
    name: []const u8,
    path: []const u8,

    pub fn format(self: Module, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        try writer.writeAll(@typeName(Module));
        try writer.print("{{ .name = {s}, .path = {s} }}", .{ self.name, self.path });
    }
};

pub const Import = struct {
    module: Module,
    path: []const u8,
    isRoot: bool,
    symbols: std.ArrayList(Parser.Symbol.Union),

    pub fn format(self: Import, comptime _: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;

        try writer.writeAll(@typeName(Import));
        try writer.writeAll("{ .name = ");

        if (self.name()) |nv| {
            defer self.symbols.allocator.free(nv);
            try writer.writeAll(nv);
        } else |err| {
            try writer.writeAll(@errorName(err));
        }

        try writer.print(", .module = {}, .path = {s}, .isRoot = {}, .symbols = {any} }}", .{
            self.module,
            self.path,
            self.isRoot,
            self.symbols.items,
        });
    }

    pub fn symbol(self: Import, symbolName: []const u8) ?*Parser.Symbol.Union {
        const end = if (std.mem.indexOf(u8, symbolName, ".")) |i| if (i > 0) i else symbolName.len else symbolName.len;
        for (self.symbols.items) |*sym| {
            if (std.mem.eql(u8, sym.name().items, symbolName[0..end])) {
                return sym;
            }
        }
        return null;
    }

    pub fn name(self: Import) ![]const u8 {
        const relPath = try std.fs.path.relative(self.symbols.allocator, self.module.path, if (self.isRoot) std.fs.path.dirname(self.path) orelse return error.InvalidPath else self.path[0..(self.path.len - std.fs.path.extension(self.path).len)]);
        defer self.symbols.allocator.free(relPath);

        const prefixedRelPath = try std.fs.path.join(self.symbols.allocator, &.{ self.module.name, relPath });
        defer self.symbols.allocator.free(prefixedRelPath);

        return try std.mem.replaceOwned(u8, self.symbols.allocator, prefixedRelPath, &.{std.fs.path.sep}, ".");
    }

    pub fn deinit(self: Import) void {
        self.symbols.allocator.free(self.path);
        for (self.symbols.items) |sym| sym.deinit();
        self.symbols.deinit();
    }
};

pub const Options = struct {
    allocator: Allocator,
    version: arch.Version,
    entrypoint: []const u8 = "root._start",
};

version: arch.Version,
imports: std.ArrayList(Import),
symbols: std.ArrayList(*Parser.Symbol.Data),
entrypoint: *Parser.Symbol.Data,

pub fn create(options: Options, modules: []const Module, root: []const u8, messages: *std.ArrayList(Parser.Message)) !*Assembler {
    const self = try options.allocator.create(Assembler);
    errdefer options.allocator.destroy(self);

    self.* = .{
        .version = options.version,
        .imports = std.ArrayList(Import).init(options.allocator),
        .symbols = std.ArrayList(*Parser.Symbol.Data).init(options.allocator),
        .entrypoint = undefined,
    };
    errdefer self.deinit();

    {
        const source = @src();
        _ = try self.import(.{
            .name = "root",
            .path = try options.allocator.dupe(u8, std.fs.path.dirname(root) orelse return error.InvalidPath),
        }, root, messages, true, .{
            .source = source.file,
            .line = source.line,
            .column = source.column,
        });
    }

    for (modules) |module| {
        const source = @src();
        _ = try self.import(.{
            .name = module.name,
            .path = try options.allocator.dupe(u8, std.fs.path.dirname(module.path) orelse return error.InvalidPath),
        }, module.path, messages, true, .{
            .source = source.file,
            .line = source.line,
            .column = source.column,
        });
    }

    {
        const source = @src();
        if (try self.symbol(options.entrypoint)) |entrypoint| {
            if (entrypoint.* != .data) {
                try messages.append(try Parser.Message.init(options.allocator, entrypoint.location(), error.InvalidEntrypoint, "Entrypoint must be a data symbol", .{}));
                return error.InvalidEntrypoint;
            }

            self.entrypoint = &entrypoint.data;
            try self.addDataSymbol(self.entrypoint, messages);
        } else {
            try messages.append(try Parser.Message.init(options.allocator, .{
                .source = source.file,
                .line = source.line,
                .column = source.column,
            }, error.InvalidEntrypoint, "Entrypoint does not exist", .{}));
            return error.InvalidEntrypoint;
        }
    }
    return self;
}

const SymbolError = error{
    Unexpected,
    UnexpectedExpression,
    CurrentWorkingDirectoryUnlinked,
    InvalidPath,
    InvalidSymbol,
    InvalidImport,
} || Allocator.Error;

fn hasDataSymbol(self: *Assembler, sym: *Parser.Symbol.Data) bool {
    for (self.symbols.items) |s| {
        if ((sym.location.source == null and s.location.source != null) or (sym.location.source != null and s.location.source == null)) continue;

        if (std.mem.eql(u8, sym.location.source.?, s.location.source.?) and sym.location.line == s.location.line and sym.location.column == s.location.column) {
            return true;
        }
    }
    return false;
}

fn addDataSymbolForExpression(self: *Assembler, imported: *Import, expr: *Parser.Expression, mode: Parser.Mode, messages: *std.ArrayList(Parser.Message)) SymbolError!void {
    switch (mode) {
        .symbol => switch (expr.*) {
            .instruction => |instr| {
                if (instr.operands) |operands| {
                    for (operands.items) |operand| {
                        try self.addDataSymbolForExpression(imported, operand, .normal, messages);
                    }
                }
            },
            .builtin => {},
            else => {},
        },
        .normal => {
            if (expr.* == .literal) {
                if (imported.symbol(expr.literal.items) orelse try self.lookupSymbol(imported, expr.literal.items)) |sym| {
                    if (sym.* == .data) try self.addDataSymbol(&sym.data, messages);
                } else {
                    std.debug.print("{}\n", .{imported.symbols.items[imported.symbols.items.len - 1]});
                    return error.InvalidSymbol;
                }
            }
        },
    }
}

fn addDataSymbol(self: *Assembler, sym: *Parser.Symbol.Data, messages: *std.ArrayList(Parser.Message)) SymbolError!void {
    if (self.hasDataSymbol(sym)) return;

    const imported = self.lookupImportByPath(sym.location.source.?) orelse return error.InvalidImport;

    if (sym.next) |n| {
        for (imported.symbols.items) |*s| {
            if (std.mem.eql(u8, n.items, s.name().items) and s.* == .data) {
                try self.addDataSymbol(&s.data, messages);
                break;
            }
        }
    }

    try self.symbols.append(sym);
    for (sym.expressions.items) |*expr| {
        try self.addDataSymbolForExpression(imported, expr, .symbol, messages);
    }
}

pub fn lookupSymbol(self: *Assembler, imported: *Import, name: []const u8) !?*Parser.Symbol.Union {
    const end = std.mem.indexOf(u8, name, ".") orelse name.len;
    const end2 = std.mem.indexOf(u8, name, ".") orelse (name.len - 1);
    if (imported.symbol(name[0..end])) |sym| {
        if (std.mem.indexOf(u8, name, ".") == null) return sym;

        if (sym.* == .constant) {
            if (sym.constant.expr == .builtin) {
                if (sym.constant.expr.builtin.method == .import) {
                    const importName = sym.constant.expr.builtin.params.items[0];

                    if (try self.lookupImport(importName.string.items)) |newImported| {
                        return self.lookupSymbol(newImported, name[(end2 + 1)..]);
                    } else {
                        const importPath = if (std.fs.path.isAbsolute(importName.string.items)) try self.imports.allocator.dupe(u8, importName.string.items) else try std.fs.path.join(self.imports.allocator, &.{ imported.module.path, importName.string.items });
                        defer self.imports.allocator.free(importPath);

                        if (self.lookupImportByPath(importPath)) |newImported| {
                            return self.lookupSymbol(newImported, name[end2..]);
                        }
                    }
                    return null;
                }
            }
        }
    }
    return null;
}

pub fn lookupImportByPath(self: *Assembler, path: []const u8) ?*Import {
    for (self.imports.items) |*imported| {
        if (std.mem.eql(u8, imported.path, path)) return imported;
    }
    return null;
}

pub fn lookupImport(self: *Assembler, name: []const u8) !?*Import {
    for (self.imports.items) |*imported| {
        const importedName = try imported.name();
        defer self.imports.allocator.free(importedName);
        if (std.mem.eql(u8, importedName, name)) return imported;
    }
    return null;
}

pub fn symbol(self: *Assembler, name: []const u8) !?*Parser.Symbol.Union {
    const end = std.mem.indexOf(u8, name, ".") orelse return null;
    if (try self.lookupImport(name[0..end])) |imported| {
        return self.lookupSymbol(imported, name[(end + 1)..]);
    }
    return null;
}

pub fn import(self: *Assembler, module: Module, path: []const u8, messages: *std.ArrayList(Parser.Message), isRoot: bool, location: ptk.Location) !*Import {
    if (self.lookupImportByPath(path)) |imported| return imported;

    const file = std.fs.openFileAbsolute(path, .{}) catch |err| {
        try messages.append(try Parser.Message.init(self.imports.allocator, location, err, "Failed to import {s} for module {s}", .{ path, module.name }));
        return err;
    };
    defer file.close();

    const fileSize = (try file.metadata()).size();
    const code = try file.readToEndAlloc(self.imports.allocator, fileSize);
    defer self.imports.allocator.free(code);

    const syms = try Parser.parse(.{
        .allocator = self.imports.allocator,
        .version = self.version,
    }, messages, code, path);
    errdefer {
        for (syms.items) |sym| sym.deinit();
        syms.deinit();
    }

    const imp = try self.imports.addOne();
    errdefer {
        _ = self.imports.pop();
    }
    imp.* = .{
        .module = module,
        .path = path,
        .symbols = syms,
        .isRoot = isRoot,
    };

    for (syms.items) |sym| {
        if (sym == .constant) {
            if (sym.constant.expr == .builtin) {
                if (sym.constant.expr.builtin.method == .import) {
                    const importName = sym.constant.expr.builtin.params.items[0];
                    // TODO: the parser should take care of this
                    if (importName != .string) {
                        try messages.append(try Parser.Message.init(self.imports.allocator, sym.constant.expr.builtin.location, error.InvalidImport, "Expected argument 2 to be a string", .{}));
                        return error.InvalidImport;
                    }

                    if (try self.lookupImport(importName.string.items) == null) {
                        const importPath = if (std.fs.path.isAbsolute(importName.string.items)) try self.imports.allocator.dupe(u8, importName.string.items) else try std.fs.path.join(self.imports.allocator, &.{ module.path, importName.string.items });
                        errdefer self.imports.allocator.free(importPath);
                        _ = try self.import(module, importPath, messages, false, sym.constant.expr.builtin.location);
                    }
                }
            }
        }
    }
    return imp;
}

pub const WriteOptions = struct {
    file: std.fs.File,
    address: usize = 0,
};

pub fn writeBinary(self: *Assembler, options: WriteOptions) !SymbolTable {
    _ = options;

    var symtbl = try SymbolTable.init(self.imports.allocator);
    errdefer symtbl.deinit();

    var codeEnd: usize = 0;
    for (self.symbols.items) |sym| {
        if (std.mem.eql(u8, sym.section(), "code")) {
            codeEnd += sym.size(self.version);
        }
    }

    std.debug.print("{}\n", .{codeEnd});

    return symtbl;
}

pub fn write(self: *Assembler, options: WriteOptions, fmt: OutputFormat) !SymbolTable {
    return switch (fmt) {
        .binary => self.writeBinary(options),
        else => error.InvalidOutputFormat,
    };
}

pub fn deinit(self: *Assembler) void {
    for (self.imports.items) |imp| imp.deinit();
    self.imports.deinit();
    self.symbols.deinit();
    self.imports.allocator.destroy(self);
}
