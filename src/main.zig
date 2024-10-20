const std = @import("std");
const gifany = @import("./lib/gifany/gif.zig");


pub fn main() !void {
    const path = "/home/bauer/projects/giffer/src/static/earth_sample.gif";
    const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_only });
    defer file.close();

    var new_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    var new_alloc = new_arena.allocator();
    const reader = file.reader().any();

    const decoder = try gifany.GifDecoder.init(&reader, &new_alloc);
    const data = try decoder.decode();

    for (0..data.frames.?.len) |index| {
        switch (data.frames.?[index]) {
            .Ext => std.debug.print("data:\n  {}\n", .{data.frames.?[index].Ext}),
            .Image => std.debug.print("data:\n  {}\n", .{data.frames.?[index].Image}),
        }
    }
}

