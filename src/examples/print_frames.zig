const std = @import("std");
const gifany = @import("gifany");

pub fn main() !void {
    const path = "/home/bauer/projects/gifany/src/static/earth_sample.gif";
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    var new_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var new_alloc = new_arena.allocator();
    const reader = file.reader().any();

    const decoder = try gifany.GifDecoder.init(&reader, &new_alloc);
    const data = try decoder.decode();

    for (0..data.frames.?.len) |index| {
        std.debug.print("frame #{}:\n    {}\n", .{
            index,
            data.frames.?[index],
        });
    }

    std.debug.print("\n\n", .{});

    for (0..data.extensions.?.len) |index| {
        std.debug.print("extension #{}:\n    {}\n", .{
            index,
            data.extensions.?[index],
        });
    }
}

