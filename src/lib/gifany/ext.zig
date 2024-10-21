const std = @import("std");
const block = @import("block.zig");

pub const ExtType = enum(u8) {
    Graphic = 0xf9,
    PlainText = 0x01,
    Application = 0xff,
    Comment = 0xfe,
};

pub const Extension = struct {
    label: ExtType,
    data: [][]u8,
};

pub fn readExtension(reader: *const std.io.AnyReader, alloc: *std.mem.Allocator) !Extension {
    const label = try reader.readByte();
    const data = try block.readBlocks(reader, alloc);

    return Extension {
        .label = @enumFromInt(label),
        .data = data,
    };
}

