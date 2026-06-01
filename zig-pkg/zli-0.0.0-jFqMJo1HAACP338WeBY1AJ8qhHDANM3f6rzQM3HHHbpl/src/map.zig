const std = @import("std");
const Allocator = std.mem.Allocator;
const span = std.mem.span;

pub fn argsToMap(alloc: Allocator, args: [][*:0]u8) !std.StringHashMap([]const u8) {
    if (args.len < 2) {
        return error.NoArgs;
    }
    var map = std.StringHashMap([]const u8).init(alloc);

    const window = 2;
    var iter = std.mem.window([*:0]const u8, args[1..], window, window);

    while (iter.next()) |set| {
        if (set.len != window) break;
        var key = span(set[0]);
        const value = span(set[1]);

        if (key.len == 0 or value.len == 0) return error.InvalidArgs;

        var hyphens: usize = 0;
        while (key[0] == '-') : (hyphens += 1) {
            if (key.len < 2) return error.InvalidKey;
            if (hyphens > 1) return error.InvalidHyphens;
            key = key[1..];
        }
        std.log.info("KEY OF {s}", .{key});

        try map.put(key, value);
    }

    return map;
}
