const common = @import("common");
const clap = @import("clap");
const uekit = @import("uekit");
const std = @import("std");

pub fn main() !void {
    const stderr = common.getStdErr();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help                 Display this help and exit.
        \\-v, --version <ver>        Sets the UE version to dissasemble the binary as.
        \\-m, --module <mod>...      Adds a module to be available as an import.
        \\-o, --output <path>        Sets the binary output path (default: a.out).
        \\-f, --output-format <ofmt> Sets the output format.
        \\-s, --sym <path>           Sets the symbol table output path.
        \\-e, --entrypoint <str>     Sets the entrypoint of the executable.
        \\-t, --stack <str>          Sets the symbol to use for the stack.
        \\<path>                     Path to the root assembly file.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, common.parsers, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals.len != 1)
        return clap.help(stderr, clap.Help, &params, .{});

    var messages = std.ArrayList(uekit.lop.Parser.Message).init(common.allocator);
    defer messages.deinit();

    const @"asm" = uekit.lop.Assembler.create(.{
        .version = res.args.version orelse .v2,
        .allocator = common.allocator,
        .entrypoint = res.args.entrypoint orelse "root._start",
        .stack = res.args.stack,
    }, res.args.module, res.positionals[0], &messages) catch |err| {
        try stderr.print("Errors:\n", .{});
        for (messages.items) |msg| {
            try stderr.print("\t{}\n", .{msg});
            common.allocator.free(msg.msg);
        }
        return err;
    };
    defer @"asm".deinit();

    const file = try std.fs.createFileAbsolute(res.args.output orelse try common.path("a.out"), .{});
    defer file.close();

    const symtbl = try @"asm".write(.{
        .file = file,
    }, res.args.@"output-format" orelse .binary);
    defer symtbl.deinit();

    if (res.args.sym) |symtblPath| {
        const symtblFile = try std.fs.createFileAbsolute(symtblPath, .{});
        defer symtblFile.close();
        try std.json.stringify(symtbl.list.items, .{}, symtblFile.writer());
    }
}
