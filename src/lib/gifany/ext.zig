const std = @import("std");

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

    var blocks = std.ArrayList([]u8).init(alloc.*);
    defer blocks.deinit();

    var data_size = try reader.readByte();
    while (data_size != 0) : (data_size = try reader.readByte()) {
        const slice = try alloc.alloc(u8, data_size);
        if (try reader.read(slice) != data_size) {
            alloc.free(slice);
            blocks.deinit();
            return error.UncompleteRead;
        }

        try blocks.append(slice);
    }

    return Extension {
        .label = @enumFromInt(label),
        .data = try blocks.toOwnedSlice(),
    };
}

