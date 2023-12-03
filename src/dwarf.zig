const clap = @import("clap");
const uekit = @import("uekit");
const std = @import("std");

pub fn main() !void {
    const stderr = std.io.getStdErr();
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-e, --exec <str>       Loads the path to the binary into the emulator.
        \\-v, --version <ver>    Sets the UE version to run the emulator as.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, comptime .{
        .str = clap.parsers.string,
        .ver = clap.parsers.enumeration(uekit.arch.Version),
    }, .{
        .diagnostic = &diag,
    }) catch |err| {
        diag.report(stderr.writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(stderr.writer(), clap.Help, &params, .{});

    const emu = try uekit.dwarf.Emulator.create(.{
        .allocator = std.heap.page_allocator,
        .version = res.args.version orelse .v2,
    });
    defer emu.deinit();

    if (res.args.exec) |exec| {
        try emu.mmu.entries.append(try uekit.dwarf.Mmu.Entry.types.file.create(.{
            .allocator = emu.allocator,
            .address = 0,
            .flags = .{
                .readable = 1,
                .writable = 0,
            },
            .path = exec,
        }));
    }

    emu.run() catch |err| {
        stderr.writer().print("Failed to execute at 0x{x} ({?any}): {s}\nCPU Registers:\n", .{
            emu.pc,
            emu.instr,
            @errorName(err),
        }) catch {};
        for (emu.registers) |reg| {
            stderr.writer().print("\t{s} - 0x{x}\n", .{ reg.name, reg.value }) catch {};
        }
        return err;
    };

    std.debug.print("{}\n", .{emu});
}
