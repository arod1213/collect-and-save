const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;

const parse = @import("./parse.zig");
const types = @import("./types.zig");
const Doc = types.Doc;
const Node = types.Node;

pub fn getNodesUnique(comptime T: type, alloc: Allocator, head: Node, name: []const u8, key: fn (T) []const u8) !std.StringArrayHashMap(T) {
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
            const res = try map.getOrPut(key_val);
            if (res.found_existing) {
                continue;
            }

            const owned_key = try alloc.dupe(u8, key_val);
            res.key_ptr.* = owned_key;
            res.value_ptr.* = value;
        }

        if (n.children()) |child| {
            try saveUniqueNode(T, alloc, child, name, map, key);
        }
    }
}

pub const Direction = enum { child, neighbor };
pub fn getNodes(alloc: Allocator, parent: Node, tag_name: []const u8, direction: Direction) ![]Node {
    var list = try std.ArrayList(Node).initCapacity(alloc, 4);
    errdefer list.deinit(alloc);

    var start = switch (direction) {
        .child => parent.children(),
        .neighbor => parent.next(), // should this just be parent?
    };
    while (start) |ch| : (start = ch.next()) {
        switch (ch.node_type) {
            .Element => {},
            else => continue,
        }
        if (std.mem.eql(u8, tag_name, ch.name)) {
            try list.append(alloc, ch);
        }
    }
    return try list.toOwnedSlice(alloc);
}

pub fn getNode(parent: Node, tag_name: []const u8, direction: Direction) ?Node {
    var start = switch (direction) {
        .child => parent.children(),
        .neighbor => parent.next(),
    };
    while (start) |ch| : (start = ch.next()) {
        switch (ch.node_type) {
            .Element => {},
            else => continue,
        }
        if (std.mem.eql(u8, tag_name, ch.name)) {
            return ch;
        }
    }
    return null;
}
