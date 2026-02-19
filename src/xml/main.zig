const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;
const c = @cImport({
    @cInclude("libxml/parser.h");
    @cInclude("libxml/tree.h");
});

const types = @import("./types.zig");
pub const Doc = types.Doc;
pub const Node = types.Node;
const parse = @import("./parse.zig");

pub fn getUniqueNodes(comptime T: type, alloc: Allocator, head: Node, name: []const u8, key: fn (T) []const u8) !std.StringArrayHashMap(T) {
    // const info = @typeInfo(T);
    // assert(info == .@"struct");

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
            const value = parse.getParam(T, alloc, n, null) catch |e| {
                std.log.err("parse err: {any}", .{e});
                continue;
            };
            // const value = parseNodeToT(T, alloc, &n, "Value") catch continue;
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

pub fn parseNodeToT(comptime T: type, alloc: Allocator, node: *const Node, property_name: [:0]const u8) !T {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var target: T = undefined;
    var child = node.children();

    // TODO: this doesnt check all fields are initialized
    var map = std.StringHashMap(bool).init(alloc);
    defer map.deinit();

    while (child) |ch| : (child = ch.next()) {
        const value = ch.getProperty(property_name) catch continue;
        try setField(T, &target, ch.name, value, &map);
    }

    inline for (info.@"struct".fields) |field| {
        _ = map.get(field.name) orelse return error.MissingField;
    }
    return target;
}

fn setField(comptime T: type, target: *T, name: []const u8, value: []const u8, map: *std.StringHashMap(bool)) !void {
    const info = @typeInfo(T);
    assert(info == .@"struct");
    inline for (info.@"struct".fields) |field| {
        if (std.ascii.eqlIgnoreCase(field.name, name)) {
            const variable = valToT(field.type, value) catch blk: {
                if (field.defaultValue()) |def| {
                    break :blk def;
                }
                return error.MissingField;
            };
            @field(target.*, field.name) = variable;
            try map.put(field.name, true);
        }
    }
}

fn valToT(comptime T: type, val: []const u8) !T {
    const info = @typeInfo(T);

    return switch (info) {
        .int => try std.fmt.parseInt(T, val, 10),
        .float => try std.fmt.parseFloat(T, val),
        .optional => |opt| if (val.len == 0) return null else try valToT(
            opt.child,
            val,
        ),
        .@"enum" => {
            const tag_info = @typeInfo(info.@"enum".tag_type);
            switch (tag_info) {
                .int, .float => {
                    const digit = std.fmt.parseInt(info.@"enum".tag_type, val, 10) catch {
                        // fallback to parse by string name
                        return std.meta.stringToEnum(T, val) orelse error.InvalidEnumTag;
                    };
                    return try std.meta.intToEnum(T, digit);
                },
                else => unreachable, // unsupported for now
            }
            const digit = try std.fmt.parseInt(info.@"enum".tag_type, val, 10);
            return try std.meta.intToEnum(T, digit);
        },
        .pointer => |x| switch (x.child) {
            u8 => val,
            else => unreachable, // unsupported for now
        },
        else => unreachable,
    };
}
