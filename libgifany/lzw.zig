const std = @import("std");
const color = @import("color.zig");

pub const expected_endian = std.builtin.Endian.little;

const MaskError = error {
    MasklengthTooBig,
};

inline fn bitmask(len: u8) !u8 {
    if (len > 8) {
        return MaskError.MasklengthTooBig;
    }

    if (len == 8) {
        return 0xff;
    }

    return (@as(u8, 1) << @intCast(len)) - 1;
}

pub fn BitStream(T: type) type {
    return struct {
        const Self = @This();
        pub const BitStreamError = error {
            ReadTooBig,
        };

        bits_remaining: u8 = 0x00,
        bit_buffer: u8 = 0x00,

        reader: *std.io.AnyReader,

        pub fn init(reader: *std.io.AnyReader) Self {
            return Self{
                .reader = reader,
            };
        }

        fn refill(self: *Self) !void {
            self.bit_buffer = try self.reader.readInt(@TypeOf(self.bit_buffer), expected_endian);
            self.bits_remaining = @bitSizeOf(@TypeOf(self.bit_buffer));
        }

        /// reads `len` bits from right to left into an unsigned integer of type `T`
        pub fn readBits(self: *Self, len: u8) !T {
            comptime typever: {
                switch (@typeInfo(T)) {
                    .Int => {
                        switch (@typeInfo(T).Int.signedness) {
                            .unsigned => break :typever,
                            else => @compileError("T must be an unsigned integer\n"),
                        }
                    },

                    else => {
                        @compileError("T must be an unsigned integer\n");
                    },
                }
            }

            if (len > @bitSizeOf(T)) {
                return BitStreamError.ReadTooBig;
            }

            var ret: T = 0x00;
            var remainder: usize = len;

            while (remainder != 0) {
                if (self.bits_remaining == 0) {
                    try self.refill();
                }

                const to_extract = @min(remainder, self.bits_remaining);
                const mask = try bitmask(to_extract);

                ret |= @as(T,(self.bit_buffer & mask)) << @intCast(len - remainder);

                self.bits_remaining -= to_extract;
                self.bit_buffer =
                    if (to_extract == 8)
                        0x00
                    else
                        self.bit_buffer >> @intCast(to_extract);

                remainder -= to_extract;
            }

            return ret;
        }
    };
}

const LzwError = error {
    InvalidMinCodesize,
    InvalidClearCode,
};

pub fn decodeStream(stream: *BitStream(u16), min_codesize: u8, color_table: *const []color.Rgbcolor, color_buffer: *[]color.Rgbcolor) !void {
    if (min_codesize < 2 or min_codesize > 12) {
        return LzwError.InvalidMinCodesize;
    }

    var new_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer new_arena.deinit();

    var allocator = new_arena.allocator();

    var read_length: u8 = min_codesize + 1;

    const clear_code = try stream.readBits(read_length);
    if (clear_code != color_table.len) {
        return LzwError.InvalidClearCode;
    }

    const eot_code = clear_code + 1;

    const code_table_size = 1 << 12;
    var code_table: [code_table_size][]u16 = undefined;
    var code_table_offset: usize = 0x00;

    for (0..color_table.len) |color_index| {
        var mem = try allocator.alloc(u16, 1);
        mem[0] = @intCast(color_index);
        code_table[code_table_offset] = mem;
        code_table_offset += 1;
    }

    code_table[code_table_offset] = (@constCast(&[_]u16{ clear_code }));
    code_table_offset += 1;

    code_table[code_table_offset] = (@constCast(&[_]u16{ eot_code }));
    code_table_offset += 1;

    var color_buffer_offset: usize = 0;

    const first_code = try stream.readBits(read_length);
    color_buffer.*[color_buffer_offset] = color_table.*[first_code];
    color_buffer_offset += 1;

    var last_code: u16 = first_code;

    while (true) {
        const code_index = try stream.readBits(read_length);
        if (code_index == eot_code) {
            return;
        }

        if (code_index == clear_code) {
            code_table_offset = clear_code + 2;
            read_length = min_codesize + 1;

            const new_first_code = try stream.readBits(read_length);
            color_buffer.*[color_buffer_offset] = color_table.*[new_first_code];
            color_buffer_offset += 1;

            last_code = new_first_code;
            continue;
        }

        const last_code_entry = code_table[last_code];

        const k: u16 = k_blk: {
            if (code_index < code_table_offset) {
                const code_entry = code_table[code_index];
                const new_k = code_entry[0];

                for (code_entry) |code_entry_el| {
                    color_buffer.*[color_buffer_offset] = color_table.*[code_entry_el];
                    color_buffer_offset += 1;
                }

                break :k_blk new_k;
            } else {
                const new_k = last_code_entry[0];

                for (last_code_entry) |last_code_entry_el| {
                    color_buffer.*[color_buffer_offset] = color_table.*[last_code_entry_el];
                    color_buffer_offset += 1;
                }

                color_buffer.*[color_buffer_offset] = color_table.*[new_k];
                color_buffer_offset += 1;

                break :k_blk new_k;
            }
        };

        var new_codetable_entry = try allocator.alloc(u16, last_code_entry.len + 1);
        @memcpy(new_codetable_entry[0..last_code_entry.len], last_code_entry);
        new_codetable_entry[new_codetable_entry.len - 1] = k;

        code_table[code_table_offset] = (new_codetable_entry);
        code_table_offset += 1;

        last_code = code_index;

        if (code_table_offset >= (@as(usize, 1) << @intCast(read_length))) {
            read_length += 1;
        }
    }

    return;
}


test {
    const buffer = [_]u8{ 0x0f } ** 20;

    var f_buffer = std.io.fixedBufferStream(&buffer);
    var reader = f_buffer.reader().any();

    var ctx = BitStream.init(&reader);

    std.debug.print("read of 9: {b}\nremainder: {b}\nhow many are there? {}\n", .{
        try ctx.readBits(u16, 9),
        ctx.bit_buffer,
        ctx.bits_remaining,
    });

    std.debug.print("\n", .{});

    std.debug.print("read of 9: {b}\nremainder: {b}\nhow many are there? {}\n", .{
        try ctx.readBits(u16, 9),
        ctx.bit_buffer,
        ctx.bits_remaining,
    });

    std.debug.print("\n", .{});
}

