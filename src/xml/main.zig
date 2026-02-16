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

pub fn noOp(x: Node) !Node {
    return x;
}

pub fn mainDoc(path: []const u8) !void {
    var doc = try Doc.init(path);
    defer doc.deinit();

    if (doc.root == null) return error.NoRoot;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const samples = try nodesByName(Node, alloc, doc.root.?, "SampleRef", noOp);
    std.log.info("found {d} samples", .{samples.len});
}

// transform used to prevent duplicate looping to convert Node to type T
// errors are ignored - aka Node will not be added if it cannot be parsed
pub fn nodesByName(comptime T: type, alloc: Allocator, head: Node, name: []const u8, transform: fn (Node) anyerror!T) ![]T {
    var list = try std.ArrayList(T).initCapacity(alloc, 5);
    defer list.deinit(alloc);

    try nodesByNameAcc(T, alloc, &list, head, name, transform);

    return try list.toOwnedSlice(alloc);
}

fn nodesByNameAcc(comptime T: type, alloc: Allocator, list: *std.ArrayList(T), node: Node, name: []const u8, transform: fn (Node) anyerror!T) !void {
    var current: ?Node = node;

    while (current) |n| : (current = n.next()) {
        if (std.mem.eql(u8, n.name, name)) {
            const x = transform(n) catch continue;
            try list.append(alloc, x);
        }

        if (n.children()) |child| {
            try nodesByNameAcc(T, alloc, list, child, name, transform);
        }
    }
}

pub fn parseNodeToT(comptime T: type, node: *const Node, property_name: [:0]const u8) !T {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var target: T = undefined;
    var child = node.children();

    // TODO: this doesnt check all fields are initialized
    while (child) |ch| : (child = ch.next()) {
        const value = ch.getProperty(property_name) catch continue;
        try setField(T, &target, ch.name, value);
    }
    return target;
}

fn setField(comptime T: type, target: *T, name: []const u8, value: []const u8) !void {
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
