const std = @import("std");
const Allocator = std.mem.Allocator;
const arch = @import("../arch.zig");
const ptk = @import("parser-toolkit");
const Parser = @import("parser.zig");
const Assembler = @This();

pub const Module = struct {
    name: []const u8,
    path: []const u8,
};

pub const Import = struct {
    module: Module,
    path: []const u8,
    isRoot: bool,
    symbols: std.ArrayList(Parser.Symbol.Union),

    pub fn name(self: Import) ![]const u8 {
        const relPath = try std.fs.path.relative(self.symbols.allocator, std.fs.path.dirname(self.path) orelse "", self.module.path);
        defer self.symbols.allocator.free(relPath);

        const prefixedRelPath = try std.fs.path.join(self.symbols.allocator, &.{ self.module.name, relPath });
        defer self.symbols.allocator.free(prefixedRelPath);

        return try std.mem.replaceOwned(u8, self.symbols.allocator, prefixedRelPath, std.fs.path.sep, ".");
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
};

version: arch.Version,
imports: std.ArrayList(Import),

pub fn create(options: Options, modules: []const Module, root: []const u8, messages: *std.ArrayList(Parser.Message)) !*Assembler {
    const self = try options.allocator.create(Assembler);
    errdefer options.allocator.destroy(self);

    self.* = .{
        .version = options.version,
        .imports = std.ArrayList(Import).init(options.allocator),
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
    return self;
}

pub fn import(self: *Assembler, module: Module, path: []const u8, messages: *std.ArrayList(Parser.Message), isRoot: bool, location: ptk.Location) !*Import {
    for (self.imports.items) |*imp| {
        if (std.mem.eql(u8, imp.path, path)) return imp;
    }

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

                    var isImported = false;
                    for (self.imports.items) |imported| {
                        if (std.mem.eql(u8, imported.module.name, importName.string.items) and imported.isRoot) {
                            isImported = true;
                            break;
                        }
                    }

                    if (!isImported) {
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

pub fn deinit(self: *Assembler) void {
    for (self.imports.items) |imp| imp.deinit();
    self.imports.deinit();
    self.imports.allocator.destroy(self);
}
