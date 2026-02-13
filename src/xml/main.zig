const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const types = @import("./types.zig");
pub const Doc = types.Doc;
pub const Node = types.Node;

pub const parse = @import("./parse.zig");

pub fn getUniqueNodes(comptime T: type, alloc: Allocator, head: Node, name: []const u8, key: fn (T) []const u8) !std.StringArrayHashMap(T) {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var map = std.StringArrayHashMap(T).init(alloc);
    try map.ensureTotalCapacity(80);
    try saveUniqueNode(T, alloc, head, name, &map, key);
    return map;
}

fn saveUniqueNode(comptime T: type, alloc: Allocator, node: Node, name: []const u8, map: *std.StringArrayHashMap(T), key: fn (T) []const u8) !void {
    var current: ?Node = node;

    while (current) |n| : (current = n.next()) {
        if (std.mem.eql(u8, n.name, name)) {
            // change field name for non structs
            const value = parse.nodeToT(T, alloc, n) catch |e| {
                std.log.err("parse err: {any}", .{e});
                continue;
            };
            const key_val = key(value);

            const owned_key = try alloc.dupe(u8, key_val);
            const res = try map.getOrPut(owned_key);
            if (res.found_existing) {
                continue;
            }
            res.value_ptr.* = value;
        }

        if (n.children()) |child| {
            try saveUniqueNode(T, alloc, child, name, map, key);
        }
    }
}
