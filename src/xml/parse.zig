const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const print = std.debug.print;

const types = @import("./types.zig");
pub const Doc = types.Doc;

pub const Node = types.Node;
pub const find = @import("./find.zig");

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

fn simpleTypeName(comptime T: type) []const u8 {
    const full = @typeName(T);
    const idx = std.mem.lastIndexOf(u8, full, ".") orelse return full;
    // TODO: this could break
    return full[idx + 1 ..];
}

pub fn nodeToT(comptime T: type, alloc: Allocator, node: Node) !T {
    const info = @typeInfo(T);
    assert(info == .@"struct");

    var target: T = undefined;
    inline for (info.@"struct".fields) |field| {
        const field_info = @typeInfo(field.type);
        switch (field_info) {
            .@"struct" => {
                const child = find.getNode(node, field.name, .child) orelse return error.MissingField;
                const value = try nodeToT(field.type, alloc, child);
                @field(target, field.name) = value;
            },
            .array => {}, // parse [4] of struct -- no u8 or str allowed as array or pointer
            .pointer => |ptr| {
                if (ptr.child == u8) {
                    const value = try node.getProperty(field.name);
                    @field(target, field.name) = value;
                } else {
                    switch (@typeInfo(ptr.child)) {
                        .@"struct" => {
                            const parent = find.getNode(node, field.name, .child) orelse return error.MissingField;
                            const type_name = simpleTypeName(ptr.child);
                            const children = try find.getNodes(alloc, parent, type_name, .child);

                            var list = try std.ArrayList(ptr.child).initCapacity(alloc, 5);
                            errdefer list.deinit(alloc);
                            for (children) |child| {
                                const child_val = try nodeToT(ptr.child, alloc, child);
                                try list.append(alloc, child_val);
                            }
                            const slice = try list.toOwnedSlice(alloc);
                            @field(target, field.name) = slice;
                        },
                        else => {
                            @compileError("Unsupported Pointer child type - only structs for right now");
                        },
                    }
                }
            }, // parse []struct
            else => {
                const value = try getProperty(field.type, node, field.name);
                @field(target, field.name) = value;
            },
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
                    return std.enums.fromInt(T, digit) orelse return error.InvalidEnumTag;
                },
                else => unreachable, // unsupported for now
            }
            const digit = try std.fmt.parseInt(info.@"enum".tag_type, val, 10);
            return std.enums.fromInt(T, digit) orelse return error.InvalidEnumTag;
        },
        .pointer => |x| switch (x.child) {
            u8 => val,
            else => unreachable, // UNSUPPORTED -> requires separator logic
        },
        else => unreachable,
    };
}
