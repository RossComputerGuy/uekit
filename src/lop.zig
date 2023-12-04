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
}
