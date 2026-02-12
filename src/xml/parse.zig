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

fn getProperty(comptime T: type, node: Node, property_name: []const u8) !T {
    assert(@typeInfo(T) != .@"struct");

    const val_str = try node.getProperty(@ptrCast(property_name));
    return try strToT(T, val_str);
}

fn getChild(parent: Node, field_name: []const u8) ?Node {
    var child = parent.children();
    while (child) |ch| : (child = ch.next()) {
        switch (ch.node_type) {
            .Element => {},
            else => continue,
        }
        std.log.info("looking at node {s}", .{ch.name});
        if (std.mem.eql(u8, field_name, ch.name)) {
            return ch;
        }
    }
    return null;
}

pub fn nodeToT(comptime T: type, alloc: Allocator, node: Node) !T {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var target: T = undefined;
    inline for (info.@"struct".fields) |field| {
        const field_info = @typeInfo(field.type);
        if (field_info != .@"struct") {
            std.log.info("searching for {s} prop {s}", .{ node.name, field.name });
            const value = try getProperty(field.type, node, field.name);
            @field(target, field.name) = value;
        } else {
            std.log.info("searching for {s} child {s}", .{ node.name, field.name });
            const child = getChild(node, field.name) orelse return error.MissingChildField;
            const value = try nodeToT(field.type, alloc, child);
            @field(target, field.name) = value;
        }
    }
    return target;
}

fn strToT(comptime T: type, val: []const u8) !T {
    const info = @typeInfo(T);

    return switch (info) {
        .int => try std.fmt.parseInt(T, val, 10),
        .float => try std.fmt.parseFloat(T, val),
        .optional => |opt| if (val.len == 0) return null else try strToT(
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
            else => unreachable, // UNSUPPORTED -> requires separator logic
        },
        else => unreachable,
    };
}
