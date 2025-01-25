const std = @import("std");
const libgifany = @import("libgifany");

pub fn printTermPixel(color: *libgifany.color.Rgbcolor) void {
    const block = "█";


    std.debug.print("\x1B[38;2;{};{};{}m\x1B[38;2;{};{};{}m{s}\x1B[0m", .{
        color.R,
        color.G,
        color.B,
        color.R,
        color.G,
        color.B,
        block,
    });
}

pub fn main() !void {
    const sample_file = try std.fs.cwd().openFile("samples/earth.gif", std.fs.File.OpenFlags{
        .mode = .read_only,
    });

    defer sample_file.close();

    var buffered = std.io.bufferedReader(sample_file.reader().any());
    var buf_reader = buffered.reader().any();

    var new_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var new_alloc = new_arena.allocator();

    const start_time = std.time.milliTimestamp();
    var new_decoder = try libgifany.GifDecoder.init(&buf_reader, &new_alloc);
    defer new_decoder.deinit();

    //var index: usize = 0;

    const frame = try new_decoder.nextFrame();
    const frame_size: usize = @as(usize, frame.descriptor.image_height) * @as(usize, frame.descriptor.image_width);
    std.debug.assert(frame_size <= 400*400);

    //std.debug.print("frame #{}\n", .{ index });

    for (0..frame.descriptor.image_height) |h_index| {
        for (0..frame.descriptor.image_width) |w_index| {
            var color = frame.pixel_data[h_index * frame.descriptor.image_width + w_index];
            printTermPixel(&color);
        }

        std.debug.print("\n", .{});
    }

    //while (new_decoder.nextFrame()) |*frame| : (index += 1) {
//
    //} else |err| {
    //    if (err != libgifany.DecodeError.EndOfIteration) return err;
    //}

    const end_time = std.time.milliTimestamp();

    std.debug.print("traversal took {}ms\n", .{ end_time - start_time });
}


