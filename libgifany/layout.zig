const std = @import("std");
const color = @import("color.zig");

/// The Image Descriptor contains the parameters necessary to process a table
/// based image.
/// The coordinates given in this block refer to coordinates within the Logical
/// Screen, and are given in pixels.
/// This block is a Graphic-Rendering Block, optionally preceded by one or more
/// Control blocks such as the Graphic Control Extension, and may be optionally
/// followed by a Local Color Table; the Image Descriptor is always followed by
/// the image data.
pub const ImageDescriptor = extern struct {
    left_offset: u16 align(1),
    top_offset: u16 align(1),

    image_width: u16 align(1),
    image_height: u16 align(1),

    packed_fields: packed struct {
        local_color_table_flag: u1,
        interlace_flag: u1,
        sort_flag: u1,
        reserved: u2,
        local_color_table_size: u3,
    },
};

/// Each image in the Data Stream is composed of an Image Descriptor, an
/// optional Local Color Table, and the image data.
pub const ImageData = struct {
    descriptor: ImageDescriptor,
    local_color_table: ?[]color.Rgbcolor = null,

    lzw_min_codesize: u8 = 0x00,

    pixel_data: []color.Rgbcolor,
};


