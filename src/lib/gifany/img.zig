const std = @import("std");
const color = @import("color.zig");
const block = @import("block.zig");

const RGBColor = color.RGBColor;

const ImageDescriptor = extern struct {
    pos_left: u16 align(1),
    pos_top: u16 align(1),
    local_width: u16 align(1),
    local_height: u16 align(1),
    packed_fields: u8,
};

const LZWData = struct {
    min_codesize: u8 = 0x00,
    raw_data: ?[]u8 = null,
};

pub const Image = struct {
    const Self = @This();

    descriptor: ImageDescriptor,
    local_colortable: ?[]RGBColor = null,
    img_data: LZWData,

    fn getLocalTableFlag(self: *const Self) !u8 {
        return self.descriptor.packed_fields >> 7;
    }
};

pub fn readImage(reader: *const std.io.AnyReader, alloc: *std.mem.Allocator) !Image {
    const new_image = Image{
        .descriptor = try reader.readStruct(ImageDescriptor),
        .img_data = .{
            .min_codesize = try reader.readByte(),
            .raw_data = try block.readBlocksMerge(reader, alloc),
        }
    };

    return new_image;
}






