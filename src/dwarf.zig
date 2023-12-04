const common = @import("common");
const clap = @import("clap");
const uekit = @import("uekit");
const std = @import("std");

pub fn main() !void {
    const stderr = std.io.getStdErr();
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-e, --exec <path>      Loads the path to the binary into the emulator.
        \\-v, --version <ver>    Sets the UE version to run the emulator as.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, common.parsers, .{
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

    try emu.mmu.entries.append(try uekit.dwarf.Mmu.Entry.types.console.create(.{
        .allocator = emu.allocator,
        .stdout = std.io.getStdOut(),
        .stdin = std.io.getStdIn(),
    }));

    var start: usize = 0;
    if (res.args.exec) |exec| {
        const entry = try uekit.dwarf.Mmu.Entry.types.file.create(.{
            .allocator = emu.allocator,
            .address = 0,
            .flags = .{
                .readable = 1,
                .writable = 0,
            },
            .path = exec,
        });
        try emu.mmu.entries.append(entry);
        start = entry.size;
    }

    try emu.mmu.entries.append(try uekit.dwarf.Mmu.Entry.types.ram.create(.{
        .allocator = emu.allocator,
        .address = start,
        .size = emu.mmu.free(),
        .flags = .{
            .readable = 1,
            .writable = 1,
        },
    }));

    emu.run() catch |err| {
        stderr.writer().print("Failed to execute at 0x{x} ({?any}): {s}\nCPU Registers:\n", .{
            emu.pc - emu.version.instructionSize(),
            emu.instr,
            @errorName(err),
        }) catch {};
        for (emu.registers) |reg| {
            stderr.writer().print("\t{s} - 0x{x}\n", .{ reg.name, reg.value }) catch {};
        }
        return err;
    };
}
