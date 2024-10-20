const std = @import("std");
const color = @import("color.zig");

const RGBColor = color.RGBColor;

const ImageDescriptor = extern struct {
    pos_left: u16 align(1),
    pos_top: u16 align(1),
    local_width: u16 align(1),
    local_height: u16 align(1),
    packed_fields: u8,
};

pub const Image = struct {
    const Self = @This();

    descriptor: ImageDescriptor,
    local_colortable: ?[]RGBColor = null,

    fn getLocalTableFlag(self: *const Self) !u8 {
        return self.descriptor.packed_fields >> 7;
    }
};

pub fn readImage(reader: *const std.io.AnyReader) !Image {
    const new_image = Image {
        .descriptor = try reader.readStruct(ImageDescriptor),
    };

    std.debug.print("is there a local table? {}\n", .{ try new_image.getLocalTableFlag() == 1 });

    return new_image;
}






