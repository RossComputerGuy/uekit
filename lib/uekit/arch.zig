pub const versions = struct {
    pub const v2 = @import("arch/v2.zig");
};

pub const Opcode = union(enum) {
    v2: versions.v2.Opcode,
};

pub const Instruction = union(enum) {
    v2: versions.v2.Instruction,
};

test {
    _ = versions.v2;
}
