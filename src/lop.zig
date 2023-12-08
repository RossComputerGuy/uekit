const common = @import("common");
const clap = @import("clap");
const uekit = @import("uekit");
const std = @import("std");

pub fn main() !void {
    const stderr = common.getStdErr();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-v, --version <ver>    Sets the UE version to dissasemble the binary as.
        \\-m, --module <mod>...  Adds a module to be available as an import.
        \\-o, --output <path>    Sets the binary output path (default: a.out).
        \\-s, --sym <path>       Sets the symbol table output path.
        \\-e, --entrypoint <str> Sets the entrypoint of the executable.
        \\<path>                 Path to the root assembly file.
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
    }, res.args.module, res.positionals[0], &messages) catch |err| {
        try stderr.print("Errors:\n", .{});
        for (messages.items) |msg| {
            try stderr.print("\t{}\n", .{msg});
            common.allocator.free(msg.msg);
        }
        return err;
    };
    defer @"asm".deinit();

    for (@"asm".imports.items) |imp| try stderr.print("{}\n", .{imp});

    try stderr.print("Entrypoint: {}\n", .{@"asm".entrypoint});
}
