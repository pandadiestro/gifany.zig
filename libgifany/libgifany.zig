const std = @import("std");
const image = @import("layout.zig");
const lzw = @import("lzw.zig");

pub const color = @import("color.zig");

const expected_endian = std.builtin.Endian.little;

pub const DecodeError = error {
    NotAGif,
    EndOfIteration,

    UnexpectedEof,
    UnexpectedIOError,

    InvalidVersion,
    InvalidIntroducer,

    MissingGlobalColorTable,
};

const Gifversion = enum {
    ver_89a,
    ver_87a,
};

const IntroducerLabel = enum(u8) {
    extension = 0x21,
    image = 0x2c,
    trailer = 0x3b,
};

const LogicalScreenDescriptor = extern struct {
    ls_width: u16 align(1),
    ls_height: u16 align(1),

    packed_fields: packed struct {
        global_color_table_flag: u1,
        color_resolution: u3,
        sort_flag: u1,
        global_color_table_size: u3,
    },

    bg_color_index: u8,
    pixel_aspect_ratio: u8,
};

pub const GifDecoder = struct {
    const Self = @This();

    version: Gifversion,
    ls_descriptor: LogicalScreenDescriptor,
    global_color_table: ?[]color.Rgbcolor = null,

    reader: *std.io.AnyReader,
    allocator: *std.mem.Allocator,

    lzw_binbuffer: std.io.FixedBufferStream([]u8),

    pub fn init(reader: *std.io.AnyReader, alloc: *std.mem.Allocator) !GifDecoder {
        const init_version = try readVersion(reader);
        const init_ls_descriptor = try readLogicalScreenDescriptor(reader);

        const canvas_size: usize = @as(usize, init_ls_descriptor.ls_height) * @as(usize, init_ls_descriptor.ls_width);
        const init_fixed_buffer_memory = try alloc.alloc(u8, canvas_size);
        const init_lzw_binbuffer = std.io.fixedBufferStream(init_fixed_buffer_memory);

        if (init_ls_descriptor.packed_fields.global_color_table_flag == 0) {
            return GifDecoder{
                .version = init_version,
                .ls_descriptor = init_ls_descriptor,

                .reader = reader,
                .allocator = alloc,

                .lzw_binbuffer = init_lzw_binbuffer,
            };
        }

        const gct_size_factor: u4 = @as(u4, init_ls_descriptor.packed_fields.global_color_table_size) + 1;
        const gct_size = @as(u16, 1) << gct_size_factor;

        const init_global_color_table = try alloc.alloc(color.Rgbcolor, gct_size);
        errdefer alloc.free(init_global_color_table);

        for (0..gct_size) |index| {
            init_global_color_table[index] = try reader.readStructEndian(color.Rgbcolor, expected_endian);
        }

        return GifDecoder{
            .version = init_version,
            .ls_descriptor = init_ls_descriptor,
            .global_color_table = init_global_color_table,

            .reader = reader,
            .allocator = alloc,

            .lzw_binbuffer = init_lzw_binbuffer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.lzw_binbuffer.buffer);

        if (self.global_color_table) |*gct| {
            self.allocator.free(gct.*);
        }
    }

    fn readVersion(reader: *std.io.AnyReader) !Gifversion {
        var buff: [6]u8 = undefined;

        const read_data = try reader.read(buff[0..]);
        if (read_data != 6) {
            return DecodeError.UnexpectedIOError;
        }

        if (!std.mem.eql(u8, buff[0..3], "GIF")) {
            return DecodeError.NotAGif;
        }

        if (std.mem.eql(u8, buff[3..], "89a")) {
            return Gifversion.ver_89a;
        } else if (std.mem.eql(u8, buff[3..], "87a")) {
            return Gifversion.ver_87a;
        }

        return DecodeError.InvalidVersion;
    }

    fn readLogicalScreenDescriptor(reader: *std.io.AnyReader) !LogicalScreenDescriptor {
        return try reader.readStructEndian(LogicalScreenDescriptor, expected_endian);
    }

    fn readLocalColorTable(self: *Self, container: *image.ImageData) !void {
        const lct_size_factor: u4 = @as(u4, container.descriptor.packed_fields.local_color_table_size) + 1;
        const lct_size = @as(u16, 1) << lct_size_factor;

        container.local_color_table = try self.allocator.alloc(color.Rgbcolor, lct_size);
        errdefer self.allocator.free(container.local_color_table.?);

        for (0..lct_size) |index| {
            container.local_color_table.?[index] = try self.reader.readStructEndian(color.Rgbcolor, expected_endian);
        }
    }

    fn readFrameImagedata(self: *Self) !image.ImageData {
        const init_descriptor = try self.reader.readStructEndian(image.ImageDescriptor, expected_endian);
        const image_size: usize = @as(usize, init_descriptor.image_width) * @as(usize, init_descriptor.image_height);

        var ret = image.ImageData{
            .descriptor = init_descriptor,
            .lzw_min_codesize = try self.reader.readByte(),
            .pixel_data = try self.allocator.alloc(color.Rgbcolor, image_size),
        };

        if (ret.descriptor.packed_fields.local_color_table_flag == 1) {
            try self.readLocalColorTable(&ret);
        }

        self.lzw_binbuffer.reset();

        if (self.lzw_binbuffer.buffer.len < image_size) {
            self.allocator.free(self.lzw_binbuffer.buffer);
            self.lzw_binbuffer.buffer = try self.allocator.alloc(u8, image_size);
        }

        var raw_buffer: [256]u8 = undefined;
        while (true) {
            const block_size = try self.reader.readByte();
            if (block_size == 0) break;

            const slice = raw_buffer[0..block_size];
            const read_data = try self.reader.read(slice);
            if (read_data != block_size) return DecodeError.UnexpectedIOError;

            const written = try self.lzw_binbuffer.write(slice);
            if (written != block_size) return DecodeError.UnexpectedIOError;
        }

        self.lzw_binbuffer.reset();

        const color_table: []color.Rgbcolor = self.global_color_table orelse ret.local_color_table orelse {
            return DecodeError.MissingGlobalColorTable;
        };

        var lzw_reader = self.lzw_binbuffer.reader().any();
        var bit_stream = lzw.BitStream(u16).init(&lzw_reader);

        try lzw.decodeStream(&bit_stream, ret.lzw_min_codesize, &color_table, &ret.pixel_data);

        return ret;
    }

    fn readExtension(self: *Self) !void {
        _ = try self.reader.readByte();

        var subblock_buffer: [256]u8 = undefined;
        while (true) {
            const block_size = try self.reader.readByte();
            if (block_size == 0) {
                break;
            }

            const read_data = try self.reader.read(subblock_buffer[0..block_size]);
            if (read_data != block_size) {
                return DecodeError.UnexpectedIOError;
            }
        }
    }

    pub fn nextFrame(self: *Self) !image.ImageData {
        loop: {
            while (true) {
                const introducer = try self.reader.readEnum(IntroducerLabel, expected_endian);
                switch (introducer) {
                    IntroducerLabel.trailer => return DecodeError.EndOfIteration,
                    IntroducerLabel.image => break: loop,
                    IntroducerLabel.extension => try self.readExtension(),
                }
            }
        }

        return self.readFrameImagedata();
    }
};

