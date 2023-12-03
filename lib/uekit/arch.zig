const std = @import("std");

pub const versions = struct {
    pub const v2 = @import("arch/v2.zig");
};

pub const Version = std.meta.DeclEnum(versions);

pub const Opcode = union(enum) {
    v2: versions.v2.Opcode,
};

pub const Instruction = union(enum) {
    v2: versions.v2.Instruction,
};

pub const Register = union(enum) {
    v2: versions.v2.Register,
};

test {
    _ = versions.v2;
}
