const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;

const types = @import("./types.zig");
pub const Doc = types.Doc;

pub const Node = types.Node;

pub const Direction = enum { child, neighbor };
pub fn getNodes(alloc: Allocator, parent: Node, tag_name: []const u8, direction: Direction) ![]Node {
    var list = try std.ArrayList(Node).initCapacity(alloc, 4);
    errdefer list.deinit(alloc);

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
