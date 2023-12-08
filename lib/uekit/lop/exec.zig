const arch = @import("../arch.zig");

pub const Location = packed struct {
    /// Offset relative to the parent structure's location
    offset: u16,
    /// Size of the data to be located
    size: u16,
};

pub const SectionHeader = packed struct {
    pub const Flags = packed struct {
        /// Whether the section contains a symbol table
        hasSymbols: u1,
        /// Reserved & padded for future use
        reserved: u7 = 0,
    };

    /// Base address within the executable's address space for the section
    address: u16,
    /// Location to the name of the section
    name: Location,
    /// Location to the section's data
    data: Location,
};

pub const SymbolHeader = packed struct {
    /// Location of the name of the symbol
    name: Location,
    /// Location of the symbol's data
    data: Location,

    pub const DebugHeader = packed struct {
        /// Location to the string which contains the file path on the build machine
        filePath: Location,
        /// File line number on the build machine
        line: u16,
        /// File column number on the build machine
        column: u16,
    };
};

pub const DataTable = packed struct {
    /// Location info for the data table
    location: Location,
    /// Number of entries in the data table
    count: u16,
};

pub const Header = packed struct {
    pub const Version = enum(u8) {
        /// Version 1
        v1 = 0,
    };

    pub const Flags = packed struct {
        /// Whether the symbols have debug info
        hasDebug: u1,
        /// Reserved & padded for future use
        reserved: u7 = 0,
    };

    /// Header magic
    magic: [5]u8 = "うさぎ",
    /// Usagi binary format version
    version: Version,
    /// Usagi Electric CPU ISA version
    archVersion: arch.Version,
    /// Data table defining section info
    sections: DataTable,
    /// Flags
    flags: Flags,
    /// Base address
    address: u16,
    /// entrypoint of the executable
    entrypoint: Location,
};
