const arch = @import("../arch.zig");

pub const Location = packed struct {
    offset: u16,
    size: u16,
};

pub const SectionHeader = packed struct {
    name: Location,
    symbols: DataTable,
};

pub const SymbolHeader = packed struct {
    name: Location,
    data: Location,

    pub const DebugHeader = packed struct {
        filePath: Location,
        line: u16,
        column: u16,
    };
};

pub const DataTable = packed struct {
    location: Location,
    count: u16,
};

pub const Header = packed struct {
    pub const Version = enum(u8) {
        v1 = 0,
    };

    pub const Flags = packed struct {
        hasDebug: u1,
        reserved: u7 = 0,
    };

    magic: [5]u8 = "うさぎ",
    version: Version,
    archVersion: arch.Version,
    sections: DataTable,
    flags: Flags,
    entrypoint: Location,
};
