const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_docs = b.option(bool, "no-docs", "skip installing documentation") orelse false;

    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });

    const uekit = b.addModule("uekit", .{
        .source_file = .{ .path = b.pathFromRoot("lib/uekit.zig") },
    });

    const exec_dwarf = b.addExecutable(.{
        .name = "dwarf",
        .root_source_file = .{
            .path = b.pathFromRoot("src/dwarf.zig"),
        },
        .target = target,
        .optimize = optimize,
    });

    exec_dwarf.addModule("uekit", uekit);
    exec_dwarf.addModule("clap", clap.module("clap"));
    b.installArtifact(exec_dwarf);

    const exec_hare = b.addExecutable(.{
        .name = "hare",
        .root_source_file = .{
            .path = b.pathFromRoot("src/hare.zig"),
        },
        .target = target,
        .optimize = optimize,
    });

    exec_hare.addModule("uekit", uekit);
    exec_hare.addModule("clap", clap.module("clap"));
    b.installArtifact(exec_hare);

    const step_test = b.step("test", "Run all unit tests");

    const unit_tests = b.addTest(.{
        .root_source_file = .{
            .path = b.pathFromRoot("lib/uekit.zig"),
        },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    step_test.dependOn(&run_unit_tests.step);

    if (!no_docs) {
        const docs = b.addInstallDirectory(.{
            .source_dir = unit_tests.getEmittedDocs(),
            .install_dir = .prefix,
            .install_subdir = "docs",
        });

        b.getInstallStep().dependOn(&docs.step);
    }
}
