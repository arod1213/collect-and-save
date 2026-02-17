const std = @import("std");
const lib = @import("collect_and_save");

export fn collectAndSave(filepath: [*c]const u8) c_int {
    if (filepath == null) {
        return -1;
    }

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    lib.collectAndSave(alloc, std.mem.span(filepath)) catch return -1;
    return 0;
}
