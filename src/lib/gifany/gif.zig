const std = @import("std");
const img = @import("img.zig");
const ext = @import("ext.zig");
const color = @import("color.zig");

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

pub const GifData = struct {
    const GifValidateError = error{
        NotAGif,
        NotSupported,
    };

    const Self = @This();

    main_header: GifHeader = .{},
    global_colortable: ?[]color.RGBColor = null,
    extensions: ?[]ext.Extension = null,
    frames: ?[]img.Image = null,

    fn readHeader(self: *Self, reader: *const std.io.AnyReader) !void {
        const new_header = try reader.readStruct(GifHeader);

        if (!std.mem.eql(u8, "GIF", &new_header.header.signature)) {
            return GifValidateError.NotAGif;
        }

        if (new_header.header.version[0] != '8' or new_header.header.version[2] != 'a') {
            return GifValidateError.NotSupported;
        }

        if (new_header.header.version[1] != '9' and new_header.header.version[1] != '7') {
            return GifValidateError.NotSupported;
        }

        self.main_header = new_header;
    }

    fn readColorTable(self: *Self, reader: *const std.io.AnyReader, table_size: u8, alloc: *std.mem.Allocator) !void {
        const table_len = std.math.pow(u16, 2, table_size + 1);

        const new_slice = try alloc.alloc(color.RGBColor, table_len);
        for (0..new_slice.len) |index| {
            new_slice[index] = try reader.readStruct(color.RGBColor);
        }

        self.global_colortable = new_slice;
    }
};

pub const GifDecoder = struct {
    const Self = @This();
    const GifDecodingError = error{
        InvalidByteFlag,
    };

    reader: *const std.io.AnyReader,
    alloc: *std.mem.Allocator,

    pub fn decode(self: *const Self) !GifData {
        var data = GifData{};

        try data.readHeader(self.reader);

        // if there is no global color table to be load then we can safely avoid
        // adding one to `data`
        if (data.main_header.ls_descriptor.getGctableFlag() != 0) {
            const table_size = data.main_header.ls_descriptor.getGcTableSize();
            try data.readColorTable(self.reader, table_size, self.alloc);
        }

        var extensions = std.ArrayList(ext.Extension).init(self.alloc.*);
        defer extensions.deinit();

        var frames = std.ArrayList(img.Image).init(self.alloc.*);
        defer frames.deinit();

        for (0..3) |_| {
            const flag = try self.reader.readByte();
            switch (flag) {
                0x21 => {
                    const new_ext = try ext.readExtension(self.reader, self.alloc);
                    try extensions.append(new_ext);
                },

                0x2c => {
                    const new_frame = try img.readImage(self.reader);
                    try frames.append(new_frame);
                },

                else => return GifDecodingError.InvalidByteFlag,
            }
        }

        if (frames.items.len != 0) {
            data.frames = try frames.toOwnedSlice();
        }

        if (extensions.items.len != 0) {
            data.extensions = try extensions.toOwnedSlice();
        }

        return data;
    }

    pub fn init(reader: *const std.io.AnyReader, alloc: *std.mem.Allocator) !Self {
        return Self{
            .reader = reader,
            .alloc = alloc,
        };
    }
};

