const std = @import("std");

pub fn readBlocks(reader: *const std.io.AnyReader, alloc: *std.mem.Allocator) ![][]u8 {
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

    return blocks.toOwnedSlice();
}

