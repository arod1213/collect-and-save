const std = @import("std");
const Allocator = std.mem.Allocator;

// ensure dir was opened with iterate = true
pub fn fileInDir(alloc: Allocator, dir: std.fs.Dir, filename: []const u8) !bool {
    var iter = try dir.walk(alloc);
    defer iter.deinit();
    while (try iter.next()) |entry| {
        if (std.mem.eql(u8, @ptrCast(entry.basename), filename)) {
            return true;
        }
    }
    return false;
}
