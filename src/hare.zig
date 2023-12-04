const common = @import("common");
const clap = @import("clap");
const uekit = @import("uekit");
const std = @import("std");

pub fn main() !void {
    const stderr = common.getStdErr();
    const stdout = common.getStdOut();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-v, --version <ver>    Sets the UE version to dissasemble the binary as.
        \\-i, --count <usize>    Sets the number of instructions to dissasemble.
        \\<path>                 Path to the executable to dissasemble.
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

    const version = res.args.version orelse .v2;

    const file = try std.fs.openFileAbsolute(res.positionals[0], .{});
    defer file.close();

    const fileSize = (try file.metadata()).size();
    const InstructionSize = version.instructionSize();
    const instrCount = res.args.count orelse (fileSize / InstructionSize);

    try stdout.print("Path: {s} ({})\nInstructions:\n", .{
        res.positionals[0],
        std.fmt.fmtIntSizeDec(fileSize),
    });

    var i: usize = 0;
    var addr: usize = 0;
    while (i < instrCount) : (i += 1) {
        const instr = try uekit.arch.Instruction.read(version, file.reader());
        try stdout.print("\t0x{x} - {}\n", .{ addr, instr.formatFor(version) });
        addr += InstructionSize;
    }

    var rem = fileSize - addr;
    if (rem > 0) {
        try stdout.print("Data:\n", .{});

        while (rem > 0) : (rem -= @sizeOf(u8)) {
            const byte = try file.reader().readInt(u8, version.endian());
            try stdout.print("\t0x{x} - 0x{x}\n", .{ addr, byte });
            addr += @sizeOf(u8);
        }
    }
}
