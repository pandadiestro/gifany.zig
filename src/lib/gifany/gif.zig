const std = @import("std");
const img = @import("img.zig");
const color = @import("color.zig");

const RGBColor = color.RGBColor;

/// Main gif header data (up to but not including the global color table)
pub const GifHeader = extern struct {
    const HeaderBlock = extern struct {
        /// should be 'GIF'
        signature: [3]u8 align(1) = .{0} ** 3,

        /// should be a valid GIF version: '89a' || '87a'
        version: [3]u8 align(1) = .{0} ** 3,
    };

    const LSDescriptor = extern struct {
        const Self = @This();

        canvas_width: u16 align(1) = 0,
        canvas_height: u16 align(1) = 0,

        packed_fields: u8 = 0,
        bgcolor_index: u8 = 0,
        pixel_aspratio: u8 = 0,


        fn getGctableFlag(self: Self) u8 {
            return self.packed_fields & 0b10000000;
        }

        fn getGcTableSize(self: Self) u8 {
            return self.packed_fields & 0b00000111;
        }
    };

    header: HeaderBlock = .{},
    ls_descriptor: LSDescriptor = .{},
};

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

const ImageOrExtType = enum(u8) {
    Image = 0x2c,
    Ext = 0x21,
};

const ImageOrExt = union(ImageOrExtType) {
    Image: img.Image,
    Ext: Extension,
};

pub const GifData = struct {
    const GifValidateError = error {
        NotAGif,
        NotSupported,
    };

    const Self = @This();

    main_header: GifHeader,
    global_colortable: ?[]RGBColor = null,
    frames: ?[]ImageOrExt = null,

    fn validate(self: *Self) GifValidateError!void {
        if (!std.mem.eql(u8, "GIF", &self.main_header.header.signature)) {
            return GifValidateError.NotAGif;
        }

        if (self.main_header.header.version[0] != '8' or self.main_header.header.version[2] != 'a') {
            return GifValidateError.NotSupported;
        } if (self.main_header.header.version[1] != '9' and self.main_header.header.version[1] != '7') {
            return GifValidateError.NotSupported;
        }
    }
};

pub const GifDecoder = struct {
    const Self = @This();

    reader: *const std.io.AnyReader,
    alloc: *std.mem.Allocator,

    fn readColorTable(self: *const Self, table_size: u8) ![]RGBColor {
        const table_len = std.math.pow(u16, 2, table_size + 1);

        const new_slice = try self.alloc.alloc(RGBColor, table_len);
        for (0..new_slice.len) |index| {
            new_slice[index] = try self.reader.readStruct(RGBColor);
        }

        return new_slice;
    }

    fn readExtension(self: *const Self) !Extension {
        const label = try self.reader.readByte();

        var blocks = std.ArrayList([]u8).init(self.alloc.*);
        defer blocks.deinit();

        var data_size = try self.reader.readByte();
        while (data_size != 0) : (data_size = try self.reader.readByte()) {
            const slice = try self.alloc.alloc(u8, data_size);
            if (try self.reader.read(slice) != data_size) {
                self.alloc.free(slice);
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

    pub fn decode(self: *const Self) !GifData {
        var frames = std.ArrayList(ImageOrExt).init(self.alloc.*);
        defer frames.deinit();

        var data = GifData {
            .main_header = try self.reader.readStruct(GifHeader),
        };

        try data.validate();

        // if there is no global color table to be load then we can safely avoid
        // adding one to `data`
        if (data.main_header.ls_descriptor.getGctableFlag() != 0) {
            const table_size = data.main_header.ls_descriptor.getGcTableSize();
            data.global_colortable = try self.readColorTable(table_size);
        }

        for (0..3) |_| {
            const flag: ImageOrExtType = @enumFromInt(try self.reader.readByte());
            const new = switch (flag) {
                .Ext => ImageOrExt{
                    .Ext = try self.readExtension(),
                },

                .Image => ImageOrExt{
                    .Image = try img.readImage(self.reader),
                },
            };

            try frames.append(new);
        }

        if (frames.items.len != 0) {
            data.frames = try frames.toOwnedSlice();
        }

        return data;
    }

    pub fn init(reader: *const std.io.AnyReader, alloc: *std.mem.Allocator) !Self {
        return Self {
            .reader = reader,
            .alloc = alloc,
        };
    }
};

