const std = @import("std");
const builtin = @import("builtin");
const Emulator = @import("../emu.zig");
const arch = @import("../../arch/v2.zig");

pub fn setCarry(self: *Emulator, value: *usize) !void {
    const c = try self.register("c");

    if (value.* > 255) {
        value.* -= 256;
        try c.set(1);
    } else {
        try c.set(0);
    }
}

pub fn execute(self: *Emulator, instr: arch.Instruction) !void {
    switch (instr.opcode) {
        .bz => {
            const z = try self.register("z");
            if (z.value > 0) self.pc = instr.address;
        },
        .bl => {
            const c = try self.register("c");
            if (c.value > 0) self.pc = instr.address;
        },
        .lda => {
            const rra = try self.register("rra");
            try rra.set(instr.address);
        },
        .ldl => {
            const rra = try self.register("rra");
            var buf: [1]u8 = undefined;
            _ = try self.mmu.read(instr.address, &buf);
            try rra.set(buf[0]);
        },
        .ldp => {
            const rrp = try self.register("rrp");
            const rra = try self.register("rra");

            var buf: [1]u8 = undefined;
            _ = try self.mmu.read(rrp.value, &buf);
            try rra.set(buf[0]);
        },
        .stl => {
            const rra = try self.register("rra");

            var buf: [2]u8 = undefined;
            std.mem.writeInt(u16, &buf, @intCast(rra.value), builtin.cpu.arch.endian());
            _ = try self.mmu.write(instr.address, &buf);
        },
        .stp => {
            const rra = try self.register("rra");
            const rrp = try self.register("rrp");

            var buf: [2]u8 = undefined;
            std.mem.writeInt(u16, &buf, @intCast(rra.value), builtin.cpu.arch.endian());
            _ = try self.mmu.write(rrp.value, &buf);
        },
        .lrp => {
            const rrp = try self.register("rrp");
            try rrp.set(instr.address);
        },
        .inp => {
            const rrp = try self.register("rrp");
            try rrp.setOverflow(rrp.value + 1);
        },
        .scf => {
            const c = try self.register("c");
            const z = try self.register("z");

            try c.set(if ((instr.address & 1) != 0) @as(usize, 1) else @as(usize, 0));
            try z.set(if ((instr.address & 2) != 0) @as(usize, 1) else @as(usize, 0));
        },
        .adc => {
            const rra = try self.register("rra");
            const c = try self.register("c");
            const z = try self.register("z");

            var buf: [1]u8 = undefined;
            _ = try self.mmu.read(instr.address, &buf);

            try rra.set(rra.value + (if (c.value > 0) @as(usize, 1) else @as(usize, 0)) + buf[0]);

            try setCarry(self, &rra.value);
            try z.set(if (rra.value == 0) @as(usize, 1) else @as(usize, 0));
        },
        .cmp => {
            const rra = try self.register("rra");
            const z = try self.register("z");

            var buf: [1]u8 = undefined;
            _ = try self.mmu.read(instr.address, &buf);

            var tmp = rra.value + buf[0];
            try setCarry(self, &tmp);
            try z.set(if (tmp == 0) @as(usize, 1) else @as(usize, 0));
        },
        .srl => {
            const rra = try self.register("rra");
            try rra.set(rra.value << 1);
        },
        .nand => {
            const rra = try self.register("rra");
            const z = try self.register("z");

            var buf: [1]u8 = undefined;
            _ = try self.mmu.read(instr.address, &buf);

            try rra.set(~(rra.value & buf[0]));
            try z.set(if (rra.value == 0) @as(usize, 1) else @as(usize, 0));
        },
        .ori => {
            const rra = try self.register("rra");
            const z = try self.register("z");

            var buf: [1]u8 = undefined;
            _ = try self.mmu.read(instr.address, &buf);

            try rra.set(rra.value | buf[0]);
            try z.set(if (rra.value == 0) @as(usize, 1) else @as(usize, 0));
        },
        .ore => {
            const rra = try self.register("rra");
            const z = try self.register("z");

            var buf: [1]u8 = undefined;
            _ = try self.mmu.read(instr.address, &buf);

            try rra.set(rra.value ^ buf[0]);
            try z.set(if (rra.value == 0) @as(usize, 1) else @as(usize, 0));
        },
    }
}
