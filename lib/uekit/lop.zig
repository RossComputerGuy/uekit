pub const Assembler = @import("lop/asm.zig");
pub const Parser = @import("lop/parser.zig");
pub const Executable = @import("lop/exec.zig");
pub const SymbolTable = @import("lop/symtbl.zig");

test {
    _ = Parser;
}
